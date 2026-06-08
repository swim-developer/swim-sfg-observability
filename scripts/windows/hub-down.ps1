$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

docker compose -f "$root\infra\compose-hub.yml" down
