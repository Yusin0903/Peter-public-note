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
│  Ingress │  L7 routing rules (/api/* → Service A, /dashboard/* → Service B)
└──────────┘
    │
    ▼
┌──────────┐
│  Service │  Stable internal entrypoint, uses label selector for load balancing
└──────────┘
    │
    ▼
┌──────────┐
│   Pod    │  The container actually running your code
└──────────┘
```

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
| `ImplementationSpecific` | Delegated to the Ingress Controller (can support wildcard `*`) |

### Ingress NGINX Retirement (March 2026)

- What's retiring is the **Ingress NGINX Controller**, not the Ingress API itself
- Ingress API is GA, frozen but not deprecated
- Official recommendation: migrate to **Gateway API** (v1.5, released Feb 2026)
- AWS ALB Controller is unaffected (maintained by AWS)

---

## Service

### Three Types

| type | External Exposure | Use Case |
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

K8s automatically creates DNS records for every Service. Pods can connect to each other by name:

```bash
# Same namespace → use Service name directly
curl http://my-service:80

# Cross-namespace → add namespace name
curl http://my-service.other-namespace:80

# Full FQDN (rarely used, but most explicit)
curl http://my-service.other-namespace.svc.cluster.local:80
```

---

## Workload Types Overview

| Type | Key Characteristic | Typical Use |
|------|---------|---------|
| **Deployment** | Stateless, freely scalable replicas | API server, web app, proxy |
| **StatefulSet** | Stateful, fixed name + fixed PVC per Pod | Database, time-series DB, Grafana |
| **DaemonSet** | One per node, auto-scales with new nodes | Log collector, metrics exporter |
| **Job** | Runs to completion (exit 0), doesn't restart | DB migration, one-off scripts |
| **CronJob** | Creates Jobs on a schedule | Periodic backups, cleanup, reports |
| **ReplicaSet** | Almost never used directly | Created by Deployment under the hood |

### Lifecycle

```
Deployment / StatefulSet / DaemonSet → Runs continuously, auto-restarts on failure
Job                                  → Runs once, stops when complete
CronJob                              → Creates Jobs on schedule
```

### StatefulSet vs Deployment

```
Deployment (API server, proxy):
  Pod-abc123 restarts → might become Pod-xyz789 (name changes)
  Doesn't matter which node it runs on, no dedicated disk

StatefulSet (database, TSDB):
  db-0 restarts → still db-0 (name is fixed)
  Has a dedicated PVC, db-0's /data always uses the same disk
```

**Rule of thumb**: Need persistent data or fixed identity → StatefulSet. Everything else → Deployment.

### DaemonSet

```
# cluster has 3 nodes

Deployment replicas=2:               DaemonSet:
  node-1: [api-server]                node-1: [log-collector]
  node-2: [api-server]                node-2: [log-collector]
  node-3: (empty)                     node-3: [log-collector]

New node-4 joins:
  node-4: (won't auto-add)            node-4: [log-collector] ← automatic!
```

Ideal for agents that need to collect data from every machine — log collectors, node metrics exporters.

### ReplicaSet — Why Not Use Directly

```
You create a Deployment
  → Deployment auto-creates a ReplicaSet
  → ReplicaSet manages Pod count

Using ReplicaSet directly lacks rolling update and rollback features.
In practice, always use Deployment.
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

With multiple replicas, each Pod only has logs for part of the traffic. To find a specific request, use centralized logging (e.g., CloudWatch Logs Insights, Loki) or trace IDs.

---

## Container Service Comparison (AWS Example)

| | EKS (Kubernetes) | Lambda |
|---|---|---|
| How it works | You manage Pods, runs continuously | Event-triggered, disappears when done |
| Best for | Long-running services, complex architecture | Short tasks (≤15 min), event-driven |
| Cost | Charged while nodes are running | Charged only for execution time |
| Management overhead | Manage nodes, scaling, deployments | Almost zero management |

EKS = AWS-managed Kubernetes. AWS manages the control plane; you manage worker nodes and deployments.

---

## K8s Storage: StorageClass / PVC / PV

### Three-Layer Relationship

```
StorageClass (specification template)
  → Defines "how to create disks" (type, provisioner, reclaim policy)
  → Only a few per cluster, shared by all pods

PVC — PersistentVolumeClaim (request form)
  → Pod says "I need a 500Gi gp3 disk"
  → Each pod that needs storage gets its own PVC

PV — PersistentVolume (the actual disk)
  → K8s auto-creates this when it receives a PVC
  → Maps to a real cloud disk (AWS EBS, GCP PD, etc.)
```

### Analogy

```
StorageClass = Restaurant menu (defines available disk specs)
PVC = Order slip (customer: "I want the gp3 combo, 500Gi size")
PV = The dish that comes out of the kitchen (the actual volume)
```

### StorageClass Example

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com        # Who creates the disk (AWS EBS CSI Driver)
parameters:
  type: gp3                          # Disk type
  fsType: ext4                       # File system
volumeBindingMode: WaitForFirstConsumer  # Wait until pod is scheduled (ensures same AZ)
allowVolumeExpansion: true           # Can expand later without recreating
reclaimPolicy: Retain                # Keep volume after pod deletion
```

### PVC Example

```yaml
volumeClaimTemplate:
  spec:
    storageClassName: gp3        # Which StorageClass to use
    resources:
      requests:
        storage: 500Gi           # How much
```

### Full Creation Flow

```
1. StorageClass "gp3" exists (defines disk spec)

2. StatefulSet declares PVC: storageClassName: gp3, storage: 500Gi

3. K8s scheduler places pod on node-1 (us-west-2a)

4. WaitForFirstConsumer → volume creation starts NOW
   K8s reads PVC → finds StorageClass "gp3" → calls provisioner
   → Cloud API creates 500Gi disk (same AZ)

5. K8s creates PV, binds PVC ↔ PV ↔ actual disk

6. Disk mounted to node → pod can read/write
```

### Lifecycle

| Event | PVC | PV | Actual Disk |
|---|---|---|---|
| Pod created | Created | Auto-created | Cloud auto-creates |
| Pod restarts | Unchanged | Unchanged | Unchanged (data preserved) |
| Pod moves to another node (same AZ) | Unchanged | Unchanged | Detach + reattach |
| Pod deleted | Deleted | Depends on reclaimPolicy | Retain → kept / Delete → removed |

### reclaimPolicy

```
Retain  → Pod deleted, disk stays, data preserved (databases, TSDB)
Delete  → Pod deleted, disk auto-deleted (temporary cache)
```

### volumeBindingMode

```
Immediate           → Disk created when PVC is created
                       Problem: might be in a different AZ from the pod → mount fails
WaitForFirstConsumer → Disk created after pod is scheduled
                       Ensures disk and pod are in the same AZ ✓
```

### Cloud Disk vs Node Local Disk

| | Cloud Disk (EBS / PD) | Node Local Disk |
|---|---|---|
| Nature | Independent network-attached disk | Node's built-in root disk |
| Node deleted | Disk survives | Data lost |
| Pod moves | Can reattach to another node | Cannot |
| Best for | Data that must persist | Temporary cache |

### IOPS vs Throughput

```
IOPS = I/O Operations Per Second
  → Matters for: frequent small writes (e.g., real-time metrics, each write is tiny but high frequency)
  → Analogy: how many books a librarian can pick up per second

Throughput = Data transfer rate (MiB/s)
  → Matters for: large sequential reads (e.g., querying historical data, scanning GBs at once)
  → Analogy: how many kilograms of books a librarian can carry per second
```

### AWS EBS gp2 vs gp3 (Common Choices)

| | gp2 | gp3 |
|---|---|---|
| Price/GiB/month | $0.10 | $0.08 (20% cheaper) |
| IOPS | Tied to capacity (3 IOPS/GiB) | Fixed 3000 baseline (regardless of size) |
| Throughput | Up to 250 MiB/s | 125 MiB/s baseline, up to 1000 MiB/s |
| IOPS adjustable | No — must increase capacity to get more IOPS | Yes — independently adjustable, up to 16000 |

gp3 is better than gp2 in almost every scenario. AWS officially recommends gp3 for new workloads.

**gp2 pain point**: To get 3000 IOPS, you must provision a 1000GiB volume (wasting space and money). gp3 gives 3000 IOPS regardless of volume size.
