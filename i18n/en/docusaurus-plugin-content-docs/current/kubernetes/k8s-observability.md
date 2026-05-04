---
sidebar_position: 6
---

# K8s Observability: Log Queries & Service Selection

## Pod Log Queries

```bash
# Single Pod
kubectl logs -f <pod-name>

# All replicas by label
kubectl logs -f -l app=my-app

# Grep across all Pods
kubectl logs -l app=my-app --all-containers | grep "keyword"
```

> **Python analogy**:
> ```python
> # kubectl logs -f <pod>  is equivalent to
> import subprocess
> subprocess.run(["tail", "-f", "/var/log/app.log"])
>
> # kubectl logs -l app=my-app  = tail logs from all workers simultaneously
> # Like watching stdout from all gunicorn worker processes at once
> ```

With multiple replicas, each Pod only has logs for part of the traffic. To find a specific request use centralized logging (CloudWatch Logs Insights, Loki) or trace IDs.

---

## Why kubectl logs Alone Isn't Enough

```
Assume you have 5 inference worker Pods, one request errored:

kubectl logs pod-1 → not there
kubectl logs pod-2 → not there
kubectl logs pod-3 → found it!

Problem: you don't know which Pod to look at.
```

```python
# Solution: add a trace_id to every log entry
import uuid
import logging

trace_id = str(uuid.uuid4())
logging.info(
    f"[{trace_id}] Starting inference",
    extra={"trace_id": trace_id}
)

# Then query across all Pods in CloudWatch Logs Insights:
# filter @message like "abc-123-def"
```

---

## Container Service Comparison (AWS)

| | EKS (Kubernetes) | Lambda |
|---|---|---|
| How it works | You manage Pods, runs continuously | Event-triggered, disappears when done |
| Best for | Long-running services, complex architecture | Short tasks (≤15 min), event-driven |
| Cost | Charged while nodes are running | Charged only for execution time |
| Management overhead | Manage nodes, scaling, deployments | Almost zero |

```python
# Python analogy:

# EKS = run your own FastAPI server, online 24/7
# uvicorn app:app --host 0.0.0.0 --port 8080
# → machine stays on, you pay whether or not there are requests

# Lambda = Python function, runs on call, disappears when done
def lambda_handler(event, context):
    result = model.predict(event["input"])
    return {"prediction": result}
# → no charge when idle, but cold start takes a few seconds
```

### Selection Guide

- **Inference system (your case) → EKS**: model must stay in memory, cold start is unacceptable, GPU required
- **Lightweight API, event processing → Lambda**: low traffic, no GPU needed, cold start acceptable

EKS = AWS-managed Kubernetes. AWS manages the control plane; you manage worker nodes and deployments.
