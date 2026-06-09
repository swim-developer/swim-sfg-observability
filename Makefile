SHELL := /bin/bash

PROJECT_ROOT  := $(shell pwd)
INFRA_DIR     := $(PROJECT_ROOT)/infra
APPS_DIR      := $(PROJECT_ROOT)/apps

ORIGINATOR_DIR := $(APPS_DIR)/dnotam-originator
PUBLISHER_DIR  := $(APPS_DIR)/dnotam-publisher
CONSUMER_DIR   := $(APPS_DIR)/dnotam-consumer
HUB_DIR        := $(APPS_DIR)/federation-hub

IMAGE_ORIGINATOR := sfg-dnotam-originator:latest
IMAGE_PUBLISHER  := sfg-dnotam-publisher:latest
IMAGE_CONSUMER   := sfg-dnotam-consumer:latest
IMAGE_HUB        := sfg-federation-hub:latest

ORIGINATOR_URL := http://localhost:8000
GRAFANA_UI     := http://localhost:3000
HUB_UI         := http://localhost:18080
HUB_GRAFANA_UI := http://localhost:13000
ARTEMIS_UI     := http://localhost:8161

OS := $(shell uname -s 2>/dev/null || echo Windows)
ifeq ($(OS),Darwin)
  OPEN := open
else ifeq ($(OS),Linux)
  OPEN := xdg-open
else
  OPEN := start
endif

.DEFAULT_GOAL := help

# ─── Help ─────────────────────────────────────────────────────────────────────

.PHONY: help
help:
	@echo ""
	@echo "  SWIM Yellow Profile — Distributed Tracing Demo"
	@echo ""
	@echo "  MODE A — Full stack (containers)"
	@echo "    make build              Build 3 core service images"
	@echo "    make build-all          Build all 4 images (incl. hub)"
	@echo "    make up                 Start everything (infra + apps)"
	@echo "    make down               Stop everything"
	@echo "    make status             Show container status"
	@echo ""
	@echo "  DEMO"
	@echo "    make demo-valid         Scenario 1 — valid DNOTAM"
	@echo "    make demo-invalid       Scenario 2 — invalid runway code"
	@echo "    make logs-consumer      Tail consumer structured logs"
	@echo "    make logs-publisher     Tail publisher structured logs"
	@echo ""
	@echo "  OBSERVABILITY"
	@echo "    make open-grafana       Open Grafana  (localhost:3000)"
	@echo "    make open-artemis       Open Artemis  (localhost:8161)"
	@echo ""
	@echo "  FEDERATION HUB"
	@echo "    make federation-network Create shared network (run once)"
	@echo "    make build-hub          Build federation-hub image"
	@echo "    make hub-up             Start Federation Hub stack"
	@echo "    make hub-down           Stop Federation Hub stack"
	@echo "    make open-hub           Open Hub Federation UI  (localhost:18080)"
	@echo "    make open-hub-grafana   Open Hub Grafana        (localhost:13000)"
	@echo ""
	@echo "  MODE B — Dev mode (infra only, services run locally)"
	@echo "    make infra-up           Start infra (Artemis, Tempo, Loki, Prometheus, Grafana)"
	@echo "    make infra-down         Stop infra"
	@echo "    make dev-originator     Run originator locally (port 8000)"
	@echo "    make dev-publisher      Run publisher in Quarkus dev mode (port 8080)"
	@echo "    make dev-consumer       Run consumer locally (.NET)"
	@echo ""

# ─── Build ────────────────────────────────────────────────────────────────────

.PHONY: build
build: build-originator build-publisher build-consumer build-hub

.PHONY: build-all
build-all: build

.PHONY: build-originator
build-originator:
	@echo "  Building $(IMAGE_ORIGINATOR)..."
	podman build --no-cache -t $(IMAGE_ORIGINATOR) -f $(ORIGINATOR_DIR)/Containerfile $(ORIGINATOR_DIR)

.PHONY: build-publisher
build-publisher:
	@echo "  Building $(IMAGE_PUBLISHER)..."
	podman build --no-cache -t $(IMAGE_PUBLISHER) -f $(PUBLISHER_DIR)/Containerfile $(PUBLISHER_DIR)

.PHONY: build-consumer
build-consumer:
	@echo "  Building $(IMAGE_CONSUMER)..."
	podman build --no-cache -t $(IMAGE_CONSUMER) -f $(CONSUMER_DIR)/Containerfile $(CONSUMER_DIR)

