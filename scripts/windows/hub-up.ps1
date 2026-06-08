$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

docker build --no-cache -t sfg-eurocontrol-hub:latest `
    -f "$root\apps\eurocontrol-hub\Containerfile" `
    "$root\apps\eurocontrol-hub"

docker compose -f "$root\infra\compose-hub.yml" up -d
