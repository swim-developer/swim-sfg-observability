$ErrorActionPreference = "SilentlyContinue"

$containers = @(
    "sfg-eurocontrol-hub",
    "sfg-hub-grafana",
    "sfg-hub-tempo"
)

foreach ($c in $containers) {
    podman stop $c 2>$null
    podman rm $c 2>$null
}