.PHONY: build-hub
build-hub:
	@echo "  Building $(IMAGE_HUB)..."
	podman build --no-cache -t $(IMAGE_HUB) -f $(HUB_DIR)/Containerfile $(HUB_DIR)

# ─── Mode A — Full stack ──────────────────────────────────────────────────────

.PHONY: up
up: federation-network
	podman compose -f $(INFRA_DIR)/compose-full.yml up -d

.PHONY: down
down:
	podman compose -f $(INFRA_DIR)/compose-full.yml down

.PHONY: status
status:
	@podman ps --format "table {{.Names}}\t{{.Status}}" | grep sfg || echo "  No sfg containers running."

# ─── Mode B — Infra only ──────────────────────────────────────────────────────

.PHONY: infra-up
infra-up: federation-network
	podman compose -f $(INFRA_DIR)/compose.yml up -d

.PHONY: infra-down
infra-down:
	podman compose -f $(INFRA_DIR)/compose.yml down

.PHONY: dev-originator
dev-originator:
	cd $(ORIGINATOR_DIR) && \
	  ([ -d .venv ] || python3 -m venv .venv) && \
	  source .venv/bin/activate && \
	  pip install -q -r requirements.txt && \
	  PUBLISHER_URL=http://localhost:8080 \
	  OTLP_ENDPOINT=http://localhost:4317 \
	  LOKI_OTLP_ENDPOINT=http://localhost:3100/otlp/v1/logs \
	  uvicorn main:app --host 0.0.0.0 --port 8000 --reload

.PHONY: dev-publisher
dev-publisher:
	cd $(PUBLISHER_DIR) && \
	  AMQP_HOST=localhost \
	  AMQP_PORT=5672 \
	  OTLP_ENDPOINT=http://localhost:4317 \
	  LOKI_OTLP_ENDPOINT=http://localhost:3100/otlp \
	  ./mvnw quarkus:dev

.PHONY: dev-consumer
dev-consumer:
	cd $(CONSUMER_DIR) && \
	  AMQP_HOST=localhost \
	  OTLP_ENDPOINT=http://localhost:4317 \
	  LOKI_OTLP_ENDPOINT=http://localhost:3100/otlp/v1/logs \
	  dotnet run

# ─── Demo ─────────────────────────────────────────────────────────────────────

.PHONY: demo-valid
demo-valid:
	@echo "  Scenario 1 — valid DNOTAM (runway 27R)"
	@curl -s -X POST $(ORIGINATOR_URL)/publish/valid | \
	  python3 -c "import sys,json; d=json.load(sys.stdin); print('  Trace ID:', d['traceparent'].split('-')[1]); print('  Status  :', d.get('status')); print('  Runway  :', d['metadata']['runway'])"
.PHONY: demo-invalid
demo-invalid:
	@echo "  Scenario 2 — invalid DNOTAM (runway ZZ9)"
	@curl -s -X POST $(ORIGINATOR_URL)/publish/invalid | \
	  python3 -c "import sys,json; d=json.load(sys.stdin); print('  Trace ID:', d['traceparent'].split('-')[1]); print('  Status  :', d.get('status')); print('  Runway  :', d['metadata']['runway'])"

# ─── Logs ─────────────────────────────────────────────────────────────────────

.PHONY: logs-consumer
logs-consumer:
	podman logs -f sfg-dnotam-consumer 2>&1

.PHONY: logs-publisher
logs-publisher:
	podman logs -f sfg-dnotam-publisher 2>&1

# ─── UIs ──────────────────────────────────────────────────────────────────────

.PHONY: open-grafana
open-grafana:
	$(OPEN) $(GRAFANA_UI)

.PHONY: open-artemis
open-artemis:
	$(OPEN) $(ARTEMIS_UI)

# ─── Federation Hub ───────────────────────────────────────────────

.PHONY: federation-network
federation-network:
	@podman network inspect swim-federation >/dev/null 2>&1 || podman network create swim-federation

.PHONY: hub-up
hub-up: federation-network
	podman compose -f $(INFRA_DIR)/compose-hub.yml up -d

.PHONY: hub-down
hub-down:
	podman compose -f $(INFRA_DIR)/compose-hub.yml down

.PHONY: open-hub
open-hub:
	$(OPEN) $(HUB_UI)

.PHONY: open-hub-grafana
open-hub-grafana:
	$(OPEN) $(HUB_GRAFANA_UI)
