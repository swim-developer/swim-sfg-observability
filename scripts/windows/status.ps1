$ErrorActionPreference = "Stop"
podman ps --filter "name=sfg" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
