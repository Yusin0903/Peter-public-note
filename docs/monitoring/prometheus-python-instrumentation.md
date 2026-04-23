---
sidebar_position: 8
---

# Python 推論服務 Prometheus 埋點完全指南

> 從零開始，把你的 FastAPI 推論服務接上 Prometheus，讓 p99 延遲、錯誤率、模型狀態一覽無遺。

---

## 安裝

```bash
pip install prometheus-client
```

如果使用 FastAPI：

```bash
pip install prometheus-client fastapi uvicorn
```

---

## 四種 Metric 類型速查

選錯 metric 類型是初學者最常犯的錯誤。以下是推論系統的選型原則：

| 類型 | 值的行為 | 推論系統典型用途 |
|------|----------|-----------------|
| **Counter** | 只能遞增，重啟歸零 | 請求總數、錯誤總數、Token 消耗量 |
| **Gauge** | 可任意設定（上下均可） | 已載入模型數、GPU 記憶體用量、Queue 長度 |
| **Histogram** | 將值分配到 bucket，計算分佈 | 推論延遲（最重要）、輸入 token 長度 |
| **Summary** | 客戶端計算 quantile | 幾乎不用，以 Histogram 取代 |

---

## Counter：請求計數

Counter 的語意是「某件事發生了幾次」。它只能遞增，服務重啟後歸零（Prometheus 會用 `rate()` 抵消這個影響）。

```python
from prometheus_client import Counter

# 推論請求計數，按 model_name 和 status 拆分
inference_requests_total = Counter(
    "inference_requests_total",          # metric 名稱，必須以 _total 結尾
    "Total number of inference requests",  # 說明（顯示在 Grafana tooltip）
    ["model_name", "status"]              # label 名稱
)

# 使用方式
def handle_request(model_name: str, input_data):
    try:
        result = model.predict(input_data)
        inference_requests_total.labels(
            model_name=model_name,
            status="success"
        ).inc()   # 每次 +1
        return result
    except Exception as e:
        inference_requests_total.labels(
            model_name=model_name,
            status="error"
        ).inc()
        raise
```

**PromQL 查詢：**

```promql
# 每秒推論請求數（過去 5 分鐘滑動平均）
rate(inference_requests_total{status="success"}[5m])

# 過去 1 小時推論失敗總數
increase(inference_requests_total{status="error"}[1h])

# 錯誤率（百分比）
(
  rate(inference_requests_total{status="error"}[5m])
  /
  rate(inference_requests_total[5m])
) * 100
```

```python
# Python 心智模型：Counter 就像一個只能 += 的 int
total_requests = 0
total_requests += 1   # 每次請求，永遠不會 -1
```

---

## Gauge：模型狀態

Gauge 表示「某個值現在是多少」，可以任意設定，適合表示當前狀態。

```python
from prometheus_client import Gauge
import psutil
import torch

# 模型是否已載入（0 = 未載入，1 = 已載入）
model_loaded = Gauge(
    "model_loaded",
    "Whether the model is currently loaded into memory",
    ["model_name"]
)

# 目前載入的模型數量
models_loaded_count = Gauge(
    "models_loaded_count",
    "Number of models currently loaded"
)

# GPU 記憶體使用量（bytes）
gpu_memory_used_bytes = Gauge(
    "gpu_memory_used_bytes",
    "GPU memory currently allocated",
    ["gpu_id"]
)

# Inference queue 長度
inference_queue_length = Gauge(
    "inference_queue_length",
    "Number of requests waiting in the inference queue"
)


class ModelManager:
    def __init__(self):
        self.models = {}

    def load_model(self, model_name: str):
        self.models[model_name] = load_from_disk(model_name)
        model_loaded.labels(model_name=model_name).set(1)   # 載入 → 1
        models_loaded_count.inc()

    def unload_model(self, model_name: str):
        del self.models[model_name]
        model_loaded.labels(model_name=model_name).set(0)   # 卸載 → 0
        models_loaded_count.dec()

    def update_gpu_metrics(self):
        if torch.cuda.is_available():
            for i in range(torch.cuda.device_count()):
                used = torch.cuda.memory_allocated(i)
                gpu_memory_used_bytes.labels(gpu_id=str(i)).set(used)
```

**set_function：讓 Prometheus scrape 時自動取值**

```python
# 更優雅：不需要手動呼叫 update，Prometheus 每次 scrape 時自動執行
gpu_memory_used_bytes.labels(gpu_id="0").set_function(
    lambda: torch.cuda.memory_allocated(0) if torch.cuda.is_available() else 0
)

inference_queue_length.set_function(
    lambda: request_queue.qsize()
)
```

