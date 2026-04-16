---
sidebar_position: 1
---

# Prometheus & Monitoring 常用名詞教學

> 跟 SRE 溝通時會用到的術語整理

---

## 核心概念

### Metric（指標）

一個被監控的測量值。例如 `cpu_usage`、`http_requests_total`。

### Label（標籤）

附加在 metric 上的 key-value，用來區分不同維度：
```
http_requests_total{method="GET", status="200", pod="app-a"}
                    ^^^^^^^^^^^   ^^^^^^^^^^^^   ^^^^^^^^^^^^
                    label 1       label 2        label 3
```

### Time Series（時間序列）

一個 metric name + 一組固定的 label 組合 = 一條 time series。Label 不同就是不同的 series。

### Sample（樣本）

一個 timestamp + 一個 value = 一個 sample。Prometheus 每次 scrape 一條 time series，就產生 1 個 sample。

### Active Time Series

目前正在被 Prometheus 追蹤的 time series 數量。Pod 被刪後，對應的 series 約 5 分鐘後變 stale。

### Cardinality（基數）

一個 metric 的 label 排列組合數量。高基數 = 很多條 time series = 吃記憶體和費用。

**Cardinality Explosion** = label 值太多（例如 user_id、request_id），導致 time series 數量爆炸。

---

## 資料收集

### Scrape（抓取）

Prometheus 主動去 target 的 `/metrics` endpoint 拉資料的動作（pull 模式）。

### Scrape Interval（抓取間隔）

多久 scrape 一次。常見值：15s / 30s / 60s。間隔越短，資料越即時但成本越高。

### Scrape Target（抓取目標）

Prometheus 要去 scrape 的 endpoint，通常是一個 pod 的 IP:port。

### Job

Prometheus config 裡定義的一組 scrape targets 的名稱。通常對應到一個 app 或服務。

### Service Discovery

Prometheus 自動發現 scrape targets 的機制。在 K8s 裡通常透過 kubernetes_sd_config 自動找到所有 pod。

### Exporter

把非 Prometheus 格式的 metrics 轉成 Prometheus 格式的中間層。
- `node-exporter` → 機器層級 metrics（CPU/RAM/Disk）
- `kube-state-metrics` → K8s 物件狀態（pod/deployment/node 數量）
- `blackbox-exporter` → 外部端點的 probe（HTTP/TCP/DNS）

---

## 資料儲存

### TSDB（Time Series Database）

專門為時間序列資料優化的資料庫。Prometheus 內建 TSDB 存在本地磁碟。

### Head Block

TSDB 中最近的資料（通常最近 2 小時），存在記憶體裡，查詢最快。

### WAL（Write-Ahead Log）

寫入前先寫 log 檔，確保 crash 後不丟資料。Prometheus 和 VictoriaMetrics 都用 WAL。

### Retention（保留期）

資料保留多久。過期自動刪除。

### Remote Write

Prometheus 把 scrape 到的資料推送到外部 TSDB（如 VictoriaMetrics、AMP）的機制。是集中化監控的核心。

### Ingestion（攝取）

把資料寫入 TSDB 的過程。Ingestion Rate = 每秒寫入多少 samples。

---

## 查詢

### PromQL（Prometheus Query Language）

Prometheus 的查詢語言。

常用函數：
| 函數 | 用途 | 範例 |
|------|------|------|
| `rate()` | 計算 counter 的每秒增長率 | `rate(http_requests_total[5m])` |
| `sum()` | 加總 | `sum(rate(http_requests_total[5m]))` |
| `avg()` | 平均 | `avg(cpu_usage)` |
| `count()` | 計數 | `count({__name__=~".+"})` |
| `sort_desc()` | 降序排列 | `sort_desc(sum by (job) (...))` |
| `avg_over_time()` | 時間範圍內的平均值 | `avg_over_time(metric[7d])` |
| `by` | 按 label 分組 | `sum by (namespace) (...)` |

### Recording Rule

預先計算好的 PromQL 結果，存成新的 time series。用來加速常用的重查詢。

### Alert Rule

定義告警條件的規則。當 PromQL 表達式持續滿足條件（超過 `for` 設定的時間），觸發告警。

---

## 架構元件

### Prometheus Server

核心元件，負責 scrape、存儲、查詢、告警評估。

### Alertmanager

接收 Prometheus 發出的 alert，負責去重、分組、路由、通知（email/Slack/PagerDuty）。

### Grafana

視覺化工具，連接 Prometheus 作為 datasource，用 PromQL 做 dashboard。

### VictoriaMetrics

高效能的 Prometheus 替代 TSDB。100% 相容 PromQL。壓縮率和記憶體效率比 Prometheus 好很多。
- `vmagent` — 輕量的 scrape + remote_write agent（可替代 Prometheus）
- `vminsert` — 接收寫入
- `vmselect` — 處理查詢
- `vmstorage` — 儲存資料

### Thanos

在 Prometheus 之上的擴展層，提供跨 cluster 查詢和 S3 長期儲存。
- `Sidecar` — 貼在 Prometheus 旁邊，提供 Store API
- `Querier` — 中央查詢元件，fan-out 到所有 sidecar
- `Store Gateway` — 從 S3 讀歷史資料
- `Compactor` — 壓縮和降採樣 S3 上的資料

---

## K8s 監控相關

### kube-state-metrics

把 K8s API 物件（pod/deployment/node/job）的狀態轉成 Prometheus metrics。
例如：`kube_pod_status_phase{phase="Running"}` = 有多少 pod 在 Running。

### node-exporter

每個 node 跑一個，收集機器層級的 metrics：CPU、記憶體、磁碟、網路。

### cAdvisor

收集 container 層級的 resource metrics（CPU/Memory per container）。通常內建在 kubelet 裡。

### ServiceMonitor / PodMonitor

Prometheus Operator 的 CRD，用來宣告式定義 scrape targets，不用手寫 Prometheus config。

---

## 常見縮寫

| 縮寫 | 全名 | 說明 |
|------|------|------|
| TSDB | Time Series Database | 時間序列資料庫 |
| WAL | Write-Ahead Log | 預寫日誌 |
| HA | High Availability | 高可用 |
| QSP | Query Samples Processed | AMP 查詢計費單位 |
| SLA | Service Level Agreement | 服務等級協議 |
| IRSA | IAM Roles for Service Accounts | EKS pod 用 IAM role 的機制 |
| OTel | OpenTelemetry | 開源的 observability 標準 |
| CRD | Custom Resource Definition | K8s 自訂資源 |
| DT | Data Transfer | 資料傳輸（AWS 網路費） |
| AMP | Amazon Managed Prometheus | AWS 託管 Prometheus |
| AMG | Amazon Managed Grafana | AWS 託管 Grafana |
