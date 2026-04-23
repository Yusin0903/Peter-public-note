---
sidebar_position: 1
---

# Prometheus & Monitoring 名詞教學

> 跟 SRE 溝通時會用到的術語整理，含費用計算相關的定義。

---

## 核心概念

### Metric（指標）

一個被監控的測量值，例如 `cpu_usage`、`http_requests_total`。

每個 metric 可以有多個 **label**（標籤）來區分不同維度：

```
http_requests_total{method="GET", status="200", pod="app-abc123"}
http_requests_total{method="POST", status="500", pod="app-abc123"}
```

上面雖然是同一個 metric name，但因為 label 不同，算作 **2 個 time series**。

```python
# Python 類比：就像 dataclass 的 field
from prometheus_client import Counter

http_requests = Counter(
    "http_requests_total",
    "Total HTTP requests",
    labelnames=["method", "status", "pod"]  # 這些就是 labels
)
# 每種 label 組合 = 一條獨立的 time series
http_requests.labels(method="GET", status="200", pod="app-a").inc()
http_requests.labels(method="POST", status="500", pod="app-a").inc()
```

---

### Time Series（時間序列）

一個 metric name + 一組固定的 label key-value 組合 = 一個 time series。

```
container_cpu_usage{pod="app-a", namespace="prod"}    → 1 個 time series
container_cpu_usage{pod="app-b", namespace="prod"}    → 另 1 個 time series
container_cpu_usage{pod="app-c", namespace="staging"} → 又另 1 個 time series
```

**為什麼重要：** AMP 的費用跟 time series 數量直接相關，series 越多 = 費用越高。

查看目前有多少 active series：
```promql
prometheus_tsdb_head_series
```

---

### Sample（樣本）

Prometheus 每次 scrape 一個 time series，就產生 **1 個 sample**。

```
一個 sample = 一個 timestamp + 一個 value

時間 10:00:00  cpu_usage{pod="app-a"} = 0.75    ← 1 個 sample
時間 10:00:30  cpu_usage{pod="app-a"} = 0.82    ← 又 1 個 sample
```

**為什麼重要：** AMP 按 sample 數量收費。

```python
# Python 類比：
# sample 就像 append 一筆資料到時間序列 list
time_series = []
time_series.append({"timestamp": 1700000000, "value": 0.75})  # 1 個 sample
time_series.append({"timestamp": 1700000030, "value": 0.82})  # 又 1 個 sample
```

---

### Active Time Series（活躍時間序列）

目前正在被 Prometheus scrape 的 time series 數量。Pod 被刪後，對應的 series 約 5 分鐘後變 stale（不活躍）。

```promql
# 查看目前 active series 數
prometheus_tsdb_head_series

# 查看過去 7 天平均值（更穩定的估算基準）
avg_over_time(prometheus_tsdb_head_series[7d])
```

---

### Cardinality（基數）

一個 metric 的 label 排列組合數量。高基數 = 很多條 time series = 吃記憶體和費用。

**Cardinality Explosion** = label 值太多（例如 user_id、request_id），導致 time series 數量爆炸。

```python
# ❌ 高基數的 label — 造成 cardinality explosion
from prometheus_client import Counter
requests = Counter("api_requests", "Requests", ["user_id"])  # user 有百萬個
requests.labels(user_id="user_123456").inc()  # 每個 user 一條 series，爆炸！

# ✅ 低基數的 label — 正確做法
requests = Counter("api_requests", "Requests", ["endpoint", "status"])
requests.labels(endpoint="/predict", status="200").inc()  # 組合數有限
```

---

## 四種 Metric 類型

Prometheus 有四種 metric 類型，選錯會導致 PromQL 算錯或無法查詢你想要的值。對推論系統開發者來說，選對類型等於選對了你的監控策略。

### Counter（計數器）

**只能遞增**，重啟後歸零。適合計算「發生了幾次」。

```python
from prometheus_client import Counter

# 推論系統範例：追蹤推論請求總數
inference_requests_total = Counter(
    "inference_requests_total",
    "Total number of inference requests",
    ["model_name", "status"]   # status: success / error
)

# 每次推論成功
inference_requests_total.labels(model_name="resnet50", status="success").inc()

# 每次推論失敗
inference_requests_total.labels(model_name="resnet50", status="error").inc()
```

**PromQL 用法：** Counter 本身是累積值，必須用 `rate()` 或 `increase()` 才能算每秒速率：