**PromQL 查詢：**

```promql
# 哪些模型沒有載入？
model_loaded == 0

# 當前 GPU 記憶體使用率（假設 GPU 總記憶體 24GB）
gpu_memory_used_bytes / (24 * 1024 * 1024 * 1024) * 100

# 過去 10 分鐘平均 queue 長度
avg_over_time(inference_queue_length[10m])
```

---

## Histogram：推論延遲（最重要）

Histogram 是推論系統最核心的 metric。平均延遲（mean）不夠，你需要 **p99**——因為 1% 的慢請求可能就是你的問題用戶。

```python
from prometheus_client import Histogram
import time

# 推論延遲 histogram
# buckets 單位是秒，根據你的 SLA 設定
inference_duration_seconds = Histogram(
    "inference_duration_seconds",
    "End-to-end inference request duration in seconds",
    ["model_name"],
    # 覆蓋 5ms 到 10s 的範圍（依你的 SLA 調整）
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
)

# 方法一：手動計時
def run_inference(model_name: str, input_data):
    start = time.time()
    result = model.predict(input_data)
    duration = time.time() - start
    inference_duration_seconds.labels(model_name=model_name).observe(duration)
    return result

# 方法二：context manager（推薦，更簡潔）
def run_inference_v2(model_name: str, input_data):
    with inference_duration_seconds.labels(model_name=model_name).time():
        return model.predict(input_data)

# 方法三：decorator（適合整個函式都需要計時）
@inference_duration_seconds.labels(model_name="resnet50").time()
def run_resnet50(input_data):
    return resnet50.predict(input_data)
```

**Prometheus 自動產生的 series：**

每個 Histogram 會自動展開成多個 time series：

```
# 每個 bucket 的累積計數（有多少請求 <= 這個 bucket 值）
inference_duration_seconds_bucket{le="0.005",model_name="resnet50"}  2.0
inference_duration_seconds_bucket{le="0.01",model_name="resnet50"}   8.0
inference_duration_seconds_bucket{le="0.025",model_name="resnet50"}  35.0
inference_duration_seconds_bucket{le="0.05",model_name="resnet50"}   72.0
inference_duration_seconds_bucket{le="0.1",model_name="resnet50"}    95.0
inference_duration_seconds_bucket{le="+Inf",model_name="resnet50"}  100.0

# 總請求數和總耗時（用來計算平均值）
inference_duration_seconds_count{model_name="resnet50"}  100.0
inference_duration_seconds_sum{model_name="resnet50"}    7.23
```

**PromQL 查詢：**

```promql
# p99 推論延遲（最重要的 SLA 指標）
histogram_quantile(0.99,
  rate(inference_duration_seconds_bucket{model_name="resnet50"}[5m])
)

# p50（中位數）和 p95
histogram_quantile(0.50, rate(inference_duration_seconds_bucket[5m]))
histogram_quantile(0.95, rate(inference_duration_seconds_bucket[5m]))

# 平均推論時間（比 p99 樂觀，但有時需要）
rate(inference_duration_seconds_sum[5m])
/ rate(inference_duration_seconds_count[5m])

# 跨所有 model 的整體 p99
histogram_quantile(0.99,
  sum(rate(inference_duration_seconds_bucket[5m])) by (le)
)
```

**選擇合適的 bucket 邊界：**

```python
# 通用推論服務（10ms – 5s）
buckets = [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]

# 高頻輕量推論（1ms – 500ms）
buckets = [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5]

# 大模型推論（100ms – 60s）
buckets = [0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, 30.0, 60.0]

# 原則：
# 1. bucket 數量 8–16 個（太少估算不準，太多浪費 time series）
# 2. 確保你的 SLA 目標值（如 500ms）在某個 bucket 附近
# 3. 最小 bucket 大約是最小可能延遲，最大 bucket 是超時閾值
```

---

## FastAPI Middleware：自動埋點所有路由

與其在每個 endpoint 手動呼叫 `.inc()` 和 `.observe()`，不如用 middleware 一次搞定。

