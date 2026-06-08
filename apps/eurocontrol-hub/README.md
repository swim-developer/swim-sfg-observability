# eurocontrol-hub

Quarkus service representing the **Eurocontrol Network Manager — Telemetry Federation Hub**.

## Concept

In production SWIM deployments, each organization (airport, ANSP, airline) operates independent infrastructure and independent observability stacks. There is no single place to correlate a transaction that crosses organizational boundaries.

The Eurocontrol Hub models a **neutral federation point**: a central service that receives telemetry from all participating organizations via a shared network, stores spans in its own Tempo instance, and exposes a SWIM-style query API for cross-organization trace correlation.

The key enabler is the W3C `traceparent` header: because every DNOTAM transaction carries the same Trace ID across HTTP and AMQP boundaries, the hub can reconstruct the full distributed trace from spans that originated in entirely separate organizations.

## API

| Endpoint | Description |
|---|---|
| `GET /v1/federation/traces/{traceId}` | Full distributed trace with all participating services |
| `GET /v1/federation/participants/{traceId}` | List of organization/service names in the trace |

## Local development

```bash
# Requires hub Tempo running (see hub stack below)
TEMPO_URL=http://localhost:13200 \
OTLP_ENDPOINT=http://localhost:14317 \
./mvnw quarkus:dev
```

## Build image

```bash
make build-hub
```

## Architecture

```
Organizations (independent stacks)     Eurocontrol Hub
──────────────────────────────────     ───────────────────────────────
dnotam-originator ──┐                  sfg-hub-tempo   (Tempo central)
dnotam-publisher  ──┼──► OTel ─────►  eurocontrol-hub (SWIM API)
dnotam-consumer   ──┘   Collector      sfg-hub-grafana (Grafana federated)
```

The OTel Collector fans out spans to both the local Tempo (org-level) and the Hub Tempo (federation-level). Services are unaware of the hub — routing is transparent.
