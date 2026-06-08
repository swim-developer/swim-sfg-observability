# dnotam-consumer

.NET 10 Worker Service. Consumes DNOTAMs from AMQP, validates, and logs with trace correlation.

## Prerequisites

- .NET 10 SDK
- Infrastructure running (see `infra/`)

## Local dev

```bash
AMQP_HOST=localhost \
OTLP_ENDPOINT=http://localhost:4317 \
LOKI_OTLP_ENDPOINT=http://localhost:3100/otlp/v1/logs \
dotnet run
```

## Container

```bash
podman build -t dnotam-consumer:local -f Containerfile .
podman run --rm \
  -e AMQP_HOST=host.containers.internal \
  -e OTLP_ENDPOINT=http://host.containers.internal:4317 \
  -e LOKI_OTLP_ENDPOINT=http://host.containers.internal:3100/otlp/v1/logs \
  dnotam-consumer:local
```
