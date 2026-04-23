---
sidebar_position: 3
---

# Workload 類型

K8s 的 workload 就是「跑程式的方式」，選錯類型會讓你的服務不穩定或浪費資源。

> **Python 類比總覽**：
> - `Deployment` = 你用 `supervisor` 或 `systemd` 跑的長駐 API server
> - `StatefulSet` = PostgreSQL — 重啟後資料還要在、名字不能變
> - `DaemonSet` = 每台機器都要裝的 `node_exporter`
> - `Job` = Python script 跑完就退出（`sys.exit(0)`）
> - `CronJob` = `crontab` 定時觸發 Python script

---

## 完整一覽

| 類型 | 核心特性 | 典型用途 |
|------|---------|---------|
| **Deployment** | 無狀態，replicas 自由調整 | API server、web app、proxy、reverse proxy |
| **StatefulSet** | 有狀態，固定名字 + 固定 PVC | 資料庫、時序資料庫（TSDB）、Grafana |
| **DaemonSet** | 每台 node 跑一個，node 增加自動擴展 | log collector、node metrics exporter |
| **Job** | 跑完（exit 0）就停止，不重啟 | DB migration、一次性腳本 |
| **CronJob** | 定時產生 Job | 定時備份、定時清理、定期報表 |
| **ReplicaSet** | 幾乎不直接用 | Deployment 底層自動建立，管 Pod 數量 |

---

## 生命週期

```
Deployment / StatefulSet / DaemonSet → 一直跑，掛了自動重啟
Job                                  → 跑完就停，不重啟
CronJob                              → 定時產生 Job
```

```python
# Python 類比：
# Deployment  → while True: serve_request()   # FastAPI server
# Job         → process_batch(); sys.exit(0)   # 跑完就退
# CronJob     → schedule.every().hour.do(run)  # APScheduler
```

---

## Deployment vs StatefulSet

```
Deployment（API server、proxy）：
  Pod-abc123 重啟 → 可能變成 Pod-xyz789（名字不固定）
  掛在哪台 node 無所謂，沒有自己的硬碟

StatefulSet（資料庫、TSDB）：
  db-0 重啟 → 還是 db-0（名字固定）
  有固定的 PVC，db-0 的 /data 永遠掛同一顆硬碟
```

```python
# Python 類比：

# Deployment = 無狀態的 inference worker
# 重啟後 model 重新 load，用哪張卡無所謂
class InferenceWorker:
    def __init__(self):
        self.model = load_model("weights.pt")  # stateless，重啟沒差

# StatefulSet = 有狀態的資料庫連線
# 必須有固定 ID，因為 replica 0 是 primary，replica 1 是 standby
class DatabaseNode:
    def __init__(self, node_id: int):
        self.node_id = node_id        # db-0, db-1 名字固定
        self.data_path = f"/data/{node_id}"  # 掛固定磁碟
```

**選擇原則**：需要持久化資料或固定 identity → `StatefulSet`，其他 → `Deployment`。

---

## DaemonSet

```
# cluster 有 3 台 node

Deployment replicas=2：           DaemonSet：
  node-1: [api-server]             node-1: [log-collector]
  node-2: [api-server]             node-2: [log-collector]
  node-3: (空的)                   node-3: [log-collector]

新 node-4 加入：
  node-4: (不會自動加)              node-4: [log-collector] ← 自動！
```

```python
# Python 類比：
# DaemonSet 就像「每台機器都要跑的系統 agent」
# 例如你在每台 GPU server 上都裝了 dcgm-exporter 收 GPU metrics
# 新機器加入 cluster 就自動安裝，不用手動操作

# 類似這個概念：
for node in cluster.nodes:
    node.install(DcgmExporter())   # 每台都裝
```

適合「需要在每台機器上收集資料」的 agent，例如 log collector、node metrics exporter。

---

## ReplicaSet — 為什麼不直接用

```
你建 Deployment
  → Deployment 自動建 ReplicaSet
  → ReplicaSet 管 Pod 數量

直接建 ReplicaSet 缺少 rolling update、rollback 功能
實務上只用 Deployment，不直接碰 ReplicaSet
```

```python
# Python 類比：
# ReplicaSet 就像 Python list 管理 worker processes
# Deployment 像 ProcessPoolExecutor，幫你管 list + 提供 rolling update
# 你不會直接操作 list，你只操作 ProcessPoolExecutor

from concurrent.futures import ProcessPoolExecutor
# 你用這個（Deployment）
executor = ProcessPoolExecutor(max_workers=3)
# 不直接操作底層的 process list（ReplicaSet）
```
