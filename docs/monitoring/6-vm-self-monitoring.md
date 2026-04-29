---
sidebar_position: 15
---

# VictoriaMetrics 自我監控

> 監控系統本身也需要被監控。VM cluster 有一批關鍵 metrics，沒有設好這些告警，資料靜默丟失你不會知道。

---

## 為什麼特別重要

VM 的失敗模式通常是**靜默的**：
- vminsert 接收到資料但因 vmstorage 滿了悄悄丟棄
- remote_write 因 WAL 滿了開始 drop，Prometheus 端只有一行 log
- vmstorage 磁碟快滿但沒有告警，寫入開始失敗

這些不是「服務掛掉」，是「服務在跑但資料不見了」，比宕機更難察覺。

---

## vmstorage 關鍵指標

### 資料丟失偵測

```promql
# 每秒被丟棄的 row 數（> 0 = 資料永久丟失）
rate(vm_rows_ignored_total[5m])

# 原因分類（reason label）：
#   - "big_metric_name"   — metric name 超過限制
#   - "invalid_raw_metric_name" — 格式錯誤
#   - "too_small_timestamp" / "too_big_timestamp" — 時間戳超出保留範圍
```

### 磁碟使用

```promql
# 各 vmstorage 節點的磁碟使用率（> 85% 要告警）
vm_data_size_bytes / vm_available_disk_space_bytes

# 預估還能撐幾天（基於過去 24h 的增長率）
predict_linear(vm_data_size_bytes[24h], 86400 * 7)
```

### 儲存效能

```promql
# 每秒寫入的 row 數（監控是否有突降）
rate(vm_rows_added_to_storage_total[5m])

# cache miss 率（高 = query 慢，需要加 RAM 或減少查詢量）
rate(vm_cache_misses_total[5m])
/ rate(vm_cache_requests_total[5m])

# out-of-order samples 比率（> 5% 需要調查）
# VM 接受亂序資料但有代價
rate(vm_rows_ignored_total{reason=~".*out_of_order.*"}[5m])
/ rate(vm_rows_added_to_storage_total[5m])
```

---

## vminsert 關鍵指標

```promql
# 寫入成功 vs 失敗（任何失敗都要告警）
rate(vm_http_requests_total{path="/insert/0/prometheus/api/v1/write", code="204"}[5m])
rate(vm_http_requests_total{path="/insert/0/prometheus/api/v1/write", code!="204"}[5m])

# vminsert → vmstorage 的連線錯誤
rate(vm_internallink_dial_errors_total[5m])

# replication 失敗（replicationFactor=2 下，一個節點失敗後仍可寫入，但會告警）
rate(vm_rpc_send_errors_total[5m])
```

---

## vmselect 關鍵指標

```promql
# 查詢延遲（p99 > 5s 需要調查）
histogram_quantile(0.99,
  rate(vm_request_duration_seconds_bucket{path=~"/select/.*"}[5m])
)

# 查詢錯誤率
rate(vm_http_requests_total{path=~"/select/.*", code=~"5.."}[5m])

# 同時進行的查詢數（過高會讓 vmselect OOM）
vm_concurrent_queries
```

---

## vmauth 關鍵指標

```promql
# token 驗證失敗（401/403，可能是 token 過期或 Region 設定錯誤）
rate(vm_http_requests_total{code=~"401|403"}[5m])

# 路由錯誤（vmauth 找不到對應的 backend）
rate(vm_http_requests_total{code="502"}[5m])
```

---

## VM Operator 健康

```promql
# Operator 是否能正常 reconcile VMCluster
controller_runtime_reconcile_errors_total{controller="vmcluster"}

# CRD 更新是否有 error
controller_runtime_reconcile_total{controller="vmcluster", result="error"}
```

---

## 建議 Alert Rules

```yaml
groups:
  - name: victoriametrics.rules
    rules:

      # 資料丟棄告警（最重要）
      - alert: VMRowsDropped
        expr: rate(vm_rows_ignored_total[5m]) > 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "VictoriaMetrics 正在丟棄資料 ({{ $labels.instance }})"
          description: "每秒丟棄 {{ $value | humanize }} rows，原因：{{ $labels.reason }}"

      # 磁碟空間告警
      - alert: VMStorageDiskHigh
        expr: |
          vm_data_size_bytes
          / (vm_data_size_bytes + vm_available_disk_space_bytes) > 0.85
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "vmstorage 磁碟使用超過 85% ({{ $labels.instance }})"

      # vmstorage 節點下線（replicationFactor=2 下，1 個節點掛掉資料安全但需盡快修復）
      - alert: VMStorageNodeDown
        expr: up{job="vmstorage"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "vmstorage 節點離線 ({{ $labels.instance }})"

      # remote_write 寫入失敗率
      - alert: VMInsertWriteErrors
        expr: |
          rate(vm_http_requests_total{path=~".*/insert/.*", code!="204"}[5m]) > 0.01
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "vminsert 寫入錯誤率上升"
```

---

## 用 VMUI 排查基數爆炸

VMUI 是 VictoriaMetrics 內建的 Web UI，提供 cardinality explorer：

```
URL: http://vmselect:8481/select/0/vmui/

Cardinality Explorer 功能：
  1. 查看 active series 數量最多的 metric names
  2. 查看某個 metric 的 label 值分佈（找出哪個 label 造成爆炸）
  3. 查看 time series churn rate（短命 series 的建立/消滅速率）
```

**基數爆炸排查步驟：**

```promql
# 步驟 1：確認哪個 job/instance 貢獻最多 series
topk(20, count by (job) ({__name__!=""}))

# 步驟 2：找出目標 job 裡基數最高的 metric
topk(20, count by (__name__) ({job="<高基數 job>"}))

# 步驟 3：找出造成爆炸的 label
count by (some_label) (some_high_cardinality_metric{job="<高基數 job>"})

# 步驟 4：計算移除某個 label 後能節省多少 series
# 如果 pod_id 有 10 萬個值，移除它可以減少 10 萬條 series
```

**緊急降基數（stream aggregation）：**

```yaml
# vminsert 的 stream aggregation config
# 在資料進入 vmstorage 前，把高基數 label drop 掉
- match: '{job="<高基數 job>"}'
  group_by: [job, namespace, endpoint]   # 只保留這些 label
  interval: 60s
  outputs: [last]   # 每 60s 一個聚合值
```

> ⚠️ Stream aggregation 會永久丟失被 drop 的 label 細節。操作前需確認哪些 label 可以犧牲。
