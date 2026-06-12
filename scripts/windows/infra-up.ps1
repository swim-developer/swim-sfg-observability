$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$null = podman network inspect swim-federation 2>$null
if ($LASTEXITCODE -ne 0) { podman network create swim-federation }
podman compose -f "$root\infra\compose.yml" up -d
