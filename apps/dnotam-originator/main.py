import logging
import os
from datetime import datetime, timezone

from prometheus_client import start_http_server as start_metrics_server
import httpx
from fastapi import FastAPI
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from opentelemetry import baggage as baggage_api, context, metrics, trace
from opentelemetry._logs import set_logger_provider
from opentelemetry.baggage.propagation import W3CBaggagePropagator
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.propagate import inject, set_global_textmap
from opentelemetry.propagators.composite import CompositePropagator
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.exporter.prometheus import PrometheusMetricReader
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

SERVICE_NAME = "dnotam-originator"
SERVICE_VERSION = "1.0.0"

_resource = Resource.create({
    "service.name": SERVICE_NAME,
    "service.version": SERVICE_VERSION,
    "deployment.environment": os.getenv("DEPLOYMENT_ENV", "local"),
    "service.namespace": "lisbon-airport",
})

_otlp_endpoint = os.getenv("OTLP_ENDPOINT", "http://tempo:4317")

_provider = TracerProvider(resource=_resource)
_provider.add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter(endpoint=_otlp_endpoint))
)
trace.set_tracer_provider(_provider)
_tracer = trace.get_tracer(SERVICE_NAME, SERVICE_VERSION)

set_global_textmap(CompositePropagator([
    TraceContextTextMapPropagator(),
    W3CBaggagePropagator(),
]))

_loki_url = os.getenv("LOKI_OTLP_ENDPOINT", "http://loki:3100/otlp/v1/logs")
_log_provider = LoggerProvider(resource=_resource)
_log_provider.add_log_record_processor(
    BatchLogRecordProcessor(OTLPLogExporter(endpoint=_loki_url))
)
set_logger_provider(_log_provider)

_otel_handler = LoggingHandler(logger_provider=_log_provider)
logging.getLogger().addHandler(_otel_handler)
LoggingInstrumentor().instrument(set_logging_format=True)

_logger = logging.getLogger(SERVICE_NAME)
_logger.setLevel(logging.INFO)

_metric_reader = PrometheusMetricReader()
_meter_provider = MeterProvider(resource=_resource, metric_readers=[_metric_reader])
metrics.set_meter_provider(_meter_provider)
_meter = metrics.get_meter(SERVICE_NAME, SERVICE_VERSION)

_dispatch_counter = _meter.create_counter(
    "dnotam.dispatches",
    unit="1",
    description="Number of DNOTAM dispatch requests",
)
_dispatch_error_counter = _meter.create_counter(
    "dnotam.dispatch.errors",
    unit="1",
    description="Number of failed DNOTAM dispatch requests",
)
_dispatch_duration = _meter.create_histogram(
    "dnotam.dispatch.duration",
    unit="ms",
    description="Duration of DNOTAM dispatch requests",
)

start_metrics_server(int(os.getenv("METRICS_PORT", "9464")))

PUBLISHER_URL = os.getenv("PUBLISHER_URL", "http://dnotam-publisher:8080")
GRAFANA_URL = os.getenv("GRAFANA_URL", "http://localhost:3000")

_VALID_NOTAM = {
    "notam_id": "A0001/26",
    "aerodrome": "LPPT",
    "notam_type": "RUNWAY_CLOSURE",
    "runway": "27R",
    "effective_from": "2026-06-07T22:00:00Z",
    "effective_to": "2026-06-08T06:00:00Z",
}

_INVALID_NOTAM = {
    "notam_id": "A0002/26",
    "aerodrome": "LPPT",
    "notam_type": "RUNWAY_CLOSURE",
    "runway": "ZZ9",
    "effective_from": "2026-06-07T22:00:00Z",
    "effective_to": "2026-06-08T06:00:00Z",
}

app = FastAPI()
FastAPIInstrumentor.instrument_app(app)
HTTPXClientInstrumentor().instrument()
app.mount("/static", StaticFiles(directory="static"), name="static")


def _swim_log(event_type: str, message: str, notam: dict, traceparent: str) -> None:
    _logger.info(
        "[SERVICE_LAYER][%s] %s | notam_id=%s aerodrome=%s runway=%s traceparent=%s",
        event_type, message,
        notam["notam_id"], notam["aerodrome"], notam["runway"],
        traceparent,
        extra={
            "swim_perimeter": "SERVICE_LAYER",
            "event_type": event_type,
            "notam.id": notam["notam_id"],
            "notam.aerodrome": notam["aerodrome"],
            "notam.type": notam["notam_type"],
            "notam.runway": notam["runway"],
            "service_context": "dNOTAM",
            "traceparent": traceparent,
        },
    )


@app.get("/config")
async def config():
    return {"grafana_url": GRAFANA_URL}


@app.get("/")
async def index():
    return FileResponse("static/index.html")


@app.post("/publish/valid")
async def publish_valid():
    return await _publish(_VALID_NOTAM)


@app.post("/publish/invalid")
async def publish_invalid():
    return await _publish(_INVALID_NOTAM)


async def _publish(payload: dict) -> dict:
    start = datetime.now(timezone.utc)

    root_span = trace.get_current_span()
    root_span.set_attribute("org.icao", "LPPT")
    root_span.set_attribute("org.name", "lisbon-airport")
    root_span.set_attribute("org.role", "airport-operator")

    with _tracer.start_as_current_span("dnotam.dispatch") as span:
        span.set_attribute("notam.id", payload["notam_id"])
        span.set_attribute("notam.aerodrome", payload["aerodrome"])
        span.set_attribute("notam.type", payload["notam_type"])
        span.set_attribute("notam.runway", payload["runway"])

        ctx = context.get_current()
        ctx = baggage_api.set_baggage("org.icao", "LPPT", context=ctx)
        ctx = baggage_api.set_baggage("org.name", "lisbon-airport", context=ctx)
        ctx = baggage_api.set_baggage("org.role", "airport-operator", context=ctx)

        span.set_attribute("org.icao", "LPPT")
        span.set_attribute("org.name", "lisbon-airport")
        span.set_attribute("org.role", "airport-operator")

        headers = {}
        inject(headers, context=ctx)
        traceparent = headers.get("traceparent", "")

        _swim_log("OPERATIONAL_EVENT", "Dispatching DNOTAM request", payload, traceparent)

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                response = await client.post(
                    f"{PUBLISHER_URL}/v1/notam/publish",
                    json=payload,
                    headers=headers,
                )

            elapsed_ms = (datetime.now(timezone.utc) - start).total_seconds() * 1000
            _dispatch_counter.add(1, {"notam.type": payload["notam_type"], "notam.aerodrome": payload["aerodrome"]})
            _dispatch_duration.record(elapsed_ms, {"notam.type": payload["notam_type"]})

            return {
                "traceparent": traceparent,
                "metadata": {k: payload[k] for k in ("notam_id", "aerodrome", "notam_type", "runway")},
                "status": response.status_code,
                "body": response.json() if response.content else None,
            }
        except Exception as exc:
            span.set_status(trace.StatusCode.ERROR, str(exc))
            span.record_exception(exc)
            _dispatch_error_counter.add(1, {"notam.type": payload["notam_type"]})
            return JSONResponse(
                status_code=503,
                content={"error": str(exc), "traceparent": traceparent},
            )
