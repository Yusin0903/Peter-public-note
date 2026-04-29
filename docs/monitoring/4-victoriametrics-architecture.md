---
sidebar_position: 13
---

# VictoriaMetrics 架構介紹

> VictoriaMetrics 是從頭設計的 TSDB，不是 Prometheus 的擴充層。
> 它相容 Prometheus API，但自己的 storage engine（MergeTree 類似 ClickHouse）讓它在 RAM 和 CPU 效率上遠勝 Prometheus。

---

## Single vs Cluster

VictoriaMetrics 有兩種部署形式：

| | Single（單節點） | Cluster（叢集） |
|--|:--------------:|:--------------:|
| 部署方式 | 單一 binary | vminsert + vmselect + vmstorage 分離 |
| 水平擴展 | ❌ | ✅（各元件獨立擴展） |
| HA | ❌ | ✅（replicationFactor） |
| 適用場景 | 單 Region、&lt;1M series | 多 Region、&gt;1M series、需 HA |
| 適用場景說明 | 各 Region 的本地 scraper（可用 VMAgent 替代） | **Central TSDB（選用）** |

---

## Cluster 模式三元件

### vminsert（寫入層，stateless）

**職責：**
- 接收 Prometheus `remote_write`（HTTP，Influx line protocol 也支援）
- 根據 consistent hashing 把資料分配給各 vmstorage 節點
- 無狀態 — 任意重啟，任意擴展，不存資料

```
Prometheus ──remote_write──▶ vminsert-0
                              vminsert-1  ← HA，任一掛掉另一個繼續
                                  │
                    consistent hash（按 metric name + labels）
                    │              │              │
              vmstorage-0    vmstorage-1    vmstorage-2
```

**類比（Python）：** 像一個 load balancer + sharding router。收到 request 後根據 `hash(metric_key) % n_nodes` 決定往哪個 storage 寫。自己不存任何資料。

### vmstorage（儲存層，stateful）

**職責：**
- 把時間序列資料存到本地磁碟（EBS gp3）
- 接收 vminsert 的寫入請求
- 回應 vmselect 的讀取請求

```
vmstorage-0:   EBS gp3 (/vm-data/)
  ├── data/
  │   ├── big/       ← 壓縮後的大 parts（類似 Thanos 的 S3 blocks）
  │   └── small/     ← 最近寫入的小 parts（待合併）
  └── indexdb/       ← 反向索引（metric name → series ID）
```

**replicationFactor=2 的意思：**
每筆資料寫到 **2 個** vmstorage 節點。3 個節點時：
- 正常：資料在 node-0 和 node-1（或任意 2 個）
- node-0 掛掉：資料在 node-1 和 node-2，查詢正常
- node-0 和 node-1 同時掛掉：只剩 node-2，資料不完整（但不會全失）

**類比：** 像 Python dict 存資料，但同時寫 2 份到不同的磁碟。`replication_factor = 2`。

### vmselect（查詢層，stateless）

**職責：**
- 接收 Grafana 的 PromQL 查詢
- 向所有 vmstorage 節點 fan-out 查詢（因為資料分散在各節點）
- 合併結果、去重（replication 造成的重複），回傳給 Grafana
- 有本地查詢快取（`cacheMountPath`）

```
Grafana ──PromQL──▶ vmselect-0
                    vmselect-1  ← HA
                        │
              fan-out 到所有 vmstorage 節點
              │              │              │
        vmstorage-0    vmstorage-1    vmstorage-2
              │              │              │
              └──────── 合併 + 去重 ─────────┘
                              │
                         回傳給 Grafana
```

---

## 完整資料流

### 寫入路徑（Write Path）

```
Region（每個）：
  Prometheus ──15s scrape──▶ local targets (pods)
      │
      └── remote_write (HTTPS, batch)
              │
           vmauth (TLS termination + bearer token 驗證)
              │
           vminsert × 2 (round-robin HA)
              │
           consistent hash sharding
        ┌────┴────┬────────┐
   vmstorage-0  vmstorage-1  vmstorage-2
   (replicationFactor=2: 每筆資料寫 2 個節點)
```

### 查詢路徑（Query Path）

```
Grafana ──HTTP GET /api/v1/query_range──▶ vmauth (bearer token 驗證)
                                              │
                                          vmselect × 2
                                              │
                                    fan-out to all vmstorage
                                    │           │           │
                               vmstorage-0  vmstorage-1  vmstorage-2
                                    │           │           │
                                    └─── merge + deduplicate ───┘
                                              │
                                          Grafana panel 顯示
```

### Alert 路徑

```
vmalert ──PromQL (定期 eval)──▶ vmselect ──▶ vmstorage
    │
    └── 觸發時 ──▶ Alertmanager ──▶ Slack / PagerDuty
```

---

## vmauth — 認證路由層

vmauth 是 VictoriaMetrics 生態裡的 **authenticated reverse proxy**，負責：
- TLS 終止（Prometheus ─HTTPS─▶ vmauth ─HTTP─▶ vminsert/vmselect）
- Bearer token 驗證（每個 Region 一個獨立 token）
- 路由規則：寫入走 vminsert，讀取走 vmselect

