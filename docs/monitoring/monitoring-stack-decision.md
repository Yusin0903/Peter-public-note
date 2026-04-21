---
sidebar_position: 7
---

# 集中式多 Region 監控 — 技術選型決策

> **情境：** 多個 AWS Region，各有獨立 Prometheus + Grafana。
> 目標：一個中央 TSDB + 一個 Grafana URL 查看所有 Region。
> **決策：VictoriaMetrics（自架）**

---

## 問題描述

當你在多個 Region 部署同一套服務，每個 Region 各有自己的 Prometheus + Grafana：

- 工程師必須查看多個不同 URL 才能得到跨 Region 全貌
- 沒有統一 alerting — 各 Region 各自孤立
- Dashboard 修改必須手動同步到每個 Region
- 無法有全局的 error rate、queue depth、pod health 視圖

---

## 評估方案

| 方案 | 每月成本 | 維運負擔 | 結論 |
|------|:-------:|:-------:|:----:|
| A: Prometheus Federation | ~$215 | 低 | ❌ 只有 aggregated metrics |
| B: VictoriaMetrics | ~$555-575 | 中 | ✅ 選用 |
| C: Thanos | ~$427 | 高 | ❌ 過於複雜 |
| D: AMP + AMG（AWS 託管） | ~$8,460 | 極低 | ❌ 成本 14-17 倍 |
| E: SigNoz | ~$475+ | 高 | ❌ 無多 Region 支援 |

> 跨 Region 傳輸走 Transit Gateway（AWS 內網），非公開網路。

---

## 重要：決定前先量你的 Active Series

最常見的錯誤是用估算值來估成本。

**原始假設：** 每 Region 50,000 active series → AMP 看起來可接受（~$614/月）

**實際量測後：** 平均每 Region ~613,000 series → AMP 要 ~$8,460/月

在決定技術選型前，先對每個 Prometheus 執行：
```promql
avg_over_time(prometheus_tsdb_head_series[7d])
```

以及攝取速率：
```promql
sum(rate(prometheus_tsdb_head_samples_appended_total[7d]))
```

**數字往往會讓你嚇一跳。**

---

## 方案 A：Prometheus Federation — ❌

**運作方式：**
```
Central Prometheus  ──/federate──▶  Region 1 Prometheus
                    ──/federate──▶  Region 2 Prometheus
                    ...
```

**成本明細：**

| 項目 | 規格 | 每月 |
|------|------|:----:|
| 中央 Prometheus（EC2） | m5.xlarge | ~$140 |
| EBS 儲存（gp3） | 500GB | ~$40 |
| 中央 Grafana（EC2） | t3.medium | ~$30 |
| 跨 Region 傳輸 | 極少（aggregated） | ~$5 |
| **合計** | | **~$215** |

**不選的原因：**
- 只拉取 **aggregated** metrics — raw time series 留在各 Region
- 無法對 raw data 做跨 Region 查詢（例如「在同一個 panel 顯示所有 Region 的 pod restarts」）
- 最便宜，但能力缺口讓它成為死路

---

## 方案 C：Thanos — ❌

**兩種模式都有問題：**

### Sidecar 模式（官方）
```
每個 Region EKS pod：
  ├── container: prometheus     ← 既有的
  └── container: thanos-sidecar ← 每個 Region manifest 都要加

中央：
  ├── Thanos Query
  ├── Thanos Store Gateway
  ├── Thanos Compactor
  └── S3（長期儲存，必要）
```

### Receive 模式（較新，較不成熟）
```
每個 Region：Prometheus ──remote_write──▶ Thanos Receive
中央：Query + Store + Compactor + S3
```

**成本明細：**