```promql
# 每秒推論請求數（過去 5 分鐘滑動平均）
rate(inference_requests_total{status="success"}[5m])

# 過去 1 小時推論失敗總數
increase(inference_requests_total{status="error"}[1h])
```

**命名規則：** Counter 的名稱必須以 `_total` 結尾（新版 prometheus_client 會自動加）。

```python
# Python 類比：Counter 就像一個只能 += 的 int
total = 0
total += 1  # 每次請求 +1，永遠不會 -1
```

---

### Gauge（儀表）

**可以任意設定值**（上升或下降）。適合表示「當前狀態」。

```python
from prometheus_client import Gauge

# 推論系統範例 1：當前載入的模型數量
models_loaded = Gauge(
    "models_loaded_count",
    "Number of models currently loaded in memory"
)
models_loaded.set(3)   # 目前載入 3 個模型
models_loaded.dec()    # 卸載一個 → 變 2

# 推論系統範例 2：模型是否已載入（0/1 布林值）
model_loaded = Gauge(
    "model_loaded",
    "Whether the model is currently loaded",
    ["model_name"]
)
model_loaded.labels(model_name="resnet50").set(1)   # 載入成功
model_loaded.labels(model_name="bert-base").set(0)  # 未載入

# 推論系統範例 3：GPU 記憶體使用量
gpu_memory_used_bytes = Gauge(
    "gpu_memory_used_bytes",
    "GPU memory currently in use",
    ["gpu_id"]
)

import subprocess
# 可用 set_function 讓 Prometheus 每次 scrape 時自動呼叫取值
gpu_memory_used_bytes.labels(gpu_id="0").set_function(
    lambda: get_gpu_memory_usage(gpu_id=0)
)
```

**PromQL 用法：** Gauge 可以直接查詢當前值，也可以用 `avg_over_time()` 計算時段平均：

```promql
# 目前有多少模型載入
models_loaded_count

# 過去 10 分鐘的平均 GPU 記憶體使用量
avg_over_time(gpu_memory_used_bytes{gpu_id="0"}[10m])
```

```python
# Python 類比：Gauge 就像一個可以自由賦值的變數
current_queue_size = 0
current_queue_size = 42   # 直接設定，可增可減
```

---

### Histogram（直方圖）

**將觀測值分配到多個 bucket**，自動計算 `_count`（總次數）、`_sum`（總和）和每個 bucket 的累積計數。適合測量「延遲分佈」。

**推論系統最重要的 metric 類型。** 原因：平均延遲 (p50) 無法反映真實使用者體驗，你需要的是 **p99 延遲**（99% 的請求在多少毫秒內完成）。

```python
from prometheus_client import Histogram

# 推論系統範例：推論延遲
# buckets 單位是秒，根據你的 SLA 設定合理邊界
inference_duration_seconds = Histogram(
    "inference_duration_seconds",
    "Time spent running inference",
    ["model_name"],
    # 針對推論服務設定 bucket：10ms 到 10s
    buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
)

import time

def run_inference(model_name: str, input_data):
    start = time.time()
    result = model.predict(input_data)
    duration = time.time() - start

    # 記錄這次推論花了多久
    inference_duration_seconds.labels(model_name=model_name).observe(duration)
    return result

# 更優雅的寫法：用 context manager 自動計時
with inference_duration_seconds.labels(model_name="resnet50").time():
    result = model.predict(input_data)
```

**Prometheus 自動產生的 series：**

```
# 每個 bucket 的累積計數（有多少請求 <= 這個值）
inference_duration_seconds_bucket{model_name="resnet50", le="0.1"}   42
inference_duration_seconds_bucket{model_name="resnet50", le="0.25"}  89
inference_duration_seconds_bucket{model_name="resnet50", le="+Inf"} 100

# 總次數和總和
inference_duration_seconds_count{model_name="resnet50"}  100
inference_duration_seconds_sum{model_name="resnet50"}    18.5
```

**PromQL 用法：**

```promql
# p99 推論延遲（核心 SLA 指標）
histogram_quantile(0.99,
  rate(inference_duration_seconds_bucket{model_name="resnet50"}[5m])
)

# p50（中位數）
histogram_quantile(0.50,
  rate(inference_duration_seconds_bucket[5m])
)

# 平均推論時間
rate(inference_duration_seconds_sum[5m])
/ rate(inference_duration_seconds_count[5m])
```

