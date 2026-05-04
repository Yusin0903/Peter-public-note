---
sidebar_position: 1
---

# Kubernetes Core Concepts

K8s core architecture is split into focused topics, each with Python analogies for quick intuition.

## Navigation

| Topic | Content |
|-------|---------|
| [Ingress & Service](./k8s-ingress-and-service) | How requests flow from outside into Pods, 3 Service types, internal DNS |
| [Workload Types](./k8s-workloads) | Deployment / StatefulSet / DaemonSet / Job / CronJob — which to pick |
| [Storage](./k8s-storage) | StorageClass / PVC / PV three-layer model, gp2 vs gp3, IOPS vs Throughput |
| [CronJob](./k8s-cronjob) | Scheduled task config, concurrencyPolicy, typical use cases |
| [Observability](./k8s-observability) | Pod log queries, multi-replica log problem, EKS vs Lambda selection |

---

## Quick Mental Model

```
Incoming traffic:
  Internet → Ingress (routing rules) → Service (finds Pods) → Pod (runs your code)

Workload types for an inference system:
  - Model server (long-running)  → Deployment
  - Database / vector DB         → StatefulSet
  - Log collector                → DaemonSet
  - Batch inference              → CronJob
  - DB migration                 → Job
```

```python
# The whole K8s cluster is like a deployment platform for a Python app:

# Deployment  = uvicorn running FastAPI server (multiple replicas)
# StatefulSet = PostgreSQL (data must persist, name must be stable)
# DaemonSet   = dcgm-exporter on every GPU server (node-level agent)
# Job         = python migrate.py (runs once and exits)
# CronJob     = crontab's K8s equivalent (triggers Jobs on schedule)
```

---

## Quick Reference

For detailed K8s glossary see [K8s Glossary](./k8s-glossary).