```python
import time
from fastapi import FastAPI, Request, Response
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

app = FastAPI()

# ── Metrics 定義 ──────────────────────────────────────────────

REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status_code"]
)

REQUEST_DURATION = Histogram(
    "http_request_duration_seconds",
    "HTTP request duration",
    ["method", "endpoint"],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5]
)

# 推論專用 metrics
INFERENCE_REQUESTS = Counter(
    "inference_requests_total",
    "Total inference requests",
    ["model_name", "status"]
)

INFERENCE_DURATION = Histogram(
    "inference_duration_seconds",
    "Inference duration",
    ["model_name"],
    buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]
)


# ── Middleware：自動計時所有路由 ──────────────────────────────

@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    """
    這個 middleware 對所有路由自動埋點 request count 和 duration。

    Python 心智模型：就像一個 decorator，包住所有 endpoint 函式：
        @timer_decorator
        async def any_endpoint(...):
            ...
    """
    # 排除 /metrics 本身，避免自我監控造成雜訊
    if request.url.path == "/metrics":
        return await call_next(request)

    start_time = time.time()
    response = await call_next(request)
    duration = time.time() - start_time

    # 正規化 endpoint path（避免 /predict/123 和 /predict/456 產生不同 label）
    # ❌ 錯誤：用原始 path 當 label → cardinality explosion
    # endpoint = request.url.path

    # ✅ 正確：用路由樣板
    route = request.scope.get("route")
    endpoint = route.path if route else request.url.path

    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=endpoint,
        status_code=str(response.status_code)
    ).inc()

    REQUEST_DURATION.labels(
        method=request.method,
        endpoint=endpoint
    ).observe(duration)

    return response


# ── Endpoints ────────────────────────────────────────────────

@app.post("/predict/{model_name}")
async def predict(model_name: str, body: dict):
    """推論 endpoint，middleware 會自動計時。"""
    with INFERENCE_DURATION.labels(model_name=model_name).time():
        try:
            result = await run_model(model_name, body)
            INFERENCE_REQUESTS.labels(model_name=model_name, status="success").inc()
            return result
        except Exception as e:
            INFERENCE_REQUESTS.labels(model_name=model_name, status="error").inc()
            raise


@app.get("/metrics")
async def metrics():
    """Prometheus 每 15 秒來這裡 scrape 一次。"""
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST
    )
```

---

## 完整推論服務埋點範例

把上面所有概念整合成一個可以直接跑的完整範例：

```python
# inference_service.py
import time
import asyncio
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, Request, Response, HTTPException
from prometheus_client import (
    Counter, Gauge, Histogram,
    generate_latest, CONTENT_TYPE_LATEST
)

# ── Metrics 定義（放在 module 頂層，只初始化一次）────────────

# 1. 推論請求計數
inference_requests_total = Counter(
    "inference_requests_total",
    "Total inference requests",
    ["model_name", "status"]   # status: success | error | timeout
)

# 2. 推論延遲分佈
inference_duration_seconds = Histogram(
    "inference_duration_seconds",
    "Inference request duration in seconds",
    ["model_name"],
    buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
)

# 3. 模型載入狀態
model_loaded = Gauge(
    "model_loaded",
    "1 if model is loaded and ready, 0 otherwise",
    ["model_name"]
)

# 4. 目前處理中的請求數（用來偵測過載）
inference_in_flight = Gauge(
    "inference_in_flight_requests",
    "Number of inference requests currently being processed",
    ["model_name"]
)

# 5. 輸入 token 長度分佈（NLP 模型適用）
input_token_length = Histogram(
    "inference_input_token_length",
    "Distribution of input token lengths",
    ["model_name"],
    buckets=[32, 64, 128, 256, 512, 1024, 2048, 4096]
)


# ── 模型管理 ─────────────────────────────────────────────────

class ModelRegistry:
    """管理多個模型的載入/卸載，並同步更新 Gauge。"""

    def __init__(self):
        self._models = {}

    async def load(self, model_name: str):
        model_loaded.labels(model_name=model_name).set(0)   # 載入中
        try:
            # 模擬載入耗時
            await asyncio.sleep(0.1)
            self._models[model_name] = f"<{model_name} weights>"
            model_loaded.labels(model_name=model_name).set(1)  # 載入完成
        except Exception:
            model_loaded.labels(model_name=model_name).set(0)
            raise

    def get(self, model_name: str):
        if model_name not in self._models:
            raise KeyError(f"Model {model_name} not loaded")
        return self._models[model_name]

    async def predict(self, model_name: str, input_data: dict) -> dict:
        model = self.get(model_name)

        # 追蹤 in-flight 請求（Gauge 用 track_inprogress context manager）
        with inference_in_flight.labels(model_name=model_name).track_inprogress():
            with inference_duration_seconds.labels(model_name=model_name).time():
                # 模擬推論
                await asyncio.sleep(0.05)
                return {"result": "predicted", "model": model_name}


registry = ModelRegistry()


# ── Lifespan：服務啟動時載入模型 ─────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    # 啟動時載入模型
    await registry.load("resnet50")
    await registry.load("bert-base")
    yield
    # 關閉時可以做清理


app = FastAPI(lifespan=lifespan)


# ── Middleware ───────────────────────────────────────────────

@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    if request.url.path == "/metrics":
        return await call_next(request)
    return await call_next(request)


# ── Endpoints ────────────────────────────────────────────────

@app.post("/predict/{model_name}")
async def predict(model_name: str, body: dict):
    try:
        result = await registry.predict(model_name, body)
        inference_requests_total.labels(
            model_name=model_name, status="success"
        ).inc()
        return result
    except KeyError:
        raise HTTPException(status_code=404, detail=f"Model {model_name} not found")
    except asyncio.TimeoutError:
        inference_requests_total.labels(
            model_name=model_name, status="timeout"
        ).inc()
        raise HTTPException(status_code=504, detail="Inference timeout")
    except Exception as e:
        inference_requests_total.labels(
            model_name=model_name, status="error"
        ).inc()
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/metrics")
async def metrics():
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST
    )


@app.get("/health")
async def health():
    return {"status": "ok"}
```

