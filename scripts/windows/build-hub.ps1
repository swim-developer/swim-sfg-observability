$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Write-Host "Building sfg-federation-hub..."
podman build --no-cache -t sfg-federation-hub:latest `
    -f "$root\apps\federation-hub\Containerfile" `
    "$root\apps\federation-hub"
