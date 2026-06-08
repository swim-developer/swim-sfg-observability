$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Invoke-Podman {
    param([string[]]$Args)
    podman @Args
    if ($LASTEXITCODE -ne 0) { throw "podman $($Args[0]) failed with exit code $LASTEXITCODE" }
}

Write-Host "Building sfg-dnotam-originator..."
Invoke-Podman build, --no-cache, -t, sfg-dnotam-originator:latest, `
    -f, "$root\apps\dnotam-originator\Containerfile", `
    "$root\apps\dnotam-originator"

Write-Host "Building sfg-dnotam-publisher..."
Invoke-Podman build, --no-cache, -t, sfg-dnotam-publisher:latest, `
    -f, "$root\apps\dnotam-publisher\Containerfile", `
    "$root\apps\dnotam-publisher"

Write-Host "Building sfg-dnotam-consumer..."
Invoke-Podman build, --no-cache, -t, sfg-dnotam-consumer:latest, `
    -f, "$root\apps\dnotam-consumer\Containerfile", `
    "$root\apps\dnotam-consumer"

Write-Host "All images built."
