$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$infra = "$root\infra"
$net = "sfg-hub"

podman network create $net 2>$null
podman network create swim-federation 2>$null

Write-Host "Building eurocontrol-hub image..."
podman build --no-cache -t sfg-eurocontrol-hub:latest `
    -f "$root\apps\eurocontrol-hub\Containerfile" `
    "$root\apps\eurocontrol-hub"

Write-Host "Starting Hub Tempo..."
podman run -d --name sfg-hub-tempo --network $net `
    -p 13200:3200 `
    -v "${infra}\tempo-hub.yaml:/etc/tempo.yaml:ro,z" `
    docker.io/grafana/tempo:2.6.1 `
    -config.file=/etc/tempo.yaml
podman network connect swim-federation sfg-hub-tempo

Write-Host "Starting Hub Grafana..."
podman run -d --name sfg-hub-grafana --network $net `
    -p 13000:3000 `
    -e GF_SECURITY_ADMIN_USER=admin `
    -e GF_SECURITY_ADMIN_PASSWORD=admin `
    -e GF_AUTH_ANONYMOUS_ENABLED=true `
    -v "${infra}\grafana\hub-datasources.yml:/etc/grafana/provisioning/datasources/datasources.yml:ro,z" `
    -v "${infra}\grafana\dashboards.yml:/etc/grafana/provisioning/dashboards/dashboards.yml:ro,z" `
    -v "${infra}\grafana\dashboards:/etc/grafana/dashboards:ro,z" `
    docker.io/grafana/grafana:latest

Write-Host "Starting Eurocontrol Hub service..."
podman run -d --name sfg-eurocontrol-hub --network $net `
    -p 18080:8080 `
    -e TEMPO_URL=http://sfg-hub-tempo:3200 `
    -e OTLP_ENDPOINT=http://sfg-hub-tempo:4317 `
    sfg-eurocontrol-hub:latest
podman network connect swim-federation sfg-eurocontrol-hub

Write-Host "Done. Hub is up."
