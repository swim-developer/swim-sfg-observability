# SWIM dNOTAM: Technical Deep Dive

---

## Scenario walkthrough

### Scenario 1: Valid DNOTAM (runway 27R)

**Linux / macOS:**
```bash
make demo-valid
```

**Windows:**
```powershell
.\scripts\windows\demo-valid.ps1
```

What happens internally:
1. The originator creates a `traceparent` header and POSTs the NOTAM to the publisher
2. The publisher receives the header, propagates the trace context, and emits an AMQP message with `traceparent` in Application Properties
3. The consumer reads the AMQP message, extracts `traceparent`, validates runway `27R` (valid ICAO format), and logs an `OPERATIONAL_EVENT`
4. All three services export their spans to the OTel Collector, which forwards them to both local Tempo and Hub Tempo

Expected output:
```
Trace ID: 5d6b583f1f9a86a8bcec97d56db5cd8a
Status  : 202
Runway  : 27R
```

Verify logs:
```bash
make logs-consumer
```
Expected: `[SERVICE_LAYER][OPERATIONAL_EVENT] DNOTAM integrated for flight operation at LPPT | traceparent=00-5d6b583f...-03`

---

### Scenario 2: Invalid DNOTAM (runway ZZ9)

**Linux / macOS:**
```bash
make demo-invalid
```

**Windows:**
```powershell
.\scripts\windows\demo-invalid.ps1
```

What happens internally:
1. Same as Scenario 1, but the runway code is `ZZ9`, which is not a valid ICAO runway designator
2. The publisher does NOT validate; it publishes the AMQP message as-is (correct behaviour: the publisher is a transport relay, not a validator)
3. The consumer receives the message, extracts `traceparent`, checks the runway pattern `\d{2}[LRC]?`; `ZZ9` fails
4. The consumer logs a `VALIDATION_FAILURE` and marks the span as ERROR

Expected output in consumer logs:
```
[SERVICE_LAYER][VALIDATION_FAILURE] Invalid runway code 'ZZ9' for aerodrome LPPT | traceparent=00-ab9e9b45...-03
```

The `dnotam.process` span appears red (ERROR status) in the trace view. You can navigate from the red span back to the originator span to see exactly when and where the invalid data entered the chain.

Why this matters: the consumer is at a different organisation with no direct access to the originator. The `traceparent` is the only link. Following it reconstructs the entire chain without any organisation needing to share private logs.

---

## Federation Hub

### What it models

In real SWIM deployments, an airport, an ANSP, and an airline each run their own observability stack. There is no shared dashboard. The W3C Trace Context proposal for SPEC-170 requires that the `traceparent` be standardised at the wire level, not the platform level.

The Federation Hub models a **neutral federation point**: a central service that receives spans from all organisations via a shared network (`swim-federation`), stores them in an independent trace backend, and exposes a SWIM-style REST API to query cross-organisation traces by Trace ID.

### How it works technically

The OTel Collector uses **two distinct pipelines** so that internal and federated views have different fidelity:

```yaml
# infra/otel-collector.yaml (simplified)
processors:
  transform/hub-sanitize:
    trace_statements:
      - context: resource
        statements:
          - delete_key(resource.attributes, "telemetry.sdk.language")
          - delete_key(resource.attributes, "telemetry.sdk.name")
          - delete_key(resource.attributes, "telemetry.sdk.version")
          - delete_key(resource.attributes, "service.instance.id")
          - delete_key(resource.attributes, "deployment.environment")
          # ... and host.*, process.*, os.* attributes
      - context: span
        statements:
          - keep_keys(span.attributes, ["notam.id", "notam.aerodrome",
              "notam.type", "messaging.system", "messaging.destination.name",
              "http.method", "http.route", "http.status_code"])

service:
  pipelines:
    traces/local:                             # full fidelity — always active
      receivers: [otlp]
      processors: [batch]
      exporters: [otlp/local]

    # traces/hub:                             # curated federation export
    #   receivers: [otlp]                     # uncommented automatically by make hub-up
    #   processors: [transform/hub-sanitize, batch]
    #   exporters: [otlp/hub]
```

What each pipeline sees:

| Attribute | Local stack | Federation Hub |
|---|---|---|
| `service.name`, `service.namespace` | ✅ | ✅ |
| `notam.id`, `notam.aerodrome`, `notam.type`, `notam.runway` | ✅ | ✅ |
| `messaging.system`, `messaging.destination.name` | ✅ | ✅ |
| `deployment.environment` | ✅ | ❌ stripped |
| `service.instance.id` | ✅ | ❌ stripped |
| `telemetry.sdk.*`, `host.*`, `process.*`, `os.*` | ✅ | ❌ stripped |

