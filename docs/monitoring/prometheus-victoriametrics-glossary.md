---
sidebar_position: 2
---

# Prometheus & VictoriaMetrics 核心名詞

---

## 基礎概念

| 名詞 | 一句話 | 補充 |
|---|---|---|
| **Metric** | 一個監控指標的名字 | 例如 `container_cpu_usage_seconds_total`，一個 metric 可以有很多條 time series |
| **Time Series** | 一條數據線 = metric 名字 + 一組特定 label 值 | 圖表上的一條線就是一個 time series |
| **Label** | 附加在 metric 上的 key-value 描述 | `{pod="my-pod", namespace="monitoring"}`，決定 time series 的身份 |
| **Cardinality** | 一個 metric 有多少條不同的 time series | label 值種類越多，cardinality 越高；過高會讓 Prometheus OOM |
| **Scrape** | Prometheus 主動去拉 metrics 的動作 | Pull-based，Prometheus 定期去各個 target 拉資料 |
| **Scrape Interval** | 多久拉一次 | 預設 1m，常設 15s |
| **Sample** | 一個時間點的一個值 | `(timestamp, value)` 的組合 |
| **Counter** | 只增不減的數值 | 例如總請求數、總 CPU 秒數；重啟後從 0 開始 |
| **Gauge** | 可增可減的數值 | 例如記憶體用量、目前連線數 |
| **Histogram** | 把數值分桶統計 | 例如請求延遲分佈 |

---

## Counter vs Gauge

```
Counter（只增不減）：
  container_cpu_usage_seconds_total = 5000  → 5001 → 5002 → ...
  pod 重啟後：0 → 1 → 2 → ...（從 0 重新計數）

  要看「速率」用 rate()：
  rate(container_cpu_usage_seconds_total[5m]) = 過去 5 分鐘平均每秒消耗幾 core

Gauge（可增可減）：
  container_memory_working_set_bytes = 500Mi → 600Mi → 450Mi → ...
  直接看值，不需要 rate()
```

---

## Counter Reset

當 pod 重啟，counter 會從 0 重新開始（下降），這叫 counter reset。

**Prometheus 如何處理：**

```
樣本序列：[5, 10, 4, 6]
              ↑ reset（10 → 4，值下降）

Prometheus rate() 算法：
  1. naive delta = 6 - 5 = 1
  2. 偵測到 reset（10 → 4）→ 加上 reset 前的值 10
  3. total = 1 + 10 = 11
  4. 等同於：(10-5) + (6-0) = 5 + 6 = 11 ✅ 正確

觸發條件：當前樣本值 < 前一個樣本值 = counter reset
```

**VM 透過 remote_write 的限制：**

VM 收到的是批次樣本，在 remote_write 剛啟用時沒有「之前」的歷史可比較，無法可靠偵測 reset，可能造成短暫尖峰。累積足夠歷史後就正常了。

---

## PromQL 常用函數

| 函數 | 用途 | 例子 |
|---|---|---|
| `rate(x[5m])` | counter 的每秒平均增長率 | CPU 使用率 |
| `irate(x[5m])` | 只看最後兩個樣本的瞬時增長率 | 更即時但波動大 |
| `increase(x[5m])` | 5 分鐘內 counter 增加了多少 | 5 分鐘內的請求數 |
| `sum by (label)` | 按 label 加總 | 各 namespace 的 CPU 總和 |
| `topk(10, x)` | 取前 10 名 | CPU 用量最高的 10 個 pod |
| `avg_over_time(x[1h])` | 1 小時內的平均值 | gauge 的小時平均 |

**CPU 用量 query 的正確寫法：**

```promql
# 只看真實 container，過濾掉 cAdvisor 的 pod-level 匯總
topk(10, sum by (pod) (
  rate(container_cpu_usage_seconds_total{
    container!="",    # 過濾掉 pause container
    container!="POD"  # 過濾掉 pod-level 匯總（不過濾會造成數值翻倍）
  }[5m])
))
```

---

## remote_write

| 名詞 | 一句話 |
|---|---|
| **remote_write** | Prometheus 把 metrics 推到遠端儲存的標準 API |
| **external_labels** | 加在所有 metrics 上的固定 label，如 `{region="us-east-1", cluster="eks-central"}` |
| **WAL** | Write-Ahead Log，Prometheus 本地 buffer，最多保留 ~2 小時 |
| **batch_send_deadline** | 最多等多久才 flush 一批資料（預設 5 秒） |
| **remote_write lag** | VM 的資料比 Prometheus 落後多少秒 |

