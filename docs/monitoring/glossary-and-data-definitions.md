---
sidebar_position: 2
---

# 監控成本分析 — 名詞解釋與資料定義

> 確認每個數據的定義和來源，確保成本估算基於正確的輸入值。

---

## 1. Prometheus 基本概念

### 1.1 Metric（指標）

一個被監控的測量值。例如：
- `cpu_usage` — CPU 使用率
- `http_requests_total` — HTTP 請求總數
- `queue_depth` — 佇列深度

每個 metric 可以有多個 **label**（標籤）來區分不同維度：
```
http_requests_total{method="GET", status="200", pod="app-abc123"}
http_requests_total{method="POST", status="500", pod="app-abc123"}
```
上面雖然是同一個 metric name，但因為 label 不同，算作 **2 個 time series**。

---

### 1.2 Time Series（時間序列）

一個 metric name + 一組固定的 label key-value 組合 = 一個 time series。

```
例如你有一個 metric: container_cpu_usage
label: {pod="app-a", namespace="prod"}    → 這是 1 個 time series
label: {pod="app-b", namespace="prod"}    → 這是另 1 個 time series
label: {pod="app-c", namespace="staging"} → 又另 1 個 time series
```

**為什麼重要：** AMP 的費用跟 time series 數量直接相關，series 越多 = 費用越高。

---

### 1.3 Active Time Series（活躍時間序列）

目前正在被 Prometheus scrape 的 time series 數量。如果一個 pod 被刪了，它的 series 過一段時間會變 stale（不活躍），就不算在內了。

**怎麼查：**
```promql
prometheus_tsdb_head_series
```

---

### 1.4 Sample（樣本）

Prometheus 每次 scrape 一個 time series，就產生 **1 個 sample**。
一個 sample = 一個 timestamp + 一個 value。

```
例如：
  時間 10:00:00  cpu_usage{pod="app-a"} = 0.75    ← 1 個 sample
  時間 10:00:30  cpu_usage{pod="app-a"} = 0.82    ← 又 1 個 sample
```

**為什麼重要：** AMP 按 sample 數量收費。

---

### 1.5 Scrape Interval（抓取間隔）

Prometheus 多久去拉一次 metrics 資料。

| 間隔 | 每小時 scrape 次數 | 說明 |
|:---:|:---:|------|
| 15s | 240 次 | 很高頻，成本最高 |
| **30s** | **120 次** | **業界預設** |
| 60s | 60 次 | 成本減半 |

**怎麼查：**
```promql
prometheus_target_interval_length_seconds{quantile="0.99"}
```
或看 Prometheus config：
```bash
kubectl get configmap prometheus-server -n monitoring -o yaml | grep scrape_interval
```

---

### 1.6 Retention（資料保留期）

Prometheus 保留多久的歷史資料，過期的自動刪除。

查看啟動參數：
```bash
kubectl get pod prometheus-server-0 -o yaml | grep retention
# → --storage.tsdb.retention.time=45d
```

---

### 1.7 Scrape Samples Scraped（每次抓取的樣本數）

每次 Prometheus 去 scrape 一個 target（一個 pod/endpoint），抓回來多少個 samples。

**怎麼查：**
```promql
# 找出 samples 最多的 target
sort_desc(scrape_samples_scraped)
```

高 scrape samples 的 target 對 ingestion rate 影響最大，是優化的首要目標。

---

## 2. 費用計算相關

### 2.1 Ingestion（攝取）

將 metrics 資料推送到中央 TSDB 的過程。

**AMP 計費方式：**
```
每月 sample 數 = active_time_series × (3600 ÷ scrape_interval) × 月時數

例如：
  50,000 series × 120 scrapes/hour × 744 hours/month
  = 4,464,000,000 samples/month（~44.6 億）
```

**AMP 費率（分階收費）：**

| 階層 | 範圍 | 每 1000 萬 samples |
|------|------|:---:|
| Tier 1 | 前 20 億 | $0.90 |
| Tier 2 | 20-200 億 | ~$0.72 |
| Tier 3 | 200-700 億 | 更低 |
| Tier 4 | 700 億以上 | 更低 |

---

### 2.2 Storage（儲存）

指標資料壓縮後存在 TSDB 中所佔用的磁碟空間。

**AMP 費率：** $0.03 / GB / 月

Time series 資料壓縮率很高（每個 sample 壓縮後約 1-2 bytes），所以存儲費用通常很低。

---

### 2.3 QSP — Query Samples Processed（查詢處理樣本數）

你在 Grafana dashboard 執行 PromQL 查詢時，AMP 掃描了多少 data points。

**AMP 費率：** $0.10 / 10 億 samples

通常這個費用很低，除非有非常重的查詢。

---

### 2.4 Data Transfer（資料傳輸費）

跨 region 傳輸資料的 AWS 網路費用。

| 情境 | 費用 |
|------|------|
| AMP remote_write（Data Transfer IN） | **免費** |
| 自建方案跨 region 流量 | ~$0.02/GB |

---

### 2.5 AMG User License（Grafana 使用者授權）

| 類型 | 權限 | 月費 |
|------|------|:---:|
| Editor | 建立/編輯 dashboard、管理 alert | $9/人 |
| Viewer | 只能看 dashboard | $5/人 |

只計算**當月有登入**的 active user。

---

## 3. K8s 基礎設施相關

### 3.1 Node Instance Type（節點機型）

EKS cluster 使用的 EC2 機型。常見配置：

| 機型 | vCPU | RAM | On-demand (us-east-1) |
|------|:---:|:---:|:---:|
| t3.medium | 2 | 4 GB | ~$30/month |
| t3.xlarge | 4 | 16 GB | ~$120/month |
| m5.large | 2 | 8 GB | ~$70/month |
| m5.xlarge | 4 | 16 GB | ~$140/month |

### 3.2 Pod Resource Requests / Limits

K8s 中每個 pod 可以設定要求（requests）和上限（limits）的 CPU/Memory。

```yaml
resources:
  requests:
    cpu: "100m"      # 保證 0.1 vCPU
    memory: "256Mi"  # 保證 256 MB
  limits:
    cpu: "500m"      # 最多用 0.5 vCPU
    memory: "512Mi"  # 最多用 512 MB
```

未設定 requests/limits 的 pod 跟其他 app 共用 node 資源，沒有保障也沒有限制。

### 3.3 Prometheus 實際資源用量（參考值）

| Pod | CPU | Memory | 說明 |
|-----|:---:|:---:|------|
| prometheus-server (primary) | ~80m | ~1.4 Gi | 主要 Prometheus |
| prometheus-server (replica) | ~40m | ~1.7 Gi | 副本 Prometheus |
| grafana | ~25m | ~110 Mi | Grafana |
| kube-state-metrics | ~1m | ~22 Mi | K8s 物件指標 |
| node-exporter (per node) | ~10m | ~77 Mi | 每個 node 一個 |

> CPU 單位：`m` = millicores，1000m = 1 vCPU
> Memory 單位：`Mi` = Mebibytes，1024 Mi ≈ 1 GB
