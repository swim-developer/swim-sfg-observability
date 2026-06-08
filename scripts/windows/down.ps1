$ErrorActionPreference = "SilentlyContinue"

$containers = @(
    "sfg-dnotam-originator",
    "sfg-dnotam-consumer",
    "sfg-dnotam-publisher",
    "sfg-otel-collector",
    "sfg-grafana",
    "sfg-prometheus",
    "sfg-loki",
    "sfg-tempo",
    "sfg-artemis"
)

foreach ($c in $containers) {
    podman stop $c 2>$null
    podman rm $c 2>$null
}
