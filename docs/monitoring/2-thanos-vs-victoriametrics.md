---
sidebar_position: 11
---
<!-- generated from ~/peter-llm-wiki; edit source there, not here -->

# Thanos vs VictoriaMetrics

> 兩者都解決「Prometheus 不能水平擴展」的問題，但設計哲學不同。
> 以下以實際在做的場景為例：10 個 AWS Region、~75K samples/sec、~4.9M active series 的中央化監控架構。
> 重點不在 $/月，而在**維運複雜度**——這才是真正燒工程時間的地方。

---

## 一句話差異

| | Thanos | VictoriaMetrics |
|--|--------|----------------|
| 設計哲學 | Prometheus 的擴充層（sidecars + object storage） | 從頭設計的 TSDB，相容 Prometheus API |
| 長期儲存 | S3 / GCS / Azure Blob（必須） | EBS 或本地磁碟（S3 可選） |
| 遷移方式 | 官方推薦：每個 Region 加 Sidecar container | 推薦：Prometheus remote_write（只改 config） |
| RAM 效率 | 與 Prometheus 相當 | 社群基準測試普遍宣稱顯著低於 Prometheus（見下方 RAM 段落，數字需以自身環境驗證） |
| PromQL 相容性 | 完整（本身就是 Prometheus 生態） | 99% 相容 + MetricsQL 擴充 |

---

## 元件數量比較（官方文件的事實基礎）

### Thanos 必要元件