```python
# Python 類比：Histogram 就像把數值丟進 numpy.histogram
import numpy as np
latencies = [0.05, 0.12, 0.08, 0.25, 0.03, 1.2]
counts, bin_edges = np.histogram(latencies, bins=[0, 0.1, 0.25, 0.5, 1.0, float("inf")])
# Prometheus 幫你把這個過程自動化並持續累積
```

**選擇 bucket 的技巧：** bucket 太少會讓 `histogram_quantile` 估算不準；太多會增加 time series 數量。一般建議 8–16 個 bucket，覆蓋你 SLA 要求的延遲範圍的 10x。

---

### Summary（摘要）

和 Histogram 類似，但 **quantile 在客戶端計算**（推論服務內部），不在 Prometheus 查詢時計算。

```python
from prometheus_client import Summary

# 較少見，多數情況下 Histogram 更好
inference_summary = Summary(
    "inference_processing_seconds",
    "Summary of inference processing time",
    ["model_name"]
)

with inference_summary.labels(model_name="resnet50").time():
    result = model.predict(input_data)
```

**Histogram vs Summary 選哪個？**

| 特性 | Histogram | Summary |
|------|-----------|---------|
| Quantile 計算位置 | Prometheus 查詢時 | 客戶端（Python 程式） |
| 跨多個 instance 聚合 | ✅ 支援 `sum()` 多個 bucket | ❌ 無法跨 instance 聚合 |
| 自訂 quantile | 查詢時動態設定 | 定義時固定 |
| CPU 開銷 | 低（只記 bucket count） | 較高（滑動時間窗口計算） |
| 推薦場景 | 推論延遲、SLA 監控 | 極少見，通常用 Histogram |

**結論：推論系統幾乎永遠都應該用 Histogram，而不是 Summary。**

---

## 資料收集

### Scrape（抓取）

Prometheus 主動去 target 的 `/metrics` endpoint 拉資料的動作（pull 模式）。

```python
# Python 類比：就像定時呼叫你的 /metrics endpoint
import httpx
import schedule

def scrape():
    response = httpx.get("http://my-service:8080/metrics")
    # 解析 Prometheus 格式，寫入 TSDB

schedule.every(30).seconds.do(scrape)  # scrape_interval = 30s
```

---

### Scrape Interval（抓取間隔）

多久 scrape 一次。常見值：15s / 30s / 60s。間隔越短，資料越即時但費用越高。

| 間隔 | 每小時 scrape 次數 | 說明 |
|:---:|:---:|------|
| 15s | 240 次 | 很高頻，成本最高 |
| **30s** | **120 次** | **業界預設** |
| 60s | 60 次 | 成本減半，犧牲一點即時性 |

查詢目前設定：
```promql
prometheus_target_interval_length_seconds{quantile="0.99"}
```

---

### Exporter

把非 Prometheus 格式的 metrics 轉成 Prometheus 格式的中間層。

| Exporter | 收集什麼 |
|---|---|
| `node-exporter` | 機器層級 metrics（CPU/RAM/Disk） |
| `kube-state-metrics` | K8s 物件狀態（pod/deployment/node 數量） |
| `blackbox-exporter` | 外部端點的 probe（HTTP/TCP/DNS） |
| `dcgm-exporter` | NVIDIA GPU metrics |

```python
# Python 類比：就像你寫一個 /metrics endpoint 把自己的指標暴露給 Prometheus
from prometheus_client import make_wsgi_app, Gauge

inference_latency = Gauge("inference_latency_ms", "Inference latency in ms")

# 在你的 inference code 裡更新這個 gauge
inference_latency.set(response_time_ms)

# Prometheus 每 30 秒來抓一次這個 /metrics endpoint
```

---

## 資料儲存

### TSDB（Time Series Database）

專門為時間序列資料優化的資料庫。Prometheus 內建 TSDB 存在本地磁碟。

### WAL（Write-Ahead Log）

寫入前先寫 log 檔，確保 crash 後不丟資料。Prometheus 和 VictoriaMetrics 都用 WAL。

```python
# Python 類比：就像 SQLite 的 WAL mode
# conn.execute("PRAGMA journal_mode=WAL")
# 先寫 log，crash 後可以從 log 重建
```

### Remote Write

