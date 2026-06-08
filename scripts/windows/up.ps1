$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

podman network create swim-federation 2>$null
podman compose -f "$root\infra\compose-full.yml" up -d
Write-Host "Stack started. Open http://localhost:8000 (Originator) and http://localhost:3000 (Grafana)."
