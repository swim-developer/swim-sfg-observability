$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

podman compose -f "$root\infra\compose-full.yml" down
