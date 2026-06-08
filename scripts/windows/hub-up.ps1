$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

podman build --no-cache -t sfg-eurocontrol-hub:latest `
    -f "$root\apps\eurocontrol-hub\Containerfile" `
    "$root\apps\eurocontrol-hub"

podman compose -f "$root\infra\compose-hub.yml" up -d
