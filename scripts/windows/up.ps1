$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

docker network create swim-federation 2>$null
docker compose -f "$root\infra\compose-full.yml" up -d
