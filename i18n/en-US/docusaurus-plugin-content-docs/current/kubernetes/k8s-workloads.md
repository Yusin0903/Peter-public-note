---
sidebar_position: 3
---

# Workload Types

K8s workloads define "how your code runs." Choosing the wrong type leads to unstable services or wasted resources.

> **Python analogy overview**:
> - `Deployment` = long-running API server managed by `supervisor` or `systemd`
> - `StatefulSet` = PostgreSQL — data must survive restarts, name can't change
> - `DaemonSet` = `node_exporter` installed on every machine
> - `Job` = Python script that runs and exits (`sys.exit(0)`)
> - `CronJob` = `crontab` triggering a Python script on schedule

---

## Overview

| Type | Key Characteristic | Typical Use |
|------|-------------------|-------------|
| **Deployment** | Stateless, freely scalable replicas | API server, web app, proxy |
| **StatefulSet** | Stateful, fixed name + fixed PVC per Pod | Database, TSDB, Grafana |
| **DaemonSet** | One per node, auto-scales with new nodes | Log collector, metrics exporter |
| **Job** | Runs to completion (exit 0), no restart | DB migration, one-off scripts |
| **CronJob** | Creates Jobs on a schedule | Periodic backups, cleanup, reports |
| **ReplicaSet** | Almost never used directly | Created by Deployment under the hood |

---

## Lifecycle

```
Deployment / StatefulSet / DaemonSet → Runs continuously, auto-restarts on failure
Job                                  → Runs once, stops when done
CronJob                              → Triggers Jobs on schedule
```

```python
# Python analogy:
# Deployment  → while True: serve_request()    # FastAPI server
# Job         → process_batch(); sys.exit(0)    # run and exit
# CronJob     → schedule.every().hour.do(run)   # APScheduler
```

---

## Deployment vs StatefulSet

```
Deployment (API server, proxy):
  Pod-abc123 restarts → might become Pod-xyz789 (name changes)
  Doesn't matter which node it runs on, no dedicated disk

StatefulSet (database, TSDB):
  db-0 restarts → still db-0 (name is fixed)
  Has dedicated PVC, db-0's /data always uses the same disk
```

```python
# Deployment = stateless inference worker
# Restart is fine — model reloads, doesn't matter which GPU it lands on
class InferenceWorker:
    def __init__(self):
        self.model = load_model("weights.pt")  # stateless, restart is fine

# StatefulSet = stateful database node
# Must have fixed ID — replica 0 is primary, replica 1 is standby
class DatabaseNode:
    def __init__(self, node_id: int):
        self.node_id = node_id           # db-0, db-1 — names are fixed
        self.data_path = f"/data/{node_id}"  # mount a fixed disk
```

**Rule of thumb**: Need persistent data or fixed identity → `StatefulSet`. Everything else → `Deployment`.

---

## DaemonSet

```
# cluster has 3 nodes

Deployment replicas=2:               DaemonSet:
  node-1: [api-server]                node-1: [log-collector]
  node-2: [api-server]                node-2: [log-collector]
  node-3: (empty)                     node-3: [log-collector]

New node-4 joins:
  node-4: (won't auto-add)            node-4: [log-collector] ← automatic!
```

```python
# Python analogy:
# DaemonSet = system agent that must run on every machine
# Like deploying dcgm-exporter on every GPU server to collect GPU metrics
# New machine joins the cluster → automatically installed

for node in cluster.nodes:
    node.install(DcgmExporter())   # every node gets one
```

---

## ReplicaSet — Why Not Use Directly

```
You create a Deployment
  → Deployment auto-creates a ReplicaSet
  → ReplicaSet manages Pod count

Using ReplicaSet directly: no rolling update, no rollback
In practice, always use Deployment, never touch ReplicaSet directly
```

```python
# Python analogy:
# ReplicaSet = a plain list managing worker processes
# Deployment = ProcessPoolExecutor, manages the list + adds rolling update
# You use ProcessPoolExecutor (Deployment), not the raw list (ReplicaSet)

from concurrent.futures import ProcessPoolExecutor
executor = ProcessPoolExecutor(max_workers=3)  # use this (Deployment)
# Don't directly manage the underlying process list (ReplicaSet)
```
