---
sidebar_position: 6
---

# Prometheus + Grafana 本地監控 Docker Compose

完整的本地監控 stack，包含 cAdvisor、node-exporter、process-exporter 和 NVIDIA GPU exporter。

---

## 快速上手：含 Python 推論服務的完整 Stack

這個 stack 包含：Prometheus + Grafana + node-exporter + 一個帶有自訂 metrics 的 Python FastAPI 推論服務。

### 目錄結構

```
monitoring/
├── docker-compose.yml
├── prometheus/
│   ├── prometheus.yml
│   └── rules/
│       └── inference_rules.yml
├── grafana/
│   └── grafana_data/          # 自動建立
└── inference-app/
    ├── Dockerfile
    ├── requirements.txt
    └── main.py
```

### inference-app/requirements.txt

```
fastapi==0.111.0
uvicorn==0.30.0
prometheus-client==0.20.0
```

### inference-app/main.py

完整的 FastAPI 推論服務，示範 Counter + Histogram 埋點：

```python
import time
import random
from fastapi import FastAPI, Request, Response
from prometheus_client import (
    Counter, Histogram, Gauge,
    generate_latest, CONTENT_TYPE_LATEST
)

app = FastAPI()

# ── Metrics 定義 ──────────────────────────────────────────────

# Counter：推論請求總數（按 model + status 分維度）
inference_requests_total = Counter(
    "inference_requests_total",
    "Total number of inference requests",
    ["model_name", "status"]   # status: success | error
)

# Histogram：推論延遲分佈（p50 / p99 都可以查）
inference_duration_seconds = Histogram(
    "inference_duration_seconds",
    "Time spent running inference",
    ["model_name"],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]
)

# Gauge：模型是否已載入（0 = 未載入，1 = 已載入）
model_loaded = Gauge(
    "model_loaded",
    "Whether the model is currently loaded into memory",
    ["model_name"]
)

# 模擬兩個模型已載入
model_loaded.labels(model_name="resnet50").set(1)
model_loaded.labels(model_name="bert-base").set(1)


# ── FastAPI Middleware：自動計算所有路由延遲 ─────────────────

@app.middleware("http")
async def prometheus_middleware(request: Request, call_next):
    """
    這個 middleware 讓所有路由自動被計時。
    等效概念：Python 的 decorator，在函式前後插入計時邏輯。
    """
    start_time = time.time()
    response = await call_next(request)
    duration = time.time() - start_time

    # 只記錄 /predict 開頭的路由
    if request.url.path.startswith("/predict"):
        model_name = request.url.path.split("/")[-1]
        status = "success" if response.status_code < 400 else "error"
        inference_requests_total.labels(
            model_name=model_name,
            status=status
        ).inc()
        inference_duration_seconds.labels(
            model_name=model_name
        ).observe(duration)

    return response


# ── 推論 Endpoints ───────────────────────────────────────────

@app.post("/predict/{model_name}")
async def predict(model_name: str, body: dict):
    """
    模擬推論：隨機 10% 機率失敗，延遲 10–300ms。
    """
    if model_name not in ["resnet50", "bert-base"]:
        return Response(status_code=404, content="Model not found")

    # 模擬推論耗時
    latency = random.uniform(0.01, 0.3)
    time.sleep(latency)

    # 模擬 10% 錯誤率
    if random.random() < 0.1:
        inference_requests_total.labels(
            model_name=model_name, status="error"
        ).inc()
        return Response(status_code=500, content="Inference failed")

    return {"model": model_name, "result": "cat", "latency_ms": latency * 1000}


# ── /metrics Endpoint（Prometheus 來這裡 scrape）────────────

@app.get("/metrics")
async def metrics():
    """
    暴露 Prometheus metrics。
    Prometheus 每 15 秒來這裡拉一次資料。
    """
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST
    )


@app.get("/health")
async def health():
    return {"status": "ok"}
```

### inference-app/Dockerfile

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

---

### prometheus/prometheus.yml

```yaml
global:
  scrape_interval: 15s       # 每 15 秒 scrape 一次
  evaluation_interval: 15s   # 每 15 秒評估一次 alert rules

# 載入 recording rules 和 alert rules
rule_files:
  - "rules/*.yml"

scrape_configs:
  # Prometheus 自己的 metrics
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  # 我們的推論服務
  - job_name: "inference-service"
    scrape_interval: 15s
    static_configs:
      - targets: ["inference-app:8000"]
    # 讓 Grafana 可以看到這個 job 的 metrics
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance

  # 機器層級 metrics
  - job_name: "node-exporter"
    static_configs:
      - targets: ["node-exporter:9100"]

  # Container 層級 metrics
  - job_name: "cadvisor"
    static_configs:
      - targets: ["cadvisor:8080"]
```

