$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Write-Host "Building sfg-dnotam-originator..."
podman build --no-cache -t sfg-dnotam-originator:latest `
    -f "$root\apps\dnotam-originator\Containerfile" `
    "$root\apps\dnotam-originator"