Prometheus 把 scrape 到的資料推送到外部 TSDB（如 VictoriaMetrics、AMP）的機制。是集中化監控的核心。

```python
# Python 類比：就像你在 inference worker 裡
# 把結果同時寫到本地 SQLite 和遠端 PostgreSQL
import sqlite3
import psycopg2

def save_result(data):
    local_db.execute("INSERT ...", data)    # 本地 Prometheus TSDB
    remote_db.execute("INSERT ...", data)  # remote_write 到中央 VictoriaMetrics
```

### Retention（保留期）

資料保留多久，過期自動刪除。

查看啟動參數：
```bash
kubectl get pod prometheus-server-0 -o yaml | grep retention
# → --storage.tsdb.retention.time=45d
```

---

## Recording Rules（預計算規則）

Recording rules 讓你把常用的 PromQL 表達式**預先計算**並儲存成新的 metric，之後查詢時直接讀取結果，不需要每次重新掃描大量原始資料。

**為什麼推論系統需要它：** Grafana dashboard 每 15 秒重新查詢一次 p99 延遲，每次都需要掃描大量 histogram bucket。改用 recording rule 後，Prometheus 每分鐘只計算一次，Grafana 直接讀現成的值，dashboard 速度提升 10x 以上。

```yaml
# prometheus/rules/inference_rules.yml
groups:
  - name: inference_recording_rules
    interval: 1m   # 每分鐘計算一次
    rules:
      # 把 p99 推論延遲預計算成一個新 metric
      - record: job:inference_duration_seconds:p99
        expr: |
          histogram_quantile(0.99,
            sum(rate(inference_duration_seconds_bucket[5m])) by (le, model_name)
          )

      # 每秒推論請求數（按 model 分組）
      - record: job:inference_requests:rate5m
        expr: |
          sum(rate(inference_requests_total[5m])) by (model_name, status)

      # 推論錯誤率
      - record: job:inference_error_rate:rate5m
        expr: |
          sum(rate(inference_requests_total{status="error"}[5m])) by (model_name)
          /
          sum(rate(inference_requests_total[5m])) by (model_name)
```

```python
# Python 類比：recording rule 就像把昂貴的計算結果 cache 起來
from functools import lru_cache

# ❌ 每次查詢都重新計算（expensive）
def get_p99_latency():
    return np.percentile(load_all_latency_data(), 99)

# ✅ 每分鐘預計算，查詢時直接返回
@lru_cache(maxsize=1)
def get_p99_latency_cached():
    return precomputed_p99  # Prometheus recording rule 的等效概念
```

在 `prometheus.yml` 中載入 rules 檔案：
```yaml
rule_files:
  - "rules/*.yml"
```

---

## Alerting（告警）

### Alert Rules（告警規則）

在 Prometheus 中定義「什麼情況下要觸發告警」。

```yaml
# prometheus/rules/inference_alerts.yml
groups:
  - name: inference_alerts
    rules:
      # p99 推論延遲超過 500ms 超過 5 分鐘
      - alert: HighInferenceLatency
        expr: |
          histogram_quantile(0.99,
            rate(inference_duration_seconds_bucket[5m])
          ) > 0.5
        for: 5m   # 持續 5 分鐘才觸發（避免短暫 spike 誤報）
        labels:
          severity: warning
          team: ml-platform
        annotations:
          summary: "推論延遲過高 (model={{ $labels.model_name }})"
          description: "p99 延遲 {{ $value | humanizeDuration }}，超過 500ms 閾值"

      # 推論錯誤率超過 5%
      - alert: HighInferenceErrorRate
        expr: |
          (
            sum(rate(inference_requests_total{status="error"}[5m])) by (model_name)
            /
            sum(rate(inference_requests_total[5m])) by (model_name)
          ) > 0.05
        for: 2m
        labels:
          severity: critical
          team: ml-platform
        annotations:
          summary: "推論錯誤率過高 (model={{ $labels.model_name }})"
          description: "錯誤率 {{ $value | humanizePercentage }}，超過 5% 閾值"

      # 模型未載入
      - alert: ModelNotLoaded
        expr: model_loaded == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "模型未載入 ({{ $labels.model_name }})"
```

---

### AlertManager

Prometheus 觸發告警後，**AlertManager** 負責後續的通知工作流程：去重（deduplication）、分組（grouping）、靜音（silencing）、路由（routing）到不同通知渠道。

**告警完整流程：**

