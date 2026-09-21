$ErrorActionPreference = "Stop"
$null = podman network inspect swim-federation 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating swim-federation network..."
    podman network create swim-federation
} else {
    Write-Host "Network swim-federation already exists."
}