### prometheus/rules/inference_rules.yml

```yaml
groups:
  - name: inference_recording_rules
    interval: 1m
    rules:
      # 預計算 p99 延遲，Grafana dashboard 直接讀這個
      - record: job:inference_duration_seconds:p99
        expr: |
          histogram_quantile(0.99,
            sum(rate(inference_duration_seconds_bucket[5m])) by (le, model_name)
          )

      # 預計算每秒請求數
      - record: job:inference_requests:rate5m
        expr: |
          sum(rate(inference_requests_total[5m])) by (model_name, status)

  - name: inference_alerts
    rules:
      - alert: HighInferenceLatency
        expr: job:inference_duration_seconds:p99 > 0.5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "推論 p99 延遲超過 500ms (model={{ $labels.model_name }})"

      - alert: ModelNotLoaded
        expr: model_loaded == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "模型未載入 ({{ $labels.model_name }})"
```

---

### docker-compose.yml（推論服務完整版）

```yaml
version: '3.8'

services:
  # ── 推論服務（含自訂 metrics）──────────────────────────
  inference-app:
    build: ./inference-app
    container_name: inference-app
    ports:
      - "8000:8000"
    networks:
      - monitoring
    restart: unless-stopped

  # ── Prometheus ─────────────────────────────────────────
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    volumes:
      - "./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro"
      - "./prometheus/rules:/etc/prometheus/rules:ro"
      - "prometheus_data:/prometheus/data"
    ports:
      - "9090:9090"
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus/data"
      - "--storage.tsdb.retention.time=15d"
      - "--web.enable-lifecycle"   # 允許 POST /-/reload 熱重載設定
    networks:
      - monitoring
    depends_on:
      - inference-app
    restart: unless-stopped

  # ── Grafana ────────────────────────────────────────────
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin123   # 記得換成安全的密碼
      - GF_USERS_ALLOW_SIGN_UP=false
    ports:
      - "3001:3000"
    networks:
      - monitoring
    volumes:
      - grafana_data:/var/lib/grafana
    depends_on:
      - prometheus
    restart: unless-stopped

  # ── node-exporter（機器層級 metrics）──────────────────
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.ignored-mount-points'
      - '^/(sys|proc|dev|host|etc)($|/)'
    networks:
      - monitoring
    restart: unless-stopped

  # ── cAdvisor（container 層級 metrics）─────────────────
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.49.1
    container_name: cadvisor
    volumes:
      - "/:/rootfs:ro"
      - "/var/run:/var/run:ro"
      - "/sys:/sys:ro"
      - "/var/lib/docker:/var/lib/docker:ro"
    ports:
      - "8081:8080"
    networks:
      - monitoring
    restart: unless-stopped

networks:
  monitoring:
    driver: bridge

volumes:
  prometheus_data:
  grafana_data:
```

---

## 啟動與驗證

### 啟動 Stack

```bash
# 建立目錄結構
mkdir -p prometheus/rules grafana/grafana_data inference-app

# 啟動所有服務
docker compose up -d

# 查看啟動狀態
docker compose ps
```

### 驗證推論服務的 /metrics

```bash
# 直接查看 /metrics endpoint 輸出
curl http://localhost:8000/metrics

# 預期輸出（節錄）：
# HELP inference_requests_total Total number of inference requests
# TYPE inference_requests_total counter
# inference_requests_total{model_name="resnet50",status="success"} 0.0
#
# HELP inference_duration_seconds Time spent running inference
# TYPE inference_duration_seconds histogram
# inference_duration_seconds_bucket{le="0.005",model_name="resnet50"} 0.0
# inference_duration_seconds_bucket{le="0.01",model_name="resnet50"} 0.0
# ...
# inference_duration_seconds_count{model_name="resnet50"} 0.0
# inference_duration_seconds_sum{model_name="resnet50"} 0.0
#
# HELP model_loaded Whether the model is currently loaded into memory
# TYPE model_loaded gauge
# model_loaded{model_name="bert-base"} 1.0
# model_loaded{model_name="resnet50"} 1.0
```

### 製造一些推論流量並驗證

