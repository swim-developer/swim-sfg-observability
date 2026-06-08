$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

podman network create swim-federation 2>$null
podman compose -f "$root\infra\compose-hub.yml" up -d
