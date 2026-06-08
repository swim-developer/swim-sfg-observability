# dnotam-publisher

Quarkus 3.36.1 + Java 25. Receives DNOTAM via HTTP REST and publishes to AMQP.

## Prerequisites

- Java 25, Maven 3.9+
- Infrastructure running (see `infra/`)

## Local dev

```bash
AMQP_HOST=localhost \
AMQP_PORT=5672 \
OTLP_ENDPOINT=http://localhost:4317 \
LOKI_OTLP_ENDPOINT=http://localhost:3100/otlp/v1/logs \
./mvnw quarkus:dev
```

REST endpoint: http://localhost:8080/v1/notam/publish

## Container

```bash
./mvnw clean package -DskipTests
podman build -t dnotam-publisher:local -f Containerfile .
podman run --rm -p 8080:8080 \
  -e AMQP_HOST=host.containers.internal \
  -e OTLP_ENDPOINT=http://host.containers.internal:4317 \
  -e LOKI_OTLP_ENDPOINT=http://host.containers.internal:3100/otlp/v1/logs \
  dnotam-publisher:local
```