```bash
# 發送 10 次推論請求
for i in $(seq 1 10); do
  curl -s -X POST http://localhost:8000/predict/resnet50 \
    -H "Content-Type: application/json" \
    -d '{"image": "base64_encoded_data"}' | python3 -m json.tool
done

# 再次查看 metrics，應該看到數值變化
curl http://localhost:8000/metrics | grep inference_requests_total
# inference_requests_total{model_name="resnet50",status="success"} 9.0
# inference_requests_total{model_name="resnet50",status="error"} 1.0
```

### 在 Prometheus UI 驗證

```bash
# 打開瀏覽器：http://localhost:9090

# 在 Targets 頁面確認所有 target 都是 UP 狀態
# http://localhost:9090/targets

# 在 Graph 頁面執行 PromQL：
# p99 推論延遲
histogram_quantile(0.99, rate(inference_duration_seconds_bucket[5m]))

# 每秒推論請求數
rate(inference_requests_total[5m])

# 模型載入狀態
model_loaded
```

### 設定 Grafana

```bash
# 打開瀏覽器：http://localhost:3001
# 帳號：admin，密碼：admin123

# 1. 新增 Prometheus data source：
#    Configuration → Data Sources → Add data source → Prometheus
#    URL: http://prometheus:9090

# 2. 建立 Dashboard，加入以下 panels：
#    Panel 1（Stat）：model_loaded
#    Panel 2（Time series）：rate(inference_requests_total[5m])
#    Panel 3（Time series）：histogram_quantile(0.99, rate(inference_duration_seconds_bucket[5m]))
```

### 熱重載 Prometheus 設定

```bash
# 修改 prometheus.yml 或 rules 後，不需重啟就能套用：
curl -X POST http://localhost:9090/-/reload
```

---

## 完整 Stack（含 GPU exporter）

原始的 GPU 監控版本，適合有 NVIDIA GPU 的機器：

```yaml
version: '3.8'

services:
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.49.1
    container_name: cadvisor
    volumes:
      - "/:/rootfs:ro"
      - "/var/run:/var/run:ro"
      - "/sys:/sys:ro"
      - "/var/lib/docker:/var/lib/docker:ro"
      - "/dev/disk:/dev/disk:ro"
    ports:
      - "8081:8080"
    networks:
      - monitoring
    command:
      - "--port=8080"
    restart: unless-stopped

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    volumes:
      - "./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro"
      - "./prometheus/prometheus_data:/prometheus/data"
    ports:
      - "9090:9090"
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus/data"
    networks:
      - monitoring
    depends_on:
      - cadvisor
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=your_password_here  # 記得改掉
    ports:
      - "3001:3000"
    networks:
      - monitoring
    volumes:
      - ./grafana/grafana_data:/var/lib/grafana
    depends_on:
      - prometheus
    restart: unless-stopped

  process-exporter:
    image: ncabatoff/process-exporter
    container_name: process-exporter
    ports:
      - "9256:9256"
    volumes:
      - ./process_exporter/config/process-exporter.yml:/config/process-exporter.yml
      - /proc:/host/proc:ro
      - /:/hostfs:ro
    command:
      - "--config.path=/config/process-exporter.yml"
    networks:
      - monitoring
    pid: "host"
    restart: always

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.ignored-mount-points'
      - '^/(sys|proc|dev|host|etc)($|/)'
    networks:
      - monitoring
    restart: unless-stopped

  nvidia_smi_exporter:
    container_name: nvidia_smi_exporter
    image: utkuozdemir/nvidia_gpu_exporter:1.1.0
    restart: unless-stopped
    devices:
      - /dev/nvidiactl:/dev/nvidiactl
      - /dev/nvidia0:/dev/nvidia0
    volumes:
      - /usr/lib/x86_64-linux-gnu/libnvidia-ml.so:/usr/lib/x86_64-linux-gnu/libnvidia-ml.so
      - /usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1:/usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1
      - /usr/bin/nvidia-smi:/usr/bin/nvidia-smi
    ports:
      - "9835:9835"

networks:
  monitoring:

volumes:
  prometheus_data:
  grafana_data:
```

---

## 各 Exporter 說明

| Exporter | Port | 用途 |
|----------|------|------|
| inference-app | 8000 | 推論服務自訂 metrics |
| cAdvisor | 8081 | Container 層級資源使用（CPU/Memory per container） |
| Prometheus | 9090 | Metrics 收集與查詢 |
| Grafana | 3001 | Dashboard 視覺化 |
| node-exporter | 9100 | 機器層級 metrics（CPU/RAM/Disk/Network） |
| process-exporter | 9256 | Process 層級 metrics |
| nvidia_smi_exporter | 9835 | NVIDIA GPU metrics |
