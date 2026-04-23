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

---

## Rolling Update 策略

當你更新 image tag 時，Deployment 預設用 rolling update：先起新 Pod，等它 ready 再殺舊 Pod，保持服務不中斷。

```yaml
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1          # 最多額外多開幾個 Pod（超出 replicas 的數量）
      maxUnavailable: 0    # 最多幾個 Pod 可以不可用（0 = 零停機）
```

```
replicas=4，maxSurge=1，maxUnavailable=0 的更新流程：

Step 1: 起 1 個新 Pod v2        → 5 個 Pod（4 v1 + 1 v2）
Step 2: v2 Ready → 殺 1 個 v1  → 4 個 Pod（3 v1 + 1 v2）
Step 3: 起 1 個新 Pod v2        → 5 個 Pod（3 v1 + 2 v2）
Step 4: v2 Ready → 殺 1 個 v1  → 4 個 Pod（2 v1 + 2 v2）
... 直到全部換完
```

> **Python 類比**：
> ```python
> # maxSurge=1, maxUnavailable=0 就像 blue-green 的滾動版本
> # 先起新 worker，確認健康後再殺舊的
> # 類似 Gunicorn graceful reload：
> # kill -HUP <gunicorn_pid>
> # → Gunicorn 先起新 worker，等它 ready，再殺舊 worker
> ```

**inference system 建議**：
- `maxUnavailable: 0`：確保更新期間服務不中斷
- `maxSurge: 1`：GPU Pod 資源寶貴，不要一次開太多新的
- model 載入慢的話，搭配 readinessProbe 的 `initialDelaySeconds` 確保新 Pod 真的 ready 才切流量

---

## Init Container — model 下載前置作業

Init Container 在主容器啟動前執行，**跑完才啟動主容器**。適合用來做 model 下載、設定檔初始化等前置作業。

```
Pod 啟動順序：
  [init-container-1 跑完] → [init-container-2 跑完] → [主容器啟動]

如果任何 init container 失敗 → 整個 Pod 重試（直到成功）
```

```yaml
spec:
  initContainers:
    - name: download-model
      image: amazon/aws-cli:latest
      command:
        - sh
        - -c
        - |
          aws s3 cp s3://my-models/llm-7b/weights.bin /model-cache/weights.bin
          echo "Model downloaded successfully"
      env:
        - name: AWS_DEFAULT_REGION
          value: us-west-2
      volumeMounts:
        - name: model-cache
          mountPath: /model-cache

  containers:
    - name: inference-server
      image: my-inference-server:latest
      volumeMounts:
        - name: model-cache
          mountPath: /model-cache   # 同一個 volume，共享下載的 model
```

> **Python 類比**：
> ```python
> # Init Container 就像 Python 的 __init__ 或 setup fixture
> # 主程式跑之前必須先執行完的前置步驟
>
> # 等同於：
> def startup():
>     # init container 做的事
>     download_model_from_s3("s3://my-models/weights.bin", "/model-cache/")
>
> def main():
>     # 主容器做的事
>     model = load_model("/model-cache/weights.bin")
>     serve(model)
>
> startup()   # 必須先跑完
> main()      # 才開始 serve
> ```

**為什麼不在主容器裡下載？**
- Init container 可以用不同的 image（輕量的 aws-cli vs 你的 inference image）
- 失敗時只重跑 init container，不影響已啟動的主容器
- 清楚分離「準備階段」和「服務階段」

---

## Sidecar 模式

Sidecar 是跑在同一個 Pod 裡、與主容器並行的輔助容器。它們共享 network namespace（同一個 localhost）和可以共享 volume。

```
Pod（同一個 network namespace）：
  ┌──────────────────┐  ┌──────────────────┐
  │  inference-server │  │   log-shipper    │
  │  :8080           │  │  (Fluentd)       │
  │  寫 log 到 /logs  │  │  讀 /logs 送 S3  │
  └──────────────────┘  └──────────────────┘
         │                      │
         └──────┬───────────────┘
                │ 共享 emptyDir volume（/logs）
```

```yaml
spec:
  containers:
    - name: inference-server
      image: my-inference-server:latest
      volumeMounts:
        - name: log-volume
          mountPath: /logs

    - name: log-shipper          # sidecar
      image: fluent/fluentd:latest
      volumeMounts:
        - name: log-volume
          mountPath: /logs       # 同一個 volume

  volumes:
    - name: log-volume
      emptyDir: {}               # Pod 內共享，Pod 刪了就消失
```