| 項目 | 規格 | 每月 |
|------|------|:----:|
| Thanos Query（EC2） | 2× m5.large（HA） | ~$140 |
| Thanos Store Gateway（EC2） | 2× m5.large | ~$140 |
| Thanos Compactor（EC2） | 1× m5.large | ~$70 |
| S3 儲存 | ~500GB 壓縮後 | ~$12 |
| S3 API 請求 | PUT/GET blocks | ~$20 |
| Thanos Sidecar | 與 Prometheus pod 共用 | ~$0 |
| 中央 Grafana（EC2） | t3.medium | ~$30 |
| 跨 Region 傳輸 | 走 Transit Gateway | ~$15 |
| **合計** | | **~$427** |

**不選的原因：**
- **Sidecar 模式：** 每個 Region 的 Kubernetes manifest 都需要新增 container — 多個 Region 意味著多次 manifest 修改 + rollout，遷移風險高
- **Receive 模式：** 較新的模式，生產案例較少
- **5 個元件**（Query、Store、Compactor、Sidecar/Receive、Query Frontend）vs VictoriaMetrics 的 3 個
- **需要 S3** — 額外的託管服務需要設定和監控
- **成本節省幅度有限：** ~$427 vs ~$555 — 每月省約 $128，但增加大量維運複雜度

---

## 方案 D：AMP + AMG — ❌

**運作方式：**
```
每個 Region：Prometheus ──remote_write + SigV4──▶ AMP Workspace ──▶ AMG
```

零基礎設施管理 — AWS 全包。

**成本明細（在 ~75,000 samples/sec 下）：**

| 項目 | 計算 | 每月 |
|------|------|:----:|
| AMP 攝取 Tier 1（前 20 億） | 20億 × $0.90/1000萬 | ~$180 |
| AMP 攝取 Tier 2（後 180 億） | 180億 × $0.72/1000萬 | ~$1,296 |
| AMP 攝取 Tier 3（剩餘 ~1,740 億） | 1740億 × $0.54/1000萬 | ~$9,396 |
| AMP 儲存 | ~200GB × $0.03/GB | ~$6 |
| AMG 編輯者 | 5 × $9 | ~$45 |
| AMG 檢視者 | 15 × $5 | ~$75 |
| 跨 Region 傳輸 | AMP DT-IN 免費 | ~$0 |
| **合計** | | **~$8,460** |

**不同規模下的成本：**

| 規模 | AMP + AMG | VictoriaMetrics | 差距 |
|------|:---------:|:---------------:|:----:|
| 目前（~75K samples/sec） | ~$8,460/月 | ~$555/月 | **15 倍** |
| 降低基數後（~57K） | ~$7,136/月 | ~$555/月 | **13 倍** |
| 積極清理（每 Region 100K series） | ~$2,616/月 | ~$555/月 | **5 倍** |

**不選的原因：**
- AMP **按攝取 sample 數收費** — 費用隨 series 數量線性增長
- VictoriaMetrics **按 EC2 規格收費** — 費用固定，不受 sample 量影響
- 實際量測每 Region 平均 ~613K series，AMP 貴 15 倍
- 即使積極降低基數，仍在 AMP 划算範圍之外

**AMP 適合的情況：** 每 Region active series 少於 100K，或 AWS 推出按 series 計費方案。

---

## 方案 E：SigNoz — ❌

**運作方式：**
```
每個 Region：OTel Collector ──OTLP──▶ Central SigNoz（ClickHouse）──▶ Built-in UI
```

**成本明細：**

| 項目 | 規格 | 每月 |
|------|------|:----:|
| ClickHouse 節點（EC2） | 3× r5.xlarge（32GB RAM） | ~$330 |
| EBS 儲存（gp3） | 3× 500GB | ~$120 |
| OTel Collector（per region） | 跑在既有 pod 內 | ~$0 |
| 跨 Region 傳輸 | 走 Transit Gateway | ~$25 |
| **合計** | | **~$475+** |

