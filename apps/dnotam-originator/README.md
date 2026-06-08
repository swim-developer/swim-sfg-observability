# dnotam-originator

Python + FastAPI. Simulates the role of an aerodrome operator initiating a DNOTAM request.

## Prerequisites

- Python 3.12+
- Infrastructure running (see `infra/`)

## Local dev

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

PUBLISHER_URL=http://localhost:8080 \
OTLP_ENDPOINT=http://localhost:4317 \
LOKI_OTLP_ENDPOINT=http://localhost:3100/otlp/v1/logs \
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Open: http://localhost:8000

## Container

```bash
podman build -t dnotam-originator:local -f Containerfile .
podman run --rm -p 8000:8000 \
  -e PUBLISHER_URL=http://host.containers.internal:8080 \
  -e OTLP_ENDPOINT=http://host.containers.internal:4317 \
  -e LOKI_OTLP_ENDPOINT=http://host.containers.internal:3100/otlp/v1/logs \
  dnotam-originator:local
```
