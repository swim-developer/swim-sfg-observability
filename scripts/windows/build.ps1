$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

Write-Host "Building sfg-dnotam-originator..."
docker build --no-cache -t sfg-dnotam-originator:latest `
    -f "$root\apps\dnotam-originator\Containerfile" `
    "$root\apps\dnotam-originator"

Write-Host "Building sfg-dnotam-publisher..."
Push-Location "$root\apps\dnotam-publisher"
.\mvnw.cmd clean package -DskipTests -q
Pop-Location
docker build --no-cache -t sfg-dnotam-publisher:latest `
    -f "$root\apps\dnotam-publisher\Containerfile" `
    "$root\apps\dnotam-publisher"

Write-Host "Building sfg-dnotam-consumer..."
docker build --no-cache -t sfg-dnotam-consumer:latest `
    -f "$root\apps\dnotam-consumer\Containerfile" `
    "$root\apps\dnotam-consumer"

Write-Host "All images built."