**不選的原因：**
- **沒有成熟的多 Region federation** — 官方文件只涵蓋單 Region；無成熟的自架多 Region 模式
- **ClickHouse 複雜度：** 多個 dashboard 同時開啟時 CPU 飆升（報告顯示 80%+）、診斷 log 長到 70GB+、Zookeeper/Keeper 依賴、AVX2 CPU 需求
- **社群版限制：** dashboard 數量上限、無 SSO、無多租戶
- **需求不匹配：** SigNoz 的價值在於 metrics+traces+logs 統一；若只需要 metrics，付出 ClickHouse 複雜度卻沒有發揮其優勢

---

## 方案 B：VictoriaMetrics — ✅ 選用

**運作方式：**
```
每個 Region（唯一修改：在 prometheus.yml 加上 remote_write）：
  Prometheus ──remote_write──▶ vmauth（TLS + bearer token）
                                    │
                               vminsert ×2
                                    │
                              vmstorage ×3
                                    │
                              vmselect ×2
                                    │
                           Central Grafana
```

**成本明細：**

| 項目 | 規格 | 每月 |
|------|------|:----:|
| vminsert（EC2） | 2× c5.large（HA） | ~$125 |
| vmselect（EC2） | 2× m5.large（HA） | ~$140 |
| vmstorage（EC2） | 3× r5.large（replicationFactor=2） | ~$277 |
| EBS 儲存（gp3） | 3× 500GB（90 天保留） | ~$120 |
| 中央 Grafana | 跑在既有 EKS | ~$0 |
| 跨 Region 傳輸 | 走 Transit Gateway | ~$25 |
| **合計** | | **~$555-575** |

**關鍵優勢：**

| 面向 | 說明 |
|------|------|
| 遷移風險最低 | 每個 Region 只需在 `prometheus.yml` 加 3 行。無 manifest 修改，無 pod 重啟。 |
| 成本固定 | 由 EC2 規格決定，不受 sample 量影響。metrics 增長費用不變。 |
| RAM 效率 | 相同基數下比 Prometheus 節省 7-10 倍 RAM。對高基數 Region 至關重要。 |
| 只有 3 個元件 | vminsert、vmselect、vmstorage — 比 Thanos 的 5 個少 |
| 無外部依賴 | 不需要 S3、不需要 Zookeeper |
| 內建基數探索器 | VMUI cardinality explorer 幫助調查和修復 series 爆炸 |
| 100% PromQL 相容 | 既有查詢和 alert 規則無需修改 |

**元件規格（預生產估算，上線後第 1 天依實際負載校正）：**

| 元件 | 副本數 | CPU | RAM | 儲存 |
|------|:------:|-----|-----|------|
| vminsert | 2（HA） | 1-2 vCPU | 1-2Gi | — |
| vmstorage | 3（replicationFactor=2） | 2-4 vCPU | 8-16Gi | 500Gi gp3 |
| vmselect | 2（HA） | 2-4 vCPU | 4-8Gi | — |
| vmauth | 2（HA） | 0.5 vCPU | 256Mi | — |

---

## 遷移策略（零中斷）

```
步驟 1：在一個 Region（INT/staging）部署 VictoriaMetrics + 中央 Grafana
步驟 2：在一個 Region 的 Prometheus 加上 remote_write
步驟 3：驗證資料 + dashboard
步驟 4：逐一推廣到其餘 Region
步驟 5：保留各 Region Grafana 作為回滾選項 — 永遠不刪除 Prometheus
```

回滾隨時可用：讓工程師切回各 Region 的 Grafana URL 即可。

---

## 經驗教訓

1. **先量再估算** — 原本假設每 Region 50K series，實際是平均 613K。成本估算偏差 12 倍。
2. **託管服務隱藏成本** — AMP 的零維運故事很吸引人，但按 sample 計費在大規模下相當昂貴。
3. **遷移策略制約技術選型** — Thanos Sidecar 是不錯的架構，但若想要零中斷遷移（只加 remote_write），VictoriaMetrics 是自然的選擇。
4. **傳輸成本是次要的** — 每月 $25-50 的跨 Region 傳輸費用，跟 compute 成本相比是雜音。不要過度優化。
