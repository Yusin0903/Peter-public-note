---
sidebar_position: 6
---

# K8s 可觀測性：Log、Debug & 服務選型

## Pod Log 查詢

```bash
# 單一 Pod
kubectl logs -f <pod-name>

# 指定 container（一個 Pod 有多個 container 時）
kubectl logs -f <pod-name> -c <container-name>

# 用 label 看所有 replica 的 log（多 replica 首選）
kubectl logs -f -l app=my-app --max-log-requests=10

# 所有 Pod 的 log 一起 grep
kubectl logs -l app=my-app --all-containers | grep "keyword"

# 只看最近 100 行
kubectl logs <pod-name> --tail=100

# 看某個時間點之後的 log
kubectl logs <pod-name> --since=1h
kubectl logs <pod-name> --since-time="2024-01-15T10:00:00Z"
```

> **Python 類比**：
> ```python
> # kubectl logs -f <pod>  等同於
> import subprocess
> subprocess.run(["tail", "-f", "/var/log/app.log"])
>
> # kubectl logs -l app=my-app  等同於同時 tail 所有 worker 的 log
> # 就像你跑多個 gunicorn worker 想同時看所有 process 的 stdout
> ```

多 replica 時每個 Pod 只有部分流量的 log，要查特定 request 建議用集中式 log（如 CloudWatch Logs Insights、Loki）或 trace ID。

---

## 為什麼單靠 kubectl logs 不夠

```
假設你有 5 個 inference worker Pod，某個 request 出錯：

kubectl logs pod-1 → 沒有那筆 log
kubectl logs pod-2 → 沒有那筆 log
kubectl logs pod-3 → 找到了！

問題：你不知道要看哪個 Pod。
```

```python
# 解法 1：在每個 log 裡加 trace_id
import uuid
import logging

trace_id = str(uuid.uuid4())
logging.info(f"[{trace_id}] Starting inference", extra={"trace_id": trace_id})

# 之後在 CloudWatch Logs Insights 用 trace_id 跨 Pod 查詢：
# filter @message like "abc-123-def"
```

---

## kubectl describe — 看 Pod 狀態和 Events

`kubectl describe` 是 debug 的第一步，比 `kubectl get` 顯示更多細節：

```bash
# 看 Pod 詳細狀態
kubectl describe pod <pod-name>

# 看 Deployment 狀態（包含 rolling update 進度）
kubectl describe deployment <deployment-name>

# 看 Node 狀態（確認 GPU 資源是否可用）
kubectl describe node <node-name>
```

`kubectl describe pod` 的輸出重點：

```
Name:         inference-server-7d9f8b-abc12
Namespace:    inference
Node:         ip-10-0-1-5.us-west-2.compute.internal/10.0.1.5
Status:       Running

Containers:
  inference-server:
    State:    Running
    Ready:    True             ← readinessProbe 通過了嗎？

Conditions:
  Ready:      True             ← Pod 整體是否 ready

Events:                        ← 最重要的 debug 資訊在這裡
  Warning  BackOff    5m   kubelet   Back-off restarting failed container
  Normal   Pulled     10m  kubelet   Successfully pulled image
  Warning  OOMKilled  15m  kubelet   Container was OOMKilled
```

> **Python 類比**：
> ```python
> # kubectl describe pod 就像 Python 的 traceback + process info
> import traceback
> import psutil
>
> proc = psutil.Process()
> print(f"Memory: {proc.memory_info().rss / 1024**3:.1f} GB")
> print(f"Status: {proc.status()}")
> # 相當於 kubectl describe 的 State + Resources 部分
> ```

---

## kubectl exec — 進入 Pod 內部

當 log 不夠用時，直接進到 Pod 裡面執行命令：

```bash
# 進入互動式 shell（類似 SSH）
kubectl exec -it <pod-name> -- /bin/bash
kubectl exec -it <pod-name> -- /bin/sh   # 如果沒有 bash

# 指定 container（多容器 Pod）
kubectl exec -it <pod-name> -c <container-name> -- /bin/bash

# 直接跑一個命令（不進互動式）
kubectl exec <pod-name> -- python -c "import torch; print(torch.cuda.is_available())"
kubectl exec <pod-name> -- nvidia-smi
kubectl exec <pod-name> -- cat /proc/meminfo
```

```python
# 常用的 inference debug 命令（在 Pod 內執行）：

# 確認 GPU 是否可見
# kubectl exec <pod> -- python -c "
import torch
print(f"CUDA available: {torch.cuda.is_available()}")
print(f"GPU count: {torch.cuda.device_count()}")
print(f"GPU name: {torch.cuda.get_device_name(0)}")

# 確認 model 有沒有正確載入
import gc
print(f"GPU memory allocated: {torch.cuda.memory_allocated()/1024**3:.1f} GB")
print(f"GPU memory reserved: {torch.cuda.memory_reserved()/1024**3:.1f} GB")
# "
```

> **Python 類比**：
> ```python
> # kubectl exec -it <pod> -- bash
> # 就像 SSH 進到你的 EC2 instance，或是 Docker 的 docker exec -it
> import subprocess
> subprocess.run(["docker", "exec", "-it", "container_id", "/bin/bash"])
> ```

---

## kubectl top — 查看資源使用量

```bash
# 看所有 Pod 的 CPU/Memory 使用量
kubectl top pods -n inference

# 看所有 Node 的資源使用量
kubectl top nodes

# 持續更新（watch 模式）
watch -n 2 kubectl top pods -n inference
```

輸出範例：
```
NAME                                CPU(cores)   MEMORY(bytes)
inference-server-7d9f8b-abc12       3500m        14Gi
inference-server-7d9f8b-xyz34       2800m        13Gi
batch-job-1234-abcde                4000m        20Gi   ← 可能快 OOMKilled
```