根據 [Thanos 官方架構文件](https://thanos.io/tip/thanos/design.md/)：

| 元件 | 角色 | 是否必要 |
|---|---|---|
| Sidecar | 上傳 blocks 到 S3、提供 local Prom 查詢 | ✅ 每個 Prometheus 都要（Sidecar 模式） |
| Query (Querier) | 查詢入口，fan-out 到 Store/Sidecar | ✅ 必要 |
| Store Gateway | 從 S3 讀歷史資料 | ✅ 必要 |
| Compactor | 壓縮 blocks、downsampling、retention | ⚠️ 基本查詢可省，但生產必備 |
| Receive | 替代 Sidecar 的 push 模式 | ⚠️ 可選（與 Sidecar 二擇一） |
| Ruler | 中央執行 recording/alerting rules | ⚠️ 可選 |
| Query Frontend | 查詢 cache + 分片 | ⚠️ 強烈建議（生產規模） |

**生產規模最小配置：5 個元件**（Sidecar/Query/Store/Compactor + Query Frontend）

### VMCluster 必要元件

根據 [VictoriaMetrics Cluster 官方文件](https://docs.victoriametrics.com/cluster-victoriametrics/)：

> "A minimal cluster must contain the following nodes: a single `vmstorage`... a single `vminsert`... a single `vmselect`."

| 元件 | 角色 | 是否必要 |
|---|---|---|
| vmstorage | 儲存層、內建 merge/compaction | ✅ 必要 |
| vminsert | 寫入路由（stateless） | ✅ 必要 |
| vmselect | 查詢路由（stateless） | ✅ 必要 |
| vmagent | source 端 scraping / remote_write | ⚠️ 可選（用 Prometheus 也行） |
| vmalert | alerting rules | ⚠️ 可選 |
| vmauth | 認證/限流/路由 | ⚠️ 可選 |

**生產規模最小配置：3 個元件**

> 元件數差距：Thanos 約 **1.7 倍** 於 VMCluster。


---

## 架構模式比較

### Thanos Sidecar 模式（官方推薦）

```
每個 Region EKS Pod：
┌────────────────────────────────────┐
│ container: prometheus (既有)        │
│ container: thanos-sidecar (新增)   │ ← 每個 Region manifest 都要改
└────────────────────────────────────┘
         │ gRPC Store API (pull，非 push)
         ▼
Central：
  Thanos Query ──▶ Thanos Store Gateway ──▶ S3 (long-term)
                ──▶ Sidecar gRPC (recent data)
  Thanos Compactor（定期壓縮 S3 blocks）
```

**資料流：**
- 最近 2 小時的資料：Query 直接向各 Region 的 Sidecar 拉（gRPC）
- 超過 2 小時的資料：Sidecar 上傳到 S3，Query 透過 Store Gateway 讀取
- Compactor：定期把 S3 裡的小 block 合併壓縮，降低儲存和查詢成本

### Thanos Receive 模式（較新）

```
每個 Region：
  Prometheus ──remote_write──▶ Thanos Receive (central)
                                      │
                              Thanos Query Frontend
                              Thanos Store Gateway
                              Thanos Compactor
                              S3
```

**與 VictoriaMetrics 的架構類似，但元件更多。**

### VictoriaMetrics Cluster 模式

```
每個 Region（只改 prometheus.yml）：
  Prometheus ──remote_write──▶ vmauth (TLS + bearer token)
                                    │
                               vminsert ×2 (stateless)
                                    │
                              vmstorage ×3 (replicationFactor=2)
                                    │
                              vmselect ×2 (stateless)
                                    │
                           Central Grafana / vmalert
```

---

## 維運場景對比（這是真正的差距）

### 場景 1：擴容（增加儲存容量）

**Thanos**：
- S3 無限擴展，調整 lifecycle policy 或不動都可以
- ✅ **這是 Thanos 最大優勢**

**VMCluster**：
- 增加 vmstorage 節點時，官方明說：
  > "When new `vmstorage` nodes are added... only newly ingested data is distributed evenly among old and new `vmstorage` nodes, while historical data remains on the old `vmstorage` nodes."
  > — [Cluster Resizing and Scalability](https://docs.victoriametrics.com/cluster-victoriametrics/#cluster-resizing-and-scalability)
- 等 retention 過期，或臨時把新寫入導到新節點、舊節點只服務查詢
- ⚠️ **可運作，但要規劃 retention 窗口**

**結論：純擴儲存 Thanos 完勝**

### 場景 2：Compactor 故障

**Thanos**：
- [官方文件](https://thanos.io/tip/components/compact.md/)明說：
  > "Only one instance of Compactor may run against a single stream of blocks in a single object storage."
- 可以對「不同 stream」（用 external labels 分片）跑多 instance，但**同一 stream 同時只能一個**
- 並發跑同一 stream 會損毀資料（object storage 無一致性鎖）
- 已知問題：corrupted/incomplete block 會讓 compactor halt，需要手動清理
  - [#621 broken block 無限 loop](https://github.com/thanos-io/thanos/issues/621)
  - [#4046 dirty data 持續 restart](https://github.com/thanos-io/thanos/issues/4046)
  - [#6328 incomplete uploaded blocks](https://github.com/thanos-io/thanos/issues/6328)
- Compactor 掛了：compaction 停止 → S3 small blocks 累積 → 查詢變慢、成本上升

**VMCluster**：
- vmstorage 內建 background merge，**每個 storage node 獨立**處理自己分片的資料
- 沒有「compactor 單點」這個概念
- 一個 vmstorage node 掛了不影響其他 node 的 merge

### 場景 3：查詢慢，要 debug

**Thanos 的查詢路徑（Sidecar 模式）**：
```
Query → fan-out 到 → Store Gateway → S3
                  → Sidecar × N → Prometheus local TSDB × N
```

要看的層級：
1. Query 是否正確 fan-out、是否 partial response
2. Store Gateway 的 index cache / chunks cache hit rate
3. S3 latency / list operation 速率
4. Memcached/Redis 是否健康（如果有配）
5. 哪個 Region 的 Sidecar 慢

**VMCluster 的查詢路徑**：
```
vmselect → vmstorage (× N)
```

要看的層級：
1. vmselect 是否 timeout
2. 哪個 vmstorage 慢

對照兩者的官方 troubleshooting 文件即可看到差距：
- [Thanos troubleshooting](https://thanos.io/tip/operating/troubleshooting.md/) — 跨 Sidecar / Receiver / Overlaps 多個元件章節
- [VictoriaMetrics troubleshooting](https://docs.victoriametrics.com/troubleshooting/) — 集中在 vmstorage / vmselect

### 場景 4：Cache 配置（Thanos 獨有的複雜度）

[Thanos Store Gateway 官方文件](https://thanos.io/tip/components/store.md/#caching) 列出三層 cache：

1. **Index cache** — 找出哪些 blocks 包含查詢的 series（預設 in-memory）
2. **Caching bucket (chunks cache)** — 避免重複從 S3 讀 chunks（預設關閉）
3. **Index Header** — 啟動時從 block index 建立

| 後端 | 適用 |
|---|---|
| In-memory | 預設，僅 index cache 預設啟用；單實例、無共享 |
| Memcached / Redis | 生產規模強烈建議；多實例共享、跨重啟保留 |
| Groupcache | 實驗性，僅 caching bucket |

**生產規模實務**：
- In-memory 適合小規模；數百萬 series 以上、Store Gateway 多 replica 場景，沒有外部 cache 會導致重複讀 S3、index cache miss 後查詢非常慢
- Grafana Labs 公開分享他們 Thanos 用了大量 memcached（[How to monitor Thanos at scale](https://grafana.com/blog/2020/10/15/how-to-monitor-thanos-at-scale-step-by-step/)）
- 每個 cache 都要：決定大小、配置 stateful service、監控 hit rate、處理 eviction

**VMCluster**：
- vmselect 內建查詢 cache，無外部 cache service
- 調整 `-search.cacheTimestampOffset` 等參數即可，[官方文件](https://docs.victoriametrics.com/cluster-victoriametrics/)

### 場景 5：升級

**Thanos**：
- 5+ 個元件，要按順序升級（Sidecar → Store → Query → Compactor → Query Frontend）
- Sidecar 升級要動每個 Region 的 Prometheus pod（10 個 Region = 10 次 rollout）
- 沒有單一 operator 統一管理

**VMCluster**：
- 3 個元件，順序：vmstorage → vminsert/vmselect
- [vm-operator](https://docs.victoriametrics.com/operator/) 提供 CRDs（VMCluster、VMAgent、VMAlert、VMAuth…）
- 改一行 `spec.vmstorage.image.tag: v1.95.1`，operator 自動 rolling update

### 場景 6：監控自己（meta-monitoring）

| 項目 | Thanos | VictoriaMetrics |
|---|---|---|
| 官方 mixin / dashboards | [thanos mixin](https://github.com/thanos-io/thanos/tree/main/mixin) 涵蓋 Query / Query Frontend / Store / Receive / Compact / Bucket Replicate / Sidecar / Rule | [VM Grafana 官方頁](https://grafana.com/orgs/victoriametrics) 約 3-5 個 dashboard |
| 要看的元件數 | 8 個 | 3 個 |

> dashboards 與 alerts 的數量本身就是複雜度的代理指標。

---

## 元件數量 / 設定面複雜度（量化）

| 指標 | Thanos | VMCluster | 來源 / 備註 |
|---|---|---|---|
| Helm chart values 行數 | 1500+ | ~600 | [bitnami/thanos values](https://github.com/bitnami/charts/blob/main/bitnami/thanos/values.yaml) vs [VM cluster values](https://github.com/VictoriaMetrics/helm-charts/blob/master/charts/victoria-metrics-cluster/values.yaml) |
| 生產必要 K8s resources | StatefulSets × 2+（Store、Compactor）+ Deployments × 3+（Query、Query Frontend、Receive 或多 Sidecar）+ Service + ConfigMap + 建議 Memcached StatefulSet | StatefulSet × 1（vmstorage）+ Deployments × 2（vminsert、vmselect）+ Service | 官方 manifests |
| 建議外部依賴 | Memcached / Redis（生產規模強烈建議） | 無 | 上述官方文件 |
| Operator 統一管理 | 多個第三方 operator，無單一官方推薦 | 官方 [vm-operator](https://docs.victoriametrics.com/operator/) |  |

---

## RAM 效率對比

在 ~4.9M active series 的 central TSDB 場景：

| 方案 | 預估 Central RAM 需求 |
|------|:--------------------:|
| Thanos Store Gateway | 2-4Gi per node |
| Thanos Query | 2-8Gi（取決於查詢量） |
| VictoriaMetrics vmstorage | 8-16Gi **per node**（3 nodes，replicationFactor=2 實際存 ~9.8M series） |
| VictoriaMetrics vmselect | 4-8Gi per node |

VM 在 source 端的優勢更明顯：
- 高基數 Region 的 Prometheus 在 1.6M series 時已接近 OOM
- 換成 vmagent（無本地 TSDB，純 scrape + remote_write）可降到 ~500Mi
- vmagent 移除了本地 TSDB 整層，自然比 Prometheus 省 RAM

> ⚠️ 「VM 比 Prometheus 省 7-10x RAM」是社群基準測試常引用的數字，但 VM 官方文件並未明確背書此精確倍數。實務上要以自身 cardinality / 寫入速率測過才算數。

---

## 成本比較（以 10 Region、~75K samples/sec 為例）

| 項目                         | Thanos Receive | VictoriaMetrics |       差距        |
| -------------------------- | :------------: | :-------------: | :-------------: |
| EC2（Query、Store、Compactor） |     ~$350      |      ~$542      |    Thanos 便宜    |
| S3 儲存（必要 vs 可選）            |    ~$12-20     |       ~$0       | Thanos 多 $12-20 |
| EBS 儲存                     |    較少（靠 S3）    | ~$120（3× 500GB） |      VM 多       |
| **合計**                     |   **~$427**    |    **~$555**    |  VM 貴 ~$128/月   |

> $128/月 ≈ $1,536/年。**這個數字本身不是重點**——重點是換來的維運差距：
> - 少 ~1.7 倍元件
> - 少一個必要的外部 cache 服務
> - 升級從「跨 Region rollout + 多元件順序」變成「改一個 operator CRD」
> - debug 路徑從 5 層變 2 層
>
> 真正的成本不在帳單上，在「週末被 page 起來 debug Store Gateway OOM 或 Compactor halt」的工程時間。

---

## 遷移難度比較

### Thanos Sidecar 模式
```
要做的事（每個 Region）：
  1. 修改 Helm values 加 thanos-sidecar container
  2. 加 ObjectStore secret（S3 credentials）
  3. Rolling restart Prometheus pod
  4. 等 Sidecar 上傳初始 block 到 S3（可能 2+ 小時）
  5. 驗證 Thanos Query 能讀到這個 Region

風險：10 個 Region × 上述步驟 = 10 次 manifest 修改 + 10 次 rollout
```

### VictoriaMetrics remote_write
```
要做的事（每個 Region）：
  1. 在 prometheus.yml 加 remote_write block（3-5 行）
  2. reload Prometheus config（無需 restart）
  3. 驗證 VMUI 看到新 Region 的資料

風險：config reload 失敗最多讓 remote_write 不動，不影響本地 scraping
```

---

## 什麼情況下該選 Thanos

| 情況 | 為何偏向 Thanos |
|------|----------------|
| 資料保留超過 ~3 年 | Thanos 靠 S3 可無限保留；VM EBS 方案有成本上限 |
| 需要 multi-tenancy | Thanos Receive 有 tenant 隔離設計 |
| 需要跨 TSDB deduplication | 多個 Prometheus 同時抓同一個 target，Thanos Query 可去重 |
| 已有大量 S3 預算和經驗 | S3 依賴不是問題，反而是既有基礎設施 |
| 團隊有 Thanos 專責人員 | 運維複雜度有人承擔（5+ 人專職 observability team） |

---

## 不選 Thanos 的原因

1. **Sidecar 模式違背「零中斷遷移」策略** — 10 個 Region 全部要改 manifest + rollout
2. **Receive 模式元件複雜** — 雖已 production-ready（Thanos v0.32+），但 hashring 設定複雜、社群案例仍少於 Sidecar 模式
3. **S3 是額外依賴** — 需要管理 bucket、lifecycle policy、IAM policy
4. **元件多 = 故障點多** — 5+ 個 central 元件 vs VM 的 3 個
5. **Cache 層額外負擔** — 生產規模需 memcached/Redis stateful service
6. **Compactor 是已知雷區** — corrupted block 會 halt，需要手動介入
7. **$128/月 的節省不值得** — 換來明顯更高的運維負擔
8. **RAM 劣勢在 Region 端明顯** — 高基數 Region 已在 OOM 邊緣，vmagent 移除本地 TSDB 可大幅節省

> **判斷原則**：複雜度的成本不在帳單，在工程時間。
> 一個人/小團隊管 → VMCluster；5+ 人專職 observability team → Thanos 的複雜度可吸收，且 S3 擴展性開始有價值。

---

## 參考來源（驗證證據）

### Thanos 官方文件
- [Thanos Design](https://thanos.io/tip/thanos/design.md/) — 元件角色與職責
- [Thanos Compactor](https://thanos.io/tip/components/compact.md/) — 單實例限制與 label sharding
- [Thanos Store Gateway](https://thanos.io/tip/components/store.md/#caching) — Index cache / Caching bucket / Index Header
- [Thanos Troubleshooting](https://thanos.io/tip/operating/troubleshooting.md/) — Sidecar / Receiver / Overlaps 章節
- [Thanos Mixin](https://github.com/thanos-io/thanos/tree/main/mixin) — Query / Query Frontend / Store / Receive / Compact / Bucket Replicate / Sidecar / Rule 覆蓋

### Thanos GitHub Issues（已知 Compactor 問題）
- [#621 — compactor is in infinite loop when broken block](https://github.com/thanos-io/thanos/issues/621)
- [#4046 — Compactor should ignore dirty data or automatically delete corrupted data](https://github.com/thanos-io/thanos/issues/4046)
- [#6328 — \[Compactor\] Detect the incomplete uploaded blocks and exclude them from compaction](https://github.com/thanos-io/thanos/issues/6328)

### VictoriaMetrics 官方文件
- [VictoriaMetrics Cluster](https://docs.victoriametrics.com/cluster-victoriametrics/) — 三元件最小架構、resharding 行為
- [VictoriaMetrics Operator](https://docs.victoriametrics.com/operator/) — CRDs 與 GitOps 升級
- [VictoriaMetrics Troubleshooting](https://docs.victoriametrics.com/troubleshooting/) — 集中於 vmstorage / vmselect

### Helm Charts（行數對比）
- [bitnami/thanos values.yaml](https://github.com/bitnami/charts/blob/main/bitnami/thanos/values.yaml) — 1500+ 行
- [VictoriaMetrics cluster values.yaml](https://github.com/VictoriaMetrics/helm-charts/blob/master/charts/victoria-metrics-cluster/values.yaml) — ~600 行

### 生產經驗 blog
- [Grafana Labs — How to monitor Thanos at scale](https://grafana.com/blog/2020/10/15/how-to-monitor-thanos-at-scale-step-by-step/) — 大規模 Thanos memcached 配置經驗