> **Python 類比**：
> ```python
> # Sidecar 就像 Python process 旁邊跑的 background thread
> import threading
>
> def inference_server():
>     while True:
>         result = model.predict(get_request())
>         log_queue.put(result)    # 寫到共享 queue
>
> def log_shipper():              # sidecar
>     while True:
>         log = log_queue.get()
>         send_to_s3(log)         # 讀 queue，送到 S3
>
> # 兩個 thread 跑在同一個 process（同一個 Pod）
> t1 = threading.Thread(target=inference_server)
> t2 = threading.Thread(target=log_shipper)
> ```

常見 sidecar 用途：
- **Log shipping**：主容器寫 log 到本地，sidecar 負責送到 S3/ElasticSearch
- **Metrics 收集**：sidecar 收集並 expose `/metrics` endpoint
- **Secret 注入**：Vault agent sidecar 動態更新 secret 檔案

---

## 真實 GPU Inference Deployment YAML

這是一個生產級別的 GPU inference server Deployment，整合了前面所有概念：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llm-inference-server
  namespace: inference
  labels:
    app: llm-inference
    version: "v1.2.0"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: llm-inference
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0    # 零停機更新

  template:
    metadata:
      labels:
        app: llm-inference
        version: "v1.2.0"
    spec:
      # GPU node 選擇：只排程到有 GPU 的機器
      nodeSelector:
        accelerator: nvidia-gpu

      # 容忍 GPU node 的 taint（如果你的 GPU node 有設 taint）
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule

      # Init container：從 S3 下載 model weights
      initContainers:
        - name: download-model
          image: amazon/aws-cli:2
          command:
            - sh
            - -c
            - |
              if [ ! -f /model-cache/weights.bin ]; then
                echo "Downloading model..."
                aws s3 cp s3://my-models/llm-7b/ /model-cache/ --recursive
              else
                echo "Model already cached, skipping download"
              fi
          env:
            - name: AWS_DEFAULT_REGION
              value: us-west-2
          resources:
            requests:
              cpu: "0.5"
              memory: "512Mi"
            limits:
              cpu: "1"
              memory: "1Gi"
          volumeMounts:
            - name: model-cache
              mountPath: /model-cache

      containers:
        - name: inference-server
          image: my-org/llm-server:1.2.0
          ports:
            - containerPort: 8080
              name: http
            - containerPort: 9090
              name: metrics

          # GPU + CPU + Memory 資源設定
          resources:
            requests:
              nvidia.com/gpu: "1"
              cpu: "4"
              memory: "16Gi"
            limits:
              nvidia.com/gpu: "1"    # GPU limits 必須 = requests
              cpu: "8"
              memory: "32Gi"

          # 環境變數
          env:
            - name: MODEL_PATH
              value: /model-cache
            - name: MAX_BATCH_SIZE
              value: "32"
            - name: CUDA_VISIBLE_DEVICES
              value: "0"

          # Readiness：model 載入完才接流量
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 8080
            initialDelaySeconds: 60   # model 載入通常需要 30-90s
            periodSeconds: 10
            failureThreshold: 12      # 容忍 120s 的載入時間
            successThreshold: 1

          # Liveness：確認程式沒有 deadlock/crash
          livenessProbe:
            httpGet:
              path: /health/live
              port: 8080
            initialDelaySeconds: 120  # 必須比 readiness 晚
            periodSeconds: 30
            failureThreshold: 3
            timeoutSeconds: 10

          volumeMounts:
            - name: model-cache
              mountPath: /model-cache
            - name: shm               # 共享記憶體，PyTorch dataloader 需要
              mountPath: /dev/shm

        # Sidecar：metrics 收集
        - name: metrics-exporter
          image: prom/statsd-exporter:latest
          ports:
            - containerPort: 9102
          resources:
            requests:
              cpu: "100m"
              memory: "64Mi"
            limits:
              cpu: "200m"
              memory: "128Mi"

      volumes:
        - name: model-cache
          emptyDir:
            medium: ""              # 預設用磁碟（可改 Memory 但會佔 RAM）
            sizeLimit: 20Gi         # 限制大小防止爆磁碟
        - name: shm
          emptyDir:
            medium: Memory          # /dev/shm 必須是 Memory type
            sizeLimit: 8Gi
```

**關鍵設計決策說明**：
- `emptyDir` 存 model cache：Pod 重啟需要重下載，但避免 PVC 的 AZ 綁定問題
- `/dev/shm` 用 `medium: Memory`：PyTorch 的 DataLoader 用 shared memory，必須是 tmpfs
- `maxUnavailable: 0`：GPU Pod 很貴，不要讓任何 Pod 閒置
- init container 加了 `if [ ! -f ... ]` 判斷：如果 model 已經在 cache 就跳過下載（加速重啟）
