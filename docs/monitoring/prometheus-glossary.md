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

```python
# Python 類比：PromQL 就像 pandas 的 groupby + rolling
import pandas as pd

# rate(http_requests_total[5m]) ≈ 5 分鐘滑動窗口的增長率
df.set_index("timestamp")["requests"].rolling("5min").apply(lambda x: (x[-1]-x[0])/300)

# sum by (namespace) (...) ≈ groupby
df.groupby("namespace")["requests"].sum()
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
