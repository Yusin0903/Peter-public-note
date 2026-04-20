---
sidebar_position: 1
---

# Kubernetes Core Concepts

## Three-Layer Architecture for Incoming Requests

```
External user
    │
    ▼
┌──────────┐
│  Ingress │  L7 routing rules (/api/v1/* → Service A, /dashboard/* → Service B)
└──────────┘
    │
    ▼
┌──────────┐
│  Service │  Stable internal entrypoint, uses label selector to find Pods for load balancing
└──────────┘
    │
    ▼
┌──────────┐
│   Pod    │  The container actually running your code
└──────────┘
```

---

## Ingress

- **What it is**: An L7 routing rules table — defines "which path → which Service"
- **Not an endpoint itself** — the actual endpoint is exposed by the Ingress Controller
- Requires an Ingress Controller to work (AWS ALB Controller, NGINX, etc.)

### pathType Options

| pathType | Description |
|----------|-------------|
| `Exact` | Exact match (`/foo` only matches `/foo`) |
| `Prefix` | Prefix match, bounded by `/` |
| `ImplementationSpecific` | Delegated to the Ingress Controller (can support wildcard `*`) |

### Ingress NGINX Retirement (March 2026)

- What's retiring is the **Ingress NGINX Controller**, not the Ingress API itself
- Ingress API is GA, frozen but not deprecated
- Official recommendation: migrate to **Gateway API** (v1.5, released Feb 2026)
- AWS ALB Controller is unaffected (maintained by AWS)

---

## Service

### Three Types

| type | External exposure | Use case |
|------|:---:|:---:|
| **ClusterIP** | Only within the cluster (default) | Internal service-to-service calls |
| **NodePort** | Fixed port on each Node (30000-32767) | Pair with external LB like ALB |
| **LoadBalancer** | Auto-creates a cloud LB | Production external-facing services |

### port vs targetPort

```yaml
ports:
  - port: 80          # port the Service exposes (used within cluster)
    targetPort: 8081   # port the Pod actually listens on (= containerPort)
```

### Internal DNS Resolution

```bash
# Same namespace → use name directly
curl http://my-service:80

# Cross-namespace → add namespace
curl http://my-service.my-namespace:80

# Full FQDN
curl http://my-service.my-namespace.svc.cluster.local:80
```

---

## CronJob

```yaml
schedule: "10 */1 * * *"        # runs at minute 10 every hour
concurrencyPolicy: Forbid       # don't start new run if previous isn't done
successfulJobsHistoryLimit: 1   # keep only 1 successful run record
backoffLimit: 3                 # retry up to 3 times on failure
```

---

## Pod Log Queries

```bash
# Single Pod
kubectl logs -f <pod-name>

# All replicas by label
kubectl logs -f -l app=my-app

# Grep across all Pods
kubectl logs -l app=my-app --all-containers | grep "keyword"
```

With multiple replicas, each Pod only has logs for part of the traffic. To find a specific request, use centralized logging (CloudWatch Logs Insights) or trace IDs.

---

## AWS Container Service Comparison

| | EKS (Kubernetes) | Lambda |
|---|---|---|
| How it works | You manage Pods, runs continuously | Event-triggered, disappears when done |
| Best for | Long-running services, complex architecture | Short tasks (≤15 min), event-driven |
| Cost | Charged while nodes are running | Charged only for execution time |
| Management overhead | Manage nodes, scaling, deployments | Almost zero management |

EKS = AWS-managed Kubernetes. AWS manages the control plane; you manage worker nodes and deployments.
