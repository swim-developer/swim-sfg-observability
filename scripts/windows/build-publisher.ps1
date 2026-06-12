$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Write-Host "Building sfg-dnotam-publisher..."
podman build --no-cache -t sfg-dnotam-publisher:latest `
    -f "$root\apps\dnotam-publisher\Containerfile" `
    "$root\apps\dnotam-publisher"