---

## Pushgateway：Batch Job / CronJob 的推送方案

Prometheus 是 **pull 模式**：它主動去 `/metrics` 拉資料。但如果你的推論任務是 **批次處理**（例如 K8s CronJob、離線評估腳本），任務跑完就消失，Prometheus 來不及 scrape，這時需要 Pushgateway。

```
批次推論 Job
    ↓ 跑完後主動 push metrics
Pushgateway（長期存活，等待 Prometheus 來 scrape）
    ↓ Prometheus 定期 scrape
Prometheus TSDB
```

```python
# batch_inference.py
import time
from prometheus_client import (
    CollectorRegistry, Counter, Histogram,
    push_to_gateway
)

def run_batch_inference(dataset_path: str, model_name: str):
    # 每個 batch job 使用獨立的 registry，避免污染全域 registry
    registry = CollectorRegistry()

    batch_processed = Counter(
        "batch_inference_processed_total",
        "Total items processed in this batch run",
        ["model_name", "status"],
        registry=registry
    )

    batch_duration = Histogram(
        "batch_inference_item_duration_seconds",
        "Duration per item in batch inference",
        ["model_name"],
        buckets=[0.01, 0.05, 0.1, 0.5, 1.0, 5.0],
        registry=registry
    )

    # 執行批次推論
    dataset = load_dataset(dataset_path)
    for item in dataset:
        start = time.time()
        try:
            result = model.predict(item)
            batch_processed.labels(model_name=model_name, status="success").inc()
        except Exception:
            batch_processed.labels(model_name=model_name, status="error").inc()
        finally:
            batch_duration.labels(model_name=model_name).observe(time.time() - start)

    # 批次跑完後，把 metrics push 到 Pushgateway
    # job 名稱用來在 Pushgateway 識別這個 batch run
    push_to_gateway(
        "pushgateway:9091",           # Pushgateway 的地址
        job=f"batch_inference_{model_name}",
        registry=registry
    )
    print(f"Metrics pushed to Pushgateway for job: batch_inference_{model_name}")


if __name__ == "__main__":
    run_batch_inference("s3://my-bucket/dataset.jsonl", "resnet50")
```

**docker-compose 加入 Pushgateway：**

```yaml
pushgateway:
  image: prom/pushgateway:latest
  container_name: pushgateway
  ports:
    - "9091:9091"
  networks:
    - monitoring
  restart: unless-stopped
```

**prometheus.yml 加入 Pushgateway scrape：**

```yaml
scrape_configs:
  - job_name: "pushgateway"
    honor_labels: true   # 保留 batch job 原本的 label，不被 Prometheus 覆蓋
    static_configs:
      - targets: ["pushgateway:9091"]
```

**什麼時候用 Pushgateway：**

| 場景 | 推薦方案 |
|------|----------|
| 長期存活的 FastAPI 服務 | `/metrics` endpoint（pull 模式） |
| K8s CronJob / 定時批次推論 | Pushgateway（push 模式） |
| AWS Lambda / 短暫的 serverless 函式 | Pushgateway |
| 離線評估腳本（跑完就結束） | Pushgateway |

---

## 常見陷阱

### 陷阱一：Label Cardinality Explosion（最危險）

把高基數的值放進 label，會讓 time series 數量爆炸，Prometheus 記憶體暴增、費用暴漲。