```
推論服務 /metrics
    ↓ scrape (30s)
Prometheus TSDB
    ↓ 評估 alert rules (每 1m)
Alert 觸發 (PENDING → FIRING)
    ↓ 推送到 AlertManager
AlertManager
    ├─ 去重：同一個 alert 只通知一次
    ├─ 分組：把同 model 的多個 alert 合併成一封郵件
    ├─ 靜音：維護時間窗口內不發通知
    └─ 路由：
        ├─ severity=critical → PagerDuty（叫人起床）
        ├─ severity=warning  → Slack #ml-platform-alerts
        └─ team=ml-platform  → 特定 Slack channel
```

**AlertManager 設定範例：**

```yaml
# alertmanager.yml
global:
  slack_api_url: "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"

route:
  group_by: ["alertname", "model_name"]
  group_wait: 30s       # 等 30s 收集同組告警再一起發
  group_interval: 5m    # 同組新告警至少間隔 5m 才再發
  repeat_interval: 4h   # 持續告警每 4h 重複通知
  receiver: "slack-default"
  routes:
    - match:
        severity: critical
      receiver: "pagerduty"
    - match:
        team: ml-platform
      receiver: "slack-ml-platform"

receivers:
  - name: "slack-default"
    slack_configs:
      - channel: "#alerts"
        title: "{{ .GroupLabels.alertname }}"
        text: "{{ range .Alerts }}{{ .Annotations.description }}\n{{ end }}"

  - name: "slack-ml-platform"
    slack_configs:
      - channel: "#ml-platform-alerts"
        text: "{{ range .Alerts }}{{ .Annotations.summary }}\n{{ end }}"

  - name: "pagerduty"
    pagerduty_configs:
      - routing_key: "YOUR_PAGERDUTY_KEY"
```

```python
# Python 類比：AlertManager 就像一個智能的 notification router
def handle_alert(alert):
    # 去重：同一個 alert 10 分鐘內不重複發
    if is_duplicate(alert):
        return

    # 分組：累積 30 秒再一起發
    alert_buffer.append(alert)

    # 路由：根據 severity 決定通知方式
    if alert.severity == "critical":
        pagerduty.notify(alert_buffer)
    else:
        slack.notify("#ml-platform-alerts", alert_buffer)
```

---

## Exemplars（範例連結）

Exemplar 是 Histogram metric 上附加的一個**指向 Trace ID 的指標**，讓你從「p99 延遲尖峰」直接跳轉到「那次具體的 trace」。這是 Metrics → Traces 的橋樑。

**為什麼推論系統需要它：** 你看到 p99 推論延遲突然從 100ms 飆到 2s，但你不知道是哪一批次的請求造成的。有了 exemplar，你可以直接點擊那個尖峰，跳到對應的 Jaeger/Tempo trace，看完整的推論執行路徑。

```python
from prometheus_client import Histogram
from opentelemetry import trace

inference_duration_seconds = Histogram(
    "inference_duration_seconds",
    "Inference duration",
    ["model_name"],
    buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5]
)

def run_inference_with_exemplar(model_name: str, input_data):
    # 取得當前 trace context
    current_span = trace.get_current_span()
    trace_id = format(current_span.get_span_context().trace_id, "032x")

    with inference_duration_seconds.labels(model_name=model_name).time():
        result = model.predict(input_data)

    # 手動附加 exemplar（需要 OpenMetrics 格式）
    # prometheus_client >= 0.16 支援
    inference_duration_seconds.labels(model_name=model_name).observe(
        duration,
        exemplar={"traceID": trace_id}
    )
    return result
```

Prometheus 必須用 OpenMetrics 格式 scrape 才能收到 exemplars：
```yaml
# prometheus.yml
scrape_configs:
  - job_name: "inference-service"
    scrape_interval: 15s
    # 啟用 OpenMetrics 格式以支援 exemplars
    scrape_protocols:
      - OpenMetricsText1.0.0
      - PrometheusText0.0.4
    static_configs:
      - targets: ["inference-service:8000"]
```

---

## 費用計算

### Ingestion Rate（攝取速率）

每秒寫入多少 samples：

```promql
sum(rate(prometheus_tsdb_head_samples_appended_total[7d]))
```

### AMP 費用計算