**remote_write 健康指標：**

```promql
# 有沒有掉資料（這個 > 0 = 資料永久丟失）
rate(prometheus_remote_storage_samples_dropped_total[5m])

# 有沒有送失敗（retry 中）
rate(prometheus_remote_storage_samples_failed_total[5m])

# 落後多少秒（正常 < 30s）
prometheus_remote_storage_highest_timestamp_in_seconds
- ignoring(remote_name, url)
  prometheus_remote_storage_queue_highest_sent_timestamp_seconds
```

---

## VictoriaMetrics 架構（Cluster 模式）

```
Prometheus（各 region）
    ↓ remote_write + bearer token
vmauth（認證 + 路由）
    ↓
vminsert（接收寫入，port 8480）
    ↓
vmstorage（持久化儲存，port 8482）
    ↑
vmselect（處理查詢，port 8481）
    ↑
Grafana（視覺化）
```

| 元件 | 角色 | Port |
|------|------|------|
| vminsert | 接收 remote_write，分散到 vmstorage | 8480 |
| vmstorage | 儲存資料，replication | 8482 |
| vmselect | 處理查詢，合併多個 vmstorage 結果 | 8481 |
| vmauth | 認證 + 路由（read/write 分開） | 8427 |
| vmalert | 執行告警規則 | 8880 |

---

## Grafana

| 名詞 | 一句話 |
|---|---|
| **Datasource** | Grafana 連接資料來源的設定（Prometheus、VM 等） |
| **Datasource UID** | Datasource 的唯一 ID，dashboard 用這個找資料來源 |
| **Dashboard** | 一組 panel 的集合 |
| **Panel** | 一個圖表或統計數字 |
| **Variable** | Dashboard 上的下拉選單（例如選 region） |
| **Provisioning** | 用 YAML/JSON 自動設定 datasource 和 dashboard（IaC 方式） |

**為什麼 Datasource UID 要固定：**

```
如果 UID 不固定（每次 Grafana 重啟自動產生）：
  dashboard JSON 裡的 datasource UID 跟實際的 UID 不同
  → 所有 panel 都顯示「No data」
  → 要手動重新設定每個 panel 的 datasource

固定 UID（例如 victoriametrics-ds）：
  dashboard 搬到任何環境都能直接用
  → 不需要手動修改
```

---

## Prometheus + VictoriaMetrics 如何分工合作

我們選擇 **Prometheus 負責 scrape，VictoriaMetrics 負責儲存與查詢**。

### 為什麼這樣分

| 職責 | 選擇 | 原因 |
|---|---|---|
| Scrape（拉 metrics）| Prometheus | 最成熟的 service discovery、scrape config 生態 |
| 長期儲存 | VictoriaMetrics | RAM 效率比 Prometheus TSDB 高 7-10x，不需要 S3 |
| 查詢 | VictoriaMetrics（vmselect）| 支援 MetricsQL，multi-region 合併查詢 |

Prometheus 本地只保留 WAL buffer（約 2 小時），**真正的儲存在 VM**。

### 資料流

```
各 Region Target（Pod / Node）
    │
    │  15s scrape（pull-based）
    ▼
Prometheus
    │
    │  remote_write（HTTPS batch push）
    ▼
vmauth（TLS termination + bearer token 驗證）
    │
    ▼
vminsert（接收，consistent hash 分片）
    │
    ▼
vmstorage × 3（持久化，replicationFactor=2）
    ▲
    │  fan-out query
vmselect
    ▲
    │  PromQL / MetricsQL
Grafana
```

### 關鍵設定：prometheus.yml 的 remote_write

```yaml
remote_write:
  - url: https://vmauth.monitoring.svc:8427/insert/0/prometheus/api/v1/write
    bearer_token: "<region token>"
    queue_config:
      max_samples_per_send: 10000
      batch_send_deadline: 5s
      max_shards: 10
    tls_config:
      insecure_skip_verify: false
```

Prometheus 把 scrape 到的 samples 批次推送到 vmauth，vmauth 驗證 token 後轉發給 vminsert。

### Prometheus 本地保留什麼

```
Prometheus 本地：
  WAL（Write-Ahead Log）— 最近 ~2 小時的資料
  └── 用途：remote_write 失敗時的 retry buffer
  └── 網路斷線恢復後自動補傳，不丟資料

VictoriaMetrics：
  所有歷史資料（retentionPeriod: 90d）
  └── Grafana 查詢直接打 vmselect，不打 Prometheus
```
