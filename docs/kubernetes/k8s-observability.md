---
sidebar_position: 6
---

# K8s 可觀測性：Log 查詢 & 服務選型

## Pod Log 查詢

```bash
# 單一 Pod
kubectl logs -f <pod-name>

# 用 label 看所有 replica 的 log
kubectl logs -f -l app=my-app

# 所有 Pod 的 log 一起 grep
kubectl logs -l app=my-app --all-containers | grep "keyword"
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