Each organisation shares correlation context (Trace ID, service names, aviation business fields) without exposing internal platform details. Services are unaware of the hub; they send to one endpoint (the Collector) and routing is transparent.

### Query the federation hub

After running both scenarios:

```bash
# Replace with your actual Trace ID from make demo-valid
curl http://localhost:18080/v1/federation/traces/5d6b583f1f9a86a8bcec97d56db5cd8a | jq .
```

Response:
```json
{
  "traceId": "5d6b583f1f9a86a8bcec97d56db5cd8a",
  "participants": ["dnotam-originator", "dnotam-publisher", "dnotam-consumer"],
  "spans": [...],
  "totalDurationMicros": 167069
}
```

For the invalid scenario, the response includes `"status": "ERROR"` on the consumer span.

You can also use the Hub UI at http://localhost:18080 to search by Trace ID interactively.

### Federation API reference

| Endpoint | Description |
|---|---|
| `GET /v1/federation/traces/{traceId}` | Full distributed trace with participants, spans, durations, and error status |
| `GET /v1/federation/participants/{traceId}` | List of organisation/service names that participated in the transaction |

---

## Organisation identity and context propagation

### `service.namespace`: who owns this service

The OpenTelemetry Resource attribute `service.namespace` (stable, [semconv](https://opentelemetry.io/docs/specs/semconv/registry/entities/service/)) identifies the organisation that operates a service. It is set once at SDK initialisation and attached automatically to every span and log record.

In this demo:

| Organisation | `service.namespace` | `service.name` |
|---|---|---|
| Lisbon Airport (Airport Operator) | `lisbon-airport` | `dnotam-originator` |
| NAV Portugal (ANSP/AISP) | `nav-portugal` | `dnotam-publisher` |
| TAP Air Portugal (Airline) | `tap-air-portugal` | `dnotam-consumer` |
| Network Manager (Federation Hub) | `network-manager` | `federation-hub` |

The `service.namespace` is visible in every span in Grafana Explore (Resource attributes section), and the Federation Hub API returns `"org": "lisbon-airport"` for each participant in the trace.

---

### W3C Baggage: dynamic operational context

[W3C Baggage](https://www.w3.org/TR/baggage/) is a companion specification to W3C Trace Context. Where `traceparent` carries the trace identity, `baggage` carries arbitrary application-defined key-value pairs that propagate across every service boundary.

Wire representation:
```
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
baggage:     org.icao=LPPT,org.name=lisbon-airport,org.role=airport-operator
```

The `baggage` header travels in HTTP headers and in AMQP Application Properties, alongside `traceparent`, through the same `inject`/`extract` mechanism, using the same `CompositePropagator`.

In this demo, the originator (Aeroporto de Lisboa) sets:

| Baggage key | Value |
|---|---|
| `org.icao` | `LPPT` |
| `org.name` | `lisbon-airport` |
| `org.role` | `airport-operator` |

These values propagate automatically through the publisher (Quarkus SmallRye Reactive Messaging with `tracing-enabled=true`) and are extracted by the consumer, which logs:
```
DNOTAM integrated for flight operation at LPPT | notam_id=A0001/26 aerodrome=LPPT runway=27R org_icao=LPPT service_context=dNOTAM traceparent=00-...
```

and sets span attributes `org.icao`, `org.name`, `org.role` on the `dnotam.process` span, visible in Grafana Explore.

**Why this matters for SPEC-170:** standardising `traceparent` in AMQP Application Properties also standardises `baggage` at zero additional cost, using the same mechanism, the same wire position, the same propagator call. Organisations can use Baggage to carry ICAO designators, AIRAC cycle identifiers, or any aviation operational context across every protocol boundary without modifying the aviation payload.

---

## Observability perimeters

Not all observability data has the same audience or the same meaning. In a SWIM deployment, two distinct perimeters exist and must not be conflated.

**Infrastructure perimeter:** metrics and events generated by the platform itself. Broker memory, container CPU, TLS handshake errors, queue depth, network round-trip times. These are the concern of platform operators and are already covered by the infrastructure tooling (OpenShift, Prometheus node-exporter, broker management consoles). SPEC-170 addresses the infrastructure perimeter through its existing infrastructure capability requirements.

**Service layer perimeter:** events generated by the aviation business logic running inside the service. A DNOTAM was dispatched. A runway code failed validation. A flight update was integrated. These events carry aviation semantics (ICAO designators, NOTAM identifiers, aerodrome codes) and are the concern of service architects and SWIM service consumers. This is the perimeter where standardised observability requirements at the binding level add value.

The distinction matters because a recommendation aimed at service architects (for example, a SPEC-170 clarification on which headers to propagate) must target the service layer exclusively. Bundling infrastructure metrics and service events into the same guidance produces requirements that are either too broad to be useful or too narrow to be implementable.

### How this demo enforces the separation

The boundary between the two perimeters is structural, not configurational. It is enforced in application code, not in log routing rules or dashboard filters.

Every application log record carries `swim_perimeter: SERVICE_LAYER` and a typed `event_type` field. The infrastructure perimeter is simply absent from the application log stream: broker memory or container CPU never appear in service logs. Routing, filtering, and aggregation happen downstream (Loki, Prometheus) without any application-level awareness of infrastructure state.

```
[SERVICE_LAYER][OPERATIONAL_EVENT] DNOTAM integrated for flight operation at LPPT
[SERVICE_LAYER][VALIDATION_FAILURE] Invalid runway code 'ZZ9' for aerodrome LPPT
```

Neither record contains any infrastructure metric. Infrastructure telemetry reaches Prometheus through a separate scrape path, never through the application OTLP pipeline.

This separation enables a SPEC-170 clarification to say: "service bindings should propagate trace context and emit structured service-layer events" without conflating that with "the broker must expose queue depth via OTLP". Both are valid observability requirements; they belong to different sections of the specification.

---

## Observability concepts

### Distributed Tracing: W3C Trace Context

A **trace** is a directed acyclic graph of **spans**. Each span represents one unit of work (an HTTP call, a message publish, a message consume). Every span carries two identifiers:

- **trace-id** (128-bit): shared and invariant across the entire transaction, regardless of how many services or protocols it crosses
- **span-id** (64-bit): unique to that unit of work; becomes the `parent-id` in the next downstream service

The mechanism for carrying these identifiers across service boundaries is defined in the **W3C Trace Context** specification ([https://www.w3.org/TR/trace-context/](https://www.w3.org/TR/trace-context/)). The wire format is the `traceparent` header, a plain string:

```
00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
│   │                                │                │
│   │                                │                └─ flags: 01 = sampled
│   │                                └─ parent-id — changes at each boundary
│   └─ trace-id — invariant across ALL hops
└─ version: always 00
```

**How context crosses a protocol boundary:**

The propagation API defines two operations:
- `inject(carrier)`: writes the current trace context into a carrier (HTTP headers, AMQP properties, Kafka headers, etc.)
- `extract(carrier)`: reads trace context from a carrier and reconstructs the parent span

When the publisher injects into an AMQP message, it writes `traceparent` as a plain string into the AMQP 1.0 **Application Properties** section. The aviation payload is not touched. When the consumer extracts, it reads that string and re-creates a `SpanContext` pointing to the publisher's span as parent, connecting the two services in the same trace tree.

This is a specification-level behaviour, not a library-specific one. Any implementation that follows W3C Trace Context and the OTLP conventions for messaging (see [OpenTelemetry Messaging Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/messaging/)) can interoperate.

**Open source trace backends that support OTLP ingestion:**
Grafana Tempo, Jaeger, Zipkin, OpenSearch (with the trace analytics plugin).

---

### Structured Logging: OpenTelemetry Log Data Model

A **structured log** is a log record with machine-readable key-value fields rather than free-form text. The [OpenTelemetry Log Data Model](https://opentelemetry.io/docs/specs/otel/logs/data-model/) defines a standard schema for log records that includes, among others, the `traceId` and `spanId` of the active span at the time the log was emitted. This is what enables correlation between logs and traces without any post-processing.

The transport format is **OTLP** (OpenTelemetry Protocol), which carries logs, traces, and metrics in a single unified wire format over gRPC or HTTP.

**The SERVICE_LAYER taxonomy in this demo** makes the perimeter boundary explicit in every log record (see [Observability perimeters](#observability-perimeters)):

| Field | Values in this demo |
|---|---|
| `swim_perimeter` | `SERVICE_LAYER` |
| `event_type` | `OPERATIONAL_EVENT` or `VALIDATION_FAILURE` |
| `service_context` | `dNOTAM` |

**Open source log aggregation systems that support OTLP or structured log ingestion:**
Grafana Loki, OpenSearch, Elasticsearch, Quickwit.

---

### Metrics: OpenMetrics / Prometheus exposition format

A **metric** is a numerical measurement sampled over time. The [Prometheus exposition format](https://prometheus.io/docs/instrumenting/exposition_formats/) has become the de facto standard for metrics in cloud-native environments and is formalised as [OpenMetrics](https://openmetrics.io/) under the CNCF.

Common metric types:
- **Counter**: monotonically increasing value (e.g. total dispatches)
- **Gauge**: value that can go up or down (e.g. current queue depth)
- **Histogram**: distribution of values (e.g. dispatch duration in milliseconds)

Business metrics defined in this demo:

| Service | Metric | Type |
|---|---|---|
| originator | `dnotam_dispatches_total` | Counter |
| originator | `dnotam_dispatch_errors_total` | Counter |
| originator | `dnotam_dispatch_duration_milliseconds` | Histogram |
| publisher | `dnotam_publishes_total` | Counter |
| publisher | `dnotam_publish_duration_milliseconds` | Histogram |
| consumer | `dnotam_messages_consumed_total` | Counter |
| consumer | `dnotam_validation_failures_total` | Counter |
| consumer | `dnotam_processing_duration_milliseconds` | Histogram |

**Open source metrics backends compatible with the Prometheus exposition format:**
Prometheus, VictoriaMetrics, Thanos, Mimir.

---

## The traceparent header: hop by hop

This is the key insight of the demo:

| Hop | Protocol | trace-id | parent-id |
|---|---|---|---|
| Airport dispatches DNOTAM | — | `4bf9...4736` (created here) | root span ID |
| Airport → ANSP Publisher | **HTTP** `traceparent` header | `4bf9...4736` ← same | publisher span ID |
| ANSP Publisher → Broker | **AMQP** Application Properties | `4bf9...4736` ← same | AMQP publish span ID |
| Broker → Consumer | **AMQP** Application Properties | `4bf9...4736` ← same | consumer span ID |

The `trace-id` never changes. It crosses the HTTP→AMQP protocol boundary through the AMQP Application Properties section, not the message body. The aviation payload is untouched.

The `parent-id` updates at each service boundary, creating the parent-child span relationship that a trace backend renders as a waterfall timeline. Every span knows its parent. No span is orphaned.

When you query the Federation Hub with a Trace ID, the UI decomposes the `traceparent` live:

```
version  trace-id (invariant)              parent-id (root span)   flags
  00   - 4bf92f3577b34da6a3ce929d0e0e4736 - 00f067aa0ba902b7     -  01
```

Below it, each span in the timeline shows its own `span-id`, which becomes the `parent-id` in the traceparent of the next downstream service.

---

## Why this matters for SPEC-170

The SWIM Foundation Group use case for distributed tracing (authored by Stefan Keller, DFS) identifies two gaps in the current Yellow Profile and proposes two **optional** requirements to fill them:

> **Optional requirement:** https bindings will honour the `traceparent` header (W3C Trace Context)

> **Optional requirement:** amqps bindings will provide in the publication a standardised reference to the underlying subscription

The first requirement is what this demo validates end-to-end. The `traceparent` enters over HTTP and exits inside the AMQP Application Properties, invariant across the protocol boundary, without modifying the aviation payload. One 32-character identifier is present in every artefact (HTTP headers, AMQP Application Properties, structured logs, and distributed trace spans) across three independent technology stacks.

The second requirement refers to a reference to the SWIM subscription that caused the message to be delivered, a management concept distinct from the distributed trace context. The demo does not address subscription referencing; that is a separate binding extension.

The purpose of this demo is to validate the technical feasibility of the first requirement and to show that it is implementable with any AMQP 1.0 client and any HTTP library, with no dependency on a specific vendor or SDK. The SFG working group decides whether and how to formalise these requirements in SPEC-170.

---

## References

- [W3C Trace Context](https://www.w3.org/TR/trace-context/)
- [OpenTelemetry Messaging Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/messaging/)
- [OpenTelemetry Log Data Model](https://opentelemetry.io/docs/specs/otel/logs/data-model/)
- [OpenMetrics specification](https://openmetrics.io/)
- [EUROCONTROL SPEC-170 — SWIM-TI Yellow Profile v2.0](https://www.eurocontrol.int/publication/eurocontrol-spec-170-eurocontrol-specification-swim-technical-infrastructure-ti-yellow)
- [EUR SWIM Registry — Digital NOTAM Service](https://eur-registry.swim.aero/services/eurocontrol-digital-notam-subscription-and-request-service-010000)
- [Quarkus OpenTelemetry Guide](https://quarkus.io/guides/opentelemetry)
- [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)
