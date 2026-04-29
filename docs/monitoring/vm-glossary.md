---
sidebar_position: 17
---

# VictoriaMetrics 名詞解釋

> VM 生態的元件名稱多，這裡統一說明每個名詞的職責和關係。

---

## 核心元件

| 名詞 | 全名 / 說明 |
|------|-------------|
| **VMSingle** | VictoriaMetrics 單節點版本，單一 binary，適合小規模單 Region 部署 |
| **VMCluster** | VictoriaMetrics 叢集版本，由 vminsert + vmstorage + vmselect 三個元件組成 |
| **vminsert** | 寫入層，stateless，接收 remote_write，用 consistent hash 分配資料到各 vmstorage |
| **vmstorage** | 儲存層，stateful，把時間序列存到本地磁碟（EBS gp3） |
| **vmselect** | 查詢層，stateless，接收 PromQL，fan-out 到所有 vmstorage 後合併結果 |
| **vmauth** | 認證路由層，TLS 終止 + bearer token 驗證 + 路由規則（寫入 → vminsert，讀取 → vmselect） |
| **VMAgent** | 輕量 scraper，只做 scrape + remote_write，不存資料，是 Prometheus 的 drop-in 替代（config 格式相同） |
| **vmalert** | Alert rule 引擎，定期對 vmselect 執行 PromQL，觸發時通知 Alertmanager |
| **VMUI** | VictoriaMetrics 內建 Web UI，提供 cardinality explorer 和 query playground |
| **MetricsQL** | VictoriaMetrics 的查詢語言，100% 相容 PromQL，並額外支援 `with()`, `keep_last_value()` 等擴充函數 |

---

## Kubernetes Operator 元件

VictoriaMetrics Operator 用 CRD 管理 VM 元件，不直接操作 pod。

| CRD 名稱 | 說明 |
|---------|------|
| **VMCluster** | 宣告一個 VMCluster（含 vminsert/vmstorage/vmselect 的 replica 數、資源、storage） |
| **VMAgent** | 宣告一個 VMAgent 實例及其 scrape 設定 |
| **VMAuth** | 宣告 vmauth 實例，引用同 namespace 的 VMUser 建立路由規則 |
| **VMUser** | 宣告一個 bearer token 及它能存取的路由（寫入 or 讀取） |
| **VMRule** | 宣告 alert rules，格式與 Prometheus PrometheusRule 相同 |
| **VMAlertmanager** | 宣告 Alertmanager 實例 |

---

## 關鍵參數

| 參數 | 說明 |
|------|------|
| `replicationFactor` | 每筆資料寫到幾個 vmstorage 節點，設 2 代表 1 個節點掛掉資料不丟 |
| `retentionPeriod` | 資料保留時間（例如 `90d`），超過後 vmstorage 自動清除 |
| `consistent hashing` | vminsert 決定資料寫到哪個 vmstorage 的演算法，確保同一個 metric 固定落在同幾個節點 |
| `WAL` | Write-Ahead Log，vminsert 的寫入緩衝，避免在 vmstorage 暫時不可用時丟資料 |
| `stream aggregation` | vminsert 在資料進入 vmstorage 前做聚合，用於降低高基數 metric 的 series 數量 |
| `cardinality` | 一個 metric 的唯一 label 組合數量，過高（基數爆炸）會讓 RAM 和磁碟使用量暴增 |

---

## 元件關係圖

```
Prometheus / VMAgent
  │
  └── remote_write ──▶ vmauth（TLS + token 驗證）
                            │
                       vminsert × N（stateless，consistent hash sharding）
                            │
                   ┌────────┴─────────┐
              vmstorage-0  ...  vmstorage-N（stateful，EBS）
                   └────────┬─────────┘
                            │
                       vmselect × N（stateless，fan-out + merge）
                            │
                     Grafana / vmalert
```

---

## 與 Prometheus 生態對照

| Prometheus 元件 | VM 對應元件 | 差異 |
|---------------|-----------|------|
| Prometheus（scrape + TSDB） | VMAgent（scrape only）+ VMCluster（TSDB） | VM 把職責分離 |
| Prometheus remote_write | vminsert | VM 的寫入入口 |
| Prometheus TSDB | vmstorage | VM 用 MergeTree 引擎，RAM 效率更高 |
| PromQL | MetricsQL | VM 擴充了部分函數 |
| Prometheus built-in alerting | vmalert | 獨立部署，支援 HA replica |
| PrometheusRule CRD | VMRule CRD | 格式完全相同，可直接複製 |
