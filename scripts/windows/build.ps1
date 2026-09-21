$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

Write-Host "Building sfg-dnotam-originator..."
podman build --no-cache -t sfg-dnotam-originator:latest `
    -f "$root\apps\dnotam-originator\Containerfile" `
    "$root\apps\dnotam-originator"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Building sfg-dnotam-publisher..."
podman build --no-cache -t sfg-dnotam-publisher:latest `
    -f "$root\apps\dnotam-publisher\Containerfile" `
    "$root\apps\dnotam-publisher"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Building sfg-dnotam-consumer..."
podman build --no-cache -t sfg-dnotam-consumer:latest `
    -f "$root\apps\dnotam-consumer\Containerfile" `
    "$root\apps\dnotam-consumer"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Building sfg-federation-hub..."
podman build --no-cache -t sfg-federation-hub:latest `
    -f "$root\apps\federation-hub\Containerfile" `
    "$root\apps\federation-hub"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "All images built."