```yaml
# VMUser CRD（每個 Region 一個）
# ⚠️ bearerToken inline 只適合從 Secrets Manager apply-time 讀取後注入
# 實際部署：token 由 Terraform 從 Secrets Manager 讀取，在 apply 時填入
# 不應手動把明文 token 寫在 YAML 檔裡
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMUser
metadata:
  name: vmagent-region-sg
spec:
  bearerToken: "<由 Terraform 從 Secrets Manager 注入>"
  targetRefs:
    - crd:
        kind: VMCluster/vminsert
        name: vmcluster-central
      paths:
        - "/insert/0/prometheus/.*"   # 只允許寫入，不允許讀取

# Grafana 用的 VMUser（read-only）
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMUser
metadata:
  name: grafana-reader
spec:
  bearerToken: "<由 Terraform 從 Secrets Manager 注入>"
  targetRefs:
    - crd:
        kind: VMCluster/vmselect
        name: vmcluster-central
      paths:
        - "/select/0/prometheus/.*"   # 只允許讀取
```

**安全設計：**
- 各 Region token 相互隔離，一個 token 洩漏只影響那個 Region 的寫入
- Token 來源：AWS Secrets Manager → Terraform `data` source → apply-time inline 注入 VMUser CRD
- 不存在 K8s Secret（VM Operator v0.68.4 要求 inline bearerToken，非 bearerTokenSecret ref）
- Write token 只能 `/insert/...`；Read token 只能 `/select/...`

---

## VMAgent — Prometheus 的輕量替代

在各 Region，可以用 VMAgent 替換 Prometheus（或搭配 Prometheus 一起跑）。

| | Prometheus | VMAgent |
|--|:----------:|:-------:|
| 功能 | Scrape + TSDB + Query + Alert | **只做 Scrape + remote_write** |
| RAM（1.6M series，SG）| 需 4-8Gi（現在 1Gi OOM 邊緣）| ~500Mi-1Gi |
| Config 格式 | `scrape_configs:` | **完全相同** — drop-in |
| Persistent queue | WAL（2h 預設）| 可設定磁碟 queue，更長 |
| CPU | 較高 | 3-5x 較低 |

VMAgent 的職責：**scrape targets，把資料用 remote_write 推到中央 VMCluster，自己不存。**

```
各 Region（VMAgent 模式）：
  VMAgent ──scrape──▶ pods/nodes
      │
      └── remote_write（有持久化 queue，網路中斷不丟資料）
              │
           vmauth ──▶ vminsert ──▶ vmstorage
```

類比：VMAgent 就像 Python 的 `logging.handlers.MemoryHandler`，平常把 log 累積在 queue，達到一定量或間隔就 flush 給遠端；中央 VMCluster 是接收端的 server。

---

## IaC 部署（VictoriaMetrics Operator）

我們用 Kubernetes Operator 管理 VMCluster，不直接操作 pod。

```yaml
# VMCluster CRD — Operator 把它變成 vminsert×2、vmstorage×3、vmselect×2
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMCluster
metadata:
  name: vmcluster-central
  namespace: monitoring
spec:
  retentionPeriod: "90d"
  replicationFactor: 2

  vmstorage:
    replicaCount: 3
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          resources:
            requests:
              storage: 500Gi   # 每個節點 500Gi EBS
    resources:
      requests:
        memory: "8Gi"
        cpu: "2"
      limits:
        memory: "16Gi"
        cpu: "4"

  vminsert:
    replicaCount: 2
    resources:
      requests:
        memory: "1Gi"
        cpu: "1"

  vmselect:
    replicaCount: 2
    resources:
      requests:
        memory: "4Gi"
        cpu: "2"
```

Operator 監聽這個 CRD，自動建立對應的 Deployment、Service、PVC，並在 spec 改變時自動 rolling update。

---

## vmalert — Alert 規則引擎

vmalert 是 VictoriaMetrics 生態的 alert 引擎，功能等同 Prometheus 的 built-in alerting，但獨立部署。

**為什麼不用 Grafana Unified Alerting（GUA）：**
- GUA 內建的 Alertmanager **無法被外部系統（如 vmalert）呼叫**來路由告警 — GUA 只處理 Grafana 自己觸發的 alert
- Standalone Alertmanager 支援 `inhibit_rules`（一個 critical 可抑制同 region 的所有 warning），GUA 不支援此功能
- vmalert rule 格式與 Prometheus rule 格式 100% 相同 — 無遷移成本
- Alert rule 以 YAML 存在 git — 滿足 IaC 要求

```yaml
# vmalert rule 範例（格式與 Prometheus 完全相同）
groups:
  - name: example.rules
    rules:
      - alert: HighErrorRate
        expr: |
          sum(rate(api_request_total{namespace="<your-namespace>",code=~"5.."}[5m]))
          / sum(rate(api_request_total{namespace="<your-namespace>"}[5m])) > 0.05
        for: 5m
        labels:
          severity: warning
          region: "{{ $labels.region }}"
        annotations:
          summary: "High error rate in {{ $labels.region }}"
```

---

## MetricsQL 擴充

VictoriaMetrics 的查詢語言是 MetricsQL，100% 相容 PromQL，並額外支援：

| 擴充函數 | 功能 |
|---------|------|
| `with (...)` | 定義共用的 label filter，避免重複 |
| `default` operator | `metric_a default metric_b` — a 無值時用 b |
| `keep_last_value()` | 填補資料缺口（Prometheus 沒有） |
| `any()` | 比 `group by` 更靈活的聚合 |
| `top_k(k, expr)` | 直接取前 k 個 series |

**注意：** MetricsQL 的少數函數行為與 PromQL 不同（如 `histogram_quantile` 的邊界處理）。在從 Prometheus 遷移時，複雜的 alert rule 需要在 VMUI 驗證結果是否符合預期。