**注意**：`kubectl top` 需要 cluster 安裝了 metrics-server。EKS 預設沒有，需要另外安裝。

> **Python 類比**：
> ```python
> # kubectl top pods ≈ psutil 查所有 process 的資源使用
> import psutil
>
> for proc in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_info']):
>     print(f"{proc.info['name']}: "
>           f"CPU={proc.info['cpu_percent']}% "
>           f"MEM={proc.info['memory_info'].rss / 1024**3:.1f}GB")
> ```

---

## kubectl get events — 看 cluster 事件

Events 是 K8s 裡最重要但最常被忽略的 debug 工具。Pod 掛掉前 K8s 通常會先記錄 event：

```bash
# 看某個 namespace 的所有 events（按時間排序）
kubectl get events -n inference --sort-by='.lastTimestamp'

# 只看 Warning 事件
kubectl get events -n inference --field-selector type=Warning

# 持續監看新事件
kubectl get events -n inference -w
```

常見的重要 events：

| Event | 意思 |
|---|---|
| `OOMKilled` | 容器超過 memory limits 被殺 |
| `BackOff` | 容器一直重啟，K8s 在等待後退 |
| `FailedScheduling` | 找不到合適的 node（資源不足、GPU 不夠） |
| `Pulled` | Image pull 完成 |
| `Failed` | Image pull 失敗（ECR 權限問題？） |
| `Unhealthy` | Liveness/Readiness probe 失敗 |

```bash
# 常見看法：先看 warning events
kubectl get events -n inference \
  --field-selector type=Warning \
  --sort-by='.lastTimestamp' | tail -20
```

---

## CrashLoopBackOff 診斷流程

這是 inference system 最常遇到的問題，尤其是 model 載入失敗時。以下是系統化的診斷步驟：

```
Pod Status = CrashLoopBackOff
     │
     ▼
Step 1: 看最後一次的 log
     kubectl logs <pod-name> --previous
     （--previous 看上一次崩潰的 log，而不是現在正在跑的）
     │
     ├── 看到 OOMKilled → memory limits 太小，或 model 太大
     ├── 看到 CUDA error → GPU driver / CUDA 版本不符
     ├── 看到 ImportError → image 裡缺少 dependency
     └── 沒有 log → 可能在 startup 就崩了
     │
     ▼
Step 2: kubectl describe pod <pod-name>
     看 Events 區塊：
     ├── OOMKilled → 調高 memory limits
     ├── BackOff restarting → 看上面的 log
     └── Unhealthy → readinessProbe 設定有問題
     │
     ▼
Step 3: kubectl get events -n <namespace> --sort-by='.lastTimestamp'
     看有沒有 FailedScheduling（資源不夠）
     或 FailedMount（volume 掛不上去）
     │
     ▼
Step 4: kubectl exec -it <pod-name> -- /bin/bash
     如果 Pod 短暫 running 就能進去
     手動執行 python your_script.py 看完整錯誤
     或：kubectl run debug --image=your-image -it --rm -- /bin/bash
```

> **Python 類比**：
> ```python
> # CrashLoopBackOff 診斷就像 debug 一個一直重啟的 supervisor 程式
>
> # Step 1: 看 crash 前的 log（--previous 等同於看 supervisor 的 stderr log）
> # tail -f /var/log/supervisor/inference-server-stderr.log
>
> # Step 2: 用 strace 或 py-spy 看程式卡在哪
> # py-spy dump --pid <PID>
>
> # Step 3: 直接跑程式看完整 traceback
> # python -c "from your_app import app; app.startup()"
> ```

### 常見 CrashLoopBackOff 原因（inference system）

| 原因 | 症狀 | 解法 |
|---|---|---|
| Model 太大，OOMKilled | `kubectl describe` 顯示 OOMKilled | 調高 `limits.memory` |
| CUDA / GPU driver 版本不符 | log 顯示 `CUDA error: no kernel image` | 確認 image 的 CUDA 版本 vs 機器 driver |
| S3 權限不足（model 下載失敗） | init container 失敗，AccessDenied | 確認 IRSA / ServiceAccount 設定 |
| readinessProbe 太嚴 | Pod 一直重啟，log 顯示 Unhealthy | 調大 `initialDelaySeconds` |
| Port 衝突 | `address already in use` | 確認 `containerPort` 設定 |
| 缺少環境變數 | `KeyError` 或 `None` type error | 確認 env / Secret 設定 |

---

## 容器服務比較（以 AWS 為例）

| | EKS (Kubernetes) | Lambda |
|---|---|---|
| 運作方式 | 你管 Pod，持續運行 | 事件觸發，跑完消失 |
| 適合 | 長時間服務、複雜架構 | 短任務（≤15 min）、事件驅動 |
| 費用 | Node 開著就收錢 | 只收執行時間 |
| 管理成本 | 要管 node、scaling、部署 | 幾乎不用管 |

```python
# Python 類比：

# EKS = 你自己跑 FastAPI server，24hr 在線
# uvicorn app:app --host 0.0.0.0 --port 8080
# → 機器一直開著，不管有沒有 request 都在燒錢

# Lambda = Python function，呼叫才跑，跑完就消失
def lambda_handler(event, context):
    result = model.predict(event["input"])
    return {"prediction": result}
# → 沒有 request 不收費，但 cold start 要等幾秒
```

### 選擇原則

- **inference system（你的情境）→ EKS**：model 要常駐記憶體，cold start 不可接受，需要 GPU
- **輕量 API、事件處理 → Lambda**：低流量、不需要 GPU、可以接受 cold start

EKS = AWS 代管的 Kubernetes，幫你管 control plane，你只管 worker node 和部署。
