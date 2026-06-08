# OpenShift Local (CRC) — Deployment Guide

Minimal GitOps setup using:

- **Red Hat AMQ Broker Operator** — replaces standalone Artemis
- **Grafana Tempo / Loki / Grafana** — deployed as simple Deployments
- **OpenShift GitOps** (ArgoCD) — manages application manifests
- **Gitea** — internal Git server

---

## Prerequisites

| Tool | Install |
|---|---|
| CRC | https://console.redhat.com/openshift/create/local |
| `oc` CLI | bundled with CRC |
| `make` | via OS package manager |

Recommended CRC resources (start CRC with these):

```bash
crc config set memory 12288
crc config set cpus 6
crc start
```

Login as developer and then as admin:

```bash
eval $(crc oc-env)
oc login -u developer -p developer https://api.crc.testing:6443
oc login -u kubeadmin -p $(crc console --credentials | grep kubeadmin | awk '{print $2}') https://api.crc.testing:6443
```

---

## Step 1 — Enable internal image registry

```bash
oc patch configs.imageregistry.operator.openshift.io cluster \
  --type merge --patch '{"spec":{"defaultRoute":true}}'
```

Log in to the registry:

```bash
make crc-registry-login
```

---

## Step 2 — Build and push images

```bash
make crc-build-push
```

This builds all three service images and pushes them to the CRC internal registry under the `swim-sfg-observability` project.

---

## Step 3 — Install OpenShift GitOps

```bash
oc apply -f deployments/openshift/gitops/01-openshift-gitops-subscription.yaml
```

Wait for ArgoCD to be ready (~2 minutes):

```bash
oc wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server \
  -n openshift-gitops --timeout=120s
```

Retrieve the ArgoCD admin password:

```bash
oc get secret openshift-gitops-cluster -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' | base64 -d && echo
```

Open ArgoCD:

```bash
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
```

---

## Step 4 — Deploy Gitea

```bash
oc apply -f deployments/openshift/gitops/02-gitea.yaml
```

Wait for Gitea to start and then open:

```bash
oc get route gitea -n gitea -o jsonpath='https://{.spec.host}'
```

In the Gitea UI, complete initial setup (use SQLite), create a user `swimadmin`, and create a repository named `swim-sfg-observability`.

---

## Step 5 — Push repo to Gitea

```bash
export GITEA_PASS=yourpassword
make gitea-push
```

---

## Step 6 — Apply AMQ Broker Operator and apps

```bash
make crc-deploy
```

Wait for the AMQ Broker operator to install and the broker pod to appear:

```bash
oc get pods -n swim-sfg-observability -w
```

The broker pod will be named `sfg-broker-ss-0`.

---

## Step 7 — Register ArgoCD Application

```bash
oc apply -f deployments/openshift/gitops/03-argocd-application.yaml
```

ArgoCD will sync the `deployments/openshift` path and keep all resources in sync with the Gitea repository.

---

## Verify

```bash
make crc-status
```

Expected pods:

```
NAME                               READY   STATUS
dnotam-consumer-xxx                1/1     Running
dnotam-originator-xxx              1/1     Running
dnotam-publisher-xxx               1/1     Running
grafana-xxx                        1/1     Running
loki-xxx                           1/1     Running
prometheus-xxx                     1/1     Running
sfg-broker-ss-0                    1/1     Running
tempo-xxx                          1/1     Running
```

Get the originator route and run the demo:

```bash
make crc-demo-valid
make crc-demo-invalid
```

Get Grafana route:

```bash
oc get route grafana -n swim-sfg-observability -o jsonpath='https://{.spec.host}'
```

---

## Notes

- The AMQ Broker headless service name is `sfg-broker-hdls-svc` — this is used as `AMQP_HOST` in app ConfigMaps.
- Tempo, Loki, Grafana, and Prometheus are deployed as simple Deployments (no operator) to minimise CRC resource usage.
- For production, replace these with the appropriate Red Hat operators (Loki Operator, Distributed Tracing Platform).
