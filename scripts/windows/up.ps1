$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$infra = "$root\infra"
$net = "sfg-local"

podman network create $net 2>$null
podman network create swim-federation 2>$null

Write-Host "Starting Tempo..."
podman run -d --name sfg-tempo --network $net `
    -p 3200:3200 `
    -v "${infra}\tempo.yaml:/etc/tempo.yaml:ro,z" `
    docker.io/grafana/tempo:2.6.1 `
    -config.file=/etc/tempo.yaml

Write-Host "Starting Loki..."
podman run -d --name sfg-loki --network $net `
    -p 3100:3100 `
    docker.io/grafana/loki:latest `
    -config.file=/etc/loki/local-config.yaml

Write-Host "Starting Prometheus..."
podman run -d --name sfg-prometheus --network $net `
    -p 9090:9090 `
    -v "${infra}\prometheus.yml:/etc/prometheus/prometheus.yml:ro,z" `
    docker.io/prom/prometheus:latest `
    --config.file=/etc/prometheus/prometheus.yml `
    --web.enable-remote-write-receiver

Write-Host "Starting Grafana..."
podman run -d --name sfg-grafana --network $net `
    -p 3000:3000 `
    -e GF_SECURITY_ADMIN_USER=admin `
    -e GF_SECURITY_ADMIN_PASSWORD=admin `
    -e GF_AUTH_ANONYMOUS_ENABLED=true `
    -v "${infra}\grafana\datasources.yml:/etc/grafana/provisioning/datasources/datasources.yml:ro,z" `
    -v "${infra}\grafana\dashboards.yml:/etc/grafana/provisioning/dashboards/dashboards.yml:ro,z" `
    -v "${infra}\grafana\dashboards:/etc/grafana/dashboards:ro,z" `
    docker.io/grafana/grafana:latest

Write-Host "Starting Artemis..."
podman run -d --name sfg-artemis --network $net `
    -p 5672:5672 -p 8161:8161 `
    -e ARTEMIS_USER=admin `
    -e ARTEMIS_PASSWORD=admin `
    -e ANONYMOUS_LOGIN=false `
    docker.io/apache/activemq-artemis:2.40.0-alpine

Write-Host "Starting OTel Collector..."
podman run -d --name sfg-otel-collector --network $net `
    -p 4317:4317 -p 4318:4318 `
    -v "${infra}\otel-collector.yaml:/etc/otel-collector.yaml:ro,z" `
    docker.io/otel/opentelemetry-collector-contrib:0.123.0 `
    --config=/etc/otel-collector.yaml
podman network connect swim-federation sfg-otel-collector

Write-Host "Waiting 35s for Artemis to be ready..."
Start-Sleep -Seconds 35

Write-Host "Starting Publisher..."
podman run -d --name sfg-dnotam-publisher --network $net `
    -p 8080:8080 `
    -e AMQP_HOST=sfg-artemis `
    -e AMQP_PORT=5672 `
    -e AMQP_USER=admin `
    -e AMQP_PASSWORD=admin `
    -e OTLP_ENDPOINT=http://sfg-otel-collector:4317 `
    -e LOKI_OTLP_ENDPOINT=http://sfg-loki:3100/otlp `
    sfg-dnotam-publisher:latest

Write-Host "Waiting 20s for Publisher to be ready..."
Start-Sleep -Seconds 20

Write-Host "Starting Consumer..."
podman run -d --name sfg-dnotam-consumer --network $net `
    -p 9465:9464 `
    -e AMQP_HOST=sfg-artemis `
    -e AMQP_PORT=5672 `
    -e AMQP_USER=admin `
    -e AMQP_PASSWORD=admin `
    -e OTLP_ENDPOINT=http://sfg-otel-collector:4317 `
    -e LOKI_OTLP_ENDPOINT=http://sfg-loki:3100/otlp/v1/logs `
    sfg-dnotam-consumer:latest

Write-Host "Starting Originator..."
podman run -d --name sfg-dnotam-originator --network $net `
    -p 8000:8000 -p 9464:9464 `
    -e PUBLISHER_URL=http://sfg-dnotam-publisher:8080 `
    -e OTLP_ENDPOINT=http://sfg-otel-collector:4317 `
    -e LOKI_OTLP_ENDPOINT=http://sfg-loki:3100/otlp/v1/logs `
    sfg-dnotam-originator:latest

Write-Host "Done. Stack is up."
