$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Write-Host "Building sfg-dnotam-consumer..."
podman build --no-cache -t sfg-dnotam-consumer:latest `
    -f "$root\apps\dnotam-consumer\Containerfile" `
    "$root\apps\dnotam-consumer"
