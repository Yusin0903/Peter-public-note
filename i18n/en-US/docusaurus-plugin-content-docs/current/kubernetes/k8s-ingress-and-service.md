---
sidebar_position: 2
---

# Ingress & Service

## Three-Layer Architecture for Incoming Requests

```
External user
    │
    ▼
┌──────────┐
│  Ingress │  L7 routing rules (/api/* → Service A, /dashboard/* → Service B)
└──────────┘
    │
    ▼
┌──────────┐
│  Service │  Stable internal entrypoint, label selector for load balancing
└──────────┘
    │
    ▼
┌──────────┐
│   Pod    │  The container actually running your code
└──────────┘
```

> **Python analogy**: Like FastAPI's router architecture — Ingress is the `app.include_router()` routing table, Service is the `APIRouter`, Pod is the actual handler function.

---

## Ingress

- **What it is**: L7 routing rules table — defines "which host/path → which Service"
- **Not an endpoint itself** — the actual endpoint is exposed by the Ingress Controller
- Requires an Ingress Controller to work (AWS ALB Controller, NGINX, etc.)

### pathType Options

| pathType | Description |
|----------|-------------|
| `Exact` | Exact match (`/foo` only matches `/foo`) |
| `Prefix` | Prefix match, bounded by `/` |
| `ImplementationSpecific` | Delegated to the Ingress Controller (supports wildcard `*`) |

### Ingress NGINX Retirement (March 2026)

- What's retiring is the **Ingress NGINX Controller**, not the Ingress API itself
- Ingress API is GA, frozen but not deprecated
- Official recommendation: migrate to **Gateway API** (v1.5, released Feb 2026)
- AWS ALB Controller is unaffected (maintained by AWS)

---

## Service

### Three Types

| type | External Exposure | Use Case |
|------|------------------|----------|
| **ClusterIP** | Only within the cluster (default) | Internal service-to-service calls |
| **NodePort** | Fixed port on each Node (30000-32767) | Pair with external LB like ALB |
| **LoadBalancer** | Auto-creates a cloud LB | Production external-facing services |

> **Python analogy**:
> - `ClusterIP` = `localhost:8000` — only your own machine can connect
> - `NodePort` = binding to a fixed port number, like `uvicorn --port 30080`
> - `LoadBalancer` = nginx in front doing reverse proxy and load balancing

### port vs targetPort

```yaml
ports:
  - port: 80          # port the Service exposes (used within cluster)
    targetPort: 8081   # port the Pod actually listens on (= containerPort)
```

```python
# Python analogy:
# port=80 is what external traffic hits
# targetPort=8081 is what uvicorn actually binds to
# Like nginx: proxy_pass http://127.0.0.1:8081  but exposing port 80
```

### Internal DNS Resolution

K8s automatically creates DNS records for every Service. Pods connect by name:

```bash
# Same namespace → use Service name directly
curl http://my-service:80

# Cross-namespace → add namespace
curl http://my-service.other-namespace:80

# Full FQDN (rarely needed, most explicit)
curl http://my-service.other-namespace.svc.cluster.local:80
```

```python
# Python analogy: like /etc/hosts having an entry added automatically
# my-service  10.96.0.1
# httpx.get("http://my-service:80/health") just works

import httpx
# Inside a K8s Pod, this reaches another service in the same namespace
response = httpx.get("http://inference-service:8081/predict")
```