```python
from prometheus_client import Counter

# ❌ 致命錯誤：request_id 有無限多個值
requests = Counter("inference_requests_total", "Requests", ["request_id"])
requests.labels(request_id="req-a3f92b1c-...").inc()   # 每次 UUID 都不同
# 結果：幾天後 Prometheus OOM（記憶體耗盡）

# ❌ 也很危險：user_id、session_id、ip_address
requests = Counter("requests_total", "Requests", ["user_id"])

# ✅ 正確：只用低基數的 label（通常 < 100 種值）
requests = Counter(
    "inference_requests_total",
    "Requests",
    ["model_name", "status", "endpoint"]
    # model_name：幾十種模型
    # status：success / error / timeout（3 種）
    # endpoint：/predict / /batch（幾種）
)
```

**檢查目前 cardinality：**

```promql
# 找出 time series 最多的 metric（前 10 名）
topk(10, count by (__name__)({__name__=~".+"}))
```

---

### 陷阱二：Counter 沒加 `_total` 後綴

Prometheus 規範要求 Counter 必須以 `_total` 結尾。新版 `prometheus_client`（>= 0.5）會自動加，但你在查 PromQL 時需要知道這一點。

```python
# 定義時
requests = Counter("inference_requests", "...", ["model_name"])
# 實際 metric 名稱是 inference_requests_total

# PromQL 查詢時要用 _total
rate(inference_requests_total[5m])   # ✅
rate(inference_requests[5m])         # ❌ 找不到
```

---

### 陷阱三：Histogram bucket 設定不合理

```python
# ❌ 只用預設 bucket（.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10）
# 如果你的推論幾乎都在 5–50ms，大部分值都落在同一個 bucket，p99 估算很不準
duration = Histogram("inference_duration_seconds", "...")

# ✅ 根據你服務的實際延遲範圍設定 bucket
duration = Histogram(
    "inference_duration_seconds",
    "...",
    ["model_name"],
    buckets=[0.005, 0.01, 0.02, 0.03, 0.05, 0.075, 0.1, 0.15, 0.2, 0.3, 0.5]
    # 密集分佈在 5–100ms 區間，這是你最需要精確估算 p99 的地方
)
```

---

### 陷阱四：在 request handler 外初始化 metric 物件

```python
# ❌ 每次請求都重新建立 Histogram — 會報錯或浪費資源
@app.post("/predict/{model_name}")
async def predict(model_name: str, body: dict):
    duration = Histogram("inference_duration_seconds", "...")  # 每次都 new 一個！
    with duration.time():
        return model.predict(body)

# ✅ 在 module 頂層定義，只初始化一次
inference_duration_seconds = Histogram(
    "inference_duration_seconds",
    "Inference duration",
    ["model_name"],
    buckets=[...]
)

@app.post("/predict/{model_name}")
async def predict(model_name: str, body: dict):
    with inference_duration_seconds.labels(model_name=model_name).time():
        return model.predict(body)
```

---

### 陷阱五：忘記加 `/metrics` endpoint

```python
# ❌ 裝了 prometheus_client，但沒有暴露 endpoint
# Prometheus scrape 會失敗，你什麼都看不到

# ✅ 必須加這個 endpoint
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST
from fastapi import Response

@app.get("/metrics")
async def metrics():
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST
    )
```

---

## 推薦的 Metric 命名規範

```python
# 格式：<namespace>_<subsystem>_<name>_<unit>
# 範例：
inference_requests_total              # Counter：請求總數
inference_duration_seconds            # Histogram：延遲（秒）
inference_in_flight_requests          # Gauge：進行中的請求數
model_loaded                          # Gauge：模型狀態（0/1）
gpu_memory_used_bytes                 # Gauge：GPU 記憶體（bytes）
batch_items_processed_total           # Counter：批次處理項目數

# 單位規範：
# - 時間：用 _seconds（不是 _ms 或 _milliseconds）
# - 大小：用 _bytes（不是 _mb）
# - 百分比：用 _ratio（0.0–1.0，不是 0–100）
# - Counter：以 _total 結尾
```

---

## 快速驗證 Checklist

埋點完成後，用這個清單確認一切正常：

```bash
# 1. 確認 /metrics endpoint 有輸出
curl http://localhost:8000/metrics | head -50

# 2. 確認 metric 名稱正確（注意 Counter 的 _total 後綴）
curl http://localhost:8000/metrics | grep inference_requests_total

# 3. 發送幾次測試請求後，確認數值有變化
curl -X POST http://localhost:8000/predict/resnet50 \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}'
curl http://localhost:8000/metrics | grep inference_requests_total
# inference_requests_total{model_name="resnet50",status="success"} 1.0

# 4. 在 Prometheus UI 確認 target 是 UP
# http://localhost:9090/targets

# 5. 執行 PromQL 確認資料可以查詢
# http://localhost:9090/graph
# 查詢：rate(inference_requests_total[5m])
```