```python
# 費用計算公式
active_series = 50_000          # 每 Region
scrape_interval_sec = 30
regions = 10
hours_per_month = 744  # 31 天

scrapes_per_hour = 3600 / scrape_interval_sec  # = 120
samples_per_region = active_series * scrapes_per_hour * hours_per_month
# = 50,000 × 120 × 744 = 4,464,000,000（~44.6 億）

total_samples = samples_per_region * regions
# = 446 億 samples/月
```

**AMP 費率（分階收費）：**

| 階層 | 範圍 | 每 1000 萬 samples |
|------|------|:---:|
| Tier 1 | 前 20 億 | $0.90 |
| Tier 2 | 20-200 億 | ~$0.72 |
| Tier 3 | 200-700 億 | ~$0.54 |

### QSP — Query Samples Processed

你在 Grafana 執行 PromQL 時，AMP 掃描了多少 data points。費率：$0.10 / 10 億 samples。通常這個費用很低。

---

## 查詢

### PromQL 常用函數

| 函數 | 用途 | 範例 |
|------|------|------|
| `rate()` | 計算 counter 的每秒增長率 | `rate(http_requests_total[5m])` |
| `sum()` | 加總 | `sum(rate(http_requests_total[5m]))` |
| `avg()` | 平均 | `avg(cpu_usage)` |
| `count()` | 計數 | `count({__name__=~".+"})` |
| `sort_desc()` | 降序排列 | `sort_desc(sum by (job) (...))` |
| `avg_over_time()` | 時間範圍內的平均值 | `avg_over_time(metric[7d])` |
| `by` | 按 label 分組 | `sum by (namespace) (...)` |
| `histogram_quantile()` | 計算百分位數 | `histogram_quantile(0.99, rate(duration_bucket[5m]))` |

```python
# Python 類比：PromQL 就像 pandas 的 groupby + rolling
import pandas as pd

# rate(http_requests_total[5m]) ≈ 5 分鐘滑動窗口的增長率
df.set_index("timestamp")["requests"].rolling("5min").apply(lambda x: (x[-1]-x[0])/300)

# sum by (namespace) (...) ≈ groupby
df.groupby("namespace")["requests"].sum()

# histogram_quantile(0.99, ...) ≈ np.percentile
import numpy as np
np.percentile(latency_data, 99)
```

---

## 架構元件

### VictoriaMetrics

高效能的 Prometheus 替代 TSDB，100% 相容 PromQL，壓縮率和記憶體效率比 Prometheus 好很多。

| 元件 | 職責 |
|---|---|
| `vminsert` | 接收 remote_write 寫入 |
| `vmselect` | 處理 PromQL 查詢 |
| `vmstorage` | 儲存資料 |
| `vmagent` | 輕量的 scrape + remote_write agent（可替代 Prometheus） |

### Thanos

在 Prometheus 之上的擴展層，提供跨 cluster 查詢和 S3 長期儲存。

| 元件 | 職責 |
|---|---|
| `Sidecar` | 貼在 Prometheus 旁邊，提供 Store API + 上傳 blocks 到 S3 |
| `Querier` | 中央查詢元件，fan-out 到所有 sidecar |
| `Store Gateway` | 從 S3 讀歷史資料 |
| `Compactor` | 壓縮和降採樣 S3 上的資料 |

---

## K8s 監控相關

| 元件 | 職責 |
|---|---|
| `kube-state-metrics` | K8s 物件狀態（pod/deployment/node）轉成 Prometheus metrics |
| `node-exporter` | 每個 node 跑一個，收機器層級 metrics |
| `cAdvisor` | Container 層級的 resource metrics，通常內建在 kubelet 裡 |
| `ServiceMonitor/PodMonitor` | Prometheus Operator 的 CRD，宣告式定義 scrape targets |

---

## 常見縮寫

| 縮寫 | 全名 | 說明 |
|------|------|------|
| TSDB | Time Series Database | 時間序列資料庫 |
| WAL | Write-Ahead Log | 預寫日誌 |
| HA | High Availability | 高可用 |
| QSP | Query Samples Processed | AMP 查詢計費單位 |
| IRSA | IAM Roles for Service Accounts | EKS pod 用 IAM role 的機制 |
| OTel | OpenTelemetry | 開源的 observability 標準 |
| AMP | Amazon Managed Prometheus | AWS 託管 Prometheus |
| AMG | Amazon Managed Grafana | AWS 託管 Grafana |
| DT | Data Transfer | 資料傳輸（AWS 網路費） |
