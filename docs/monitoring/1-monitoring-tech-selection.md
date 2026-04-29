---
sidebar_position: 10
---

# 集中式多 Region 監控 — 技術選型

> **背景：** 服務在 10 個 AWS Region 各跑一套 Prometheus + Grafana，工程師需查看 10 個不同 URL 才能得到全貌，且沒有統一 alerting。
> **目標：** 一個 Grafana URL、一套 alert system、所有 Region 資料都進得來。

---

## 先量，再選型

最常見的錯誤：用估算值做成本分析。

```promql
# 看每個 Prometheus 目前有多少 active time series
avg_over_time(prometheus_tsdb_head_series[7d])

# 看攝取速率（samples/sec）
sum(rate(prometheus_tsdb_head_samples_appended_total[7d]))
```

**實測結果（7 個 Region 範例）：**

| Region | Active Series | Ingestion Rate |
|--------|:------------:|:--------------:|
| SG (ap-southeast-1) | 1,600,868 | 25,255 samples/sec |
| US (us-east-1) | 765,383 | 11,066 samples/sec |
| EU (eu-central-1) | 651,737 | 9,426 samples/sec |
| JP (ap-northeast-1) | 529,036 | 7,442 samples/sec |
| IN (ap-south-1) | 298,108 | 4,219 samples/sec |
| AU (ap-southeast-2) | 262,717 | 3,839 samples/sec |
| ZA (af-south-1) | 183,347 | 2,773 samples/sec |
| **7 Region 合計** | **~4.29M** | **~64,020 samples/sec** |
| **10 Region 估算** | **~4.9M** | **~75,000 samples/sec** |

> SG 的某個服務有基數爆炸問題（2,976,623 samples/scrape），是全體的 10 倍，另行追蹤。

原始假設是每 Region 50K series → **實際平均是 613K，誤差 12 倍**。這個數字讓 AMP 從「可考慮」直接變成「不可接受」。

---

## 網路前提：Transit Gateway

所有跨 Region 的 remote_write 流量走 **AWS Transit Gateway（TGW）**，不走公開網路。

- 費用：$0.02/GB（TGW attachment fee）
- 比走 NAT Gateway（$0.045/GB）便宜
- 流量不出 AWS 骨幹網路 — 延遲低、無公網曝露

---

## 五方案比較

| 方案 | 每月成本 | 維運負擔 | 結論 |
|------|:-------:|:-------:|:----:|
| A: Prometheus Federation | ~$215 | 低 | ❌ 只有 aggregated metrics |
| **B: VictoriaMetrics（自架）** | **~$555-575** | **中** | **✅ 選用** |
| C: Thanos（自架） | ~$427 | 高 | ❌ 複雜度不值得 |
| D: AMP + AMG（AWS 託管） | ~$8,460 | 極低 | ❌ 成本 15 倍 |
| E: SigNoz | ~$475+ | 高 | ❌ 無多 Region 方案 |

---

## 方案 A：Prometheus Federation ❌

```
Central Prometheus ──/federate──▶ Region 1 Prometheus
                   ──/federate──▶ Region 2 Prometheus
                   ...（輪詢，非 push）
```

Federation 只拉 **pre-aggregated** 數字，raw time series 留在各 Region。

```
各 Region 保留（Federation 拉不到）：
  api_request_total{code="500", path="/search", pod="svc-abc"} = 15
  api_request_total{code="500", path="/export", pod="svc-xyz"} = 27

Federation 中央只有：
  error_rate_5m{region="us-east-1"} = 0.43%   ← 預先算好的單一數字
```

**缺口：** 無法在中央做跨 Region raw data 查詢（「哪個 API path 在所有 Region 的 5xx 最多？」→ 答不了）。

| 項目 | 每月 |
|------|:----:|
| EC2（m5.xlarge） | ~$140 |
| EBS 500GB | ~$40 |
| Grafana（t3.medium） | ~$30 |
| 跨 Region 傳輸（極少） | ~$5 |
| **合計** | **~$215** |

---

## 方案 C：Thanos ❌

詳細分析見 [Thanos vs VictoriaMetrics 比較](./2-thanos-vs-victoriametrics)。

簡言之：
- Sidecar 模式需修改 10 個 Region 的 K8s manifest，與零中斷遷移策略衝突
- Receive 模式雖已 production-ready（v0.32+），但元件比 VM 更多
- 5 個元件 vs VictoriaMetrics 的 3 個
- 每月省 ~$128，但付出大幅增加的維運複雜度

---

## 方案 D：AMP + AMG ❌

```
每個 Region：Prometheus ──remote_write + SigV4──▶ AMP Workspace ──▶ AMG
```

**AMP 按攝取 sample 數收費（分層定價）：**

| 層級 | 計算 | 每月 |
|------|------|:----:|
| Tier 1（前 20 億 samples） | 20億 × $0.90/1000萬 | ~$180 |
| Tier 2（次 180 億） | 180億 × $0.72/1000萬 | ~$1,296 |
| Tier 3（剩餘 ~1,740 億） | 1740億 × $0.54/1000萬 | ~$9,396 |
| AMG 編輯者（5 人） | 5 × $9 | ~$45 |
| AMG 檢視者（15 人） | 15 × $5 | ~$75 |
| **合計** | | **~$8,460** |

**核心問題：AMP 的費用隨 series 量線性增長；VM 的費用由 EC2 規格決定，不隨 series 量增長。**

| 規模 | AMP | VictoriaMetrics | 差距 |
|------|:---:|:---------------:|:----:|
| 現況 ~75K samples/sec | ~$8,460 | ~$555 | **15x** |
| 清理後 ~57K | ~$7,136 | ~$555 | **13x** |
| 積極清理（每 Region 100K series） | ~$2,616 | ~$555 | **5x** |

即使積極降低基數，AMP 仍在 5 倍以上。

---

## 方案 E：SigNoz ❌

```
每個 Region：OTel Collector ──OTLP──▶ Central SigNoz（ClickHouse）
```

| 項目 | 每月 |
|------|:----:|
| ClickHouse 節點（3× r5.xlarge） | ~$330 |
| EBS 3× 500GB | ~$120 |
| 跨 Region 傳輸 | ~$25 |
| **合計** | **~$475+** |

**問題：**
- 官方文件只涵蓋單 Region，無成熟的多 Region 自架方案
- ClickHouse 在多 dashboard 同時載入時 CPU 飆升（已知 80%+）
- 社群版有 dashboard 數量上限、無 SSO
- SigNoz 的價值是 metrics+traces+logs 統一；只需要 metrics 的話，付出 ClickHouse 複雜度卻沒有回報

---

## 方案 B：VictoriaMetrics ✅

```
每個 Region（唯一改動：prometheus.yml 加 remote_write 3 行）:
  Prometheus ──remote_write──▶ vmauth（TLS + bearer token）
                                    │
                               vminsert ×2 (HA)
                                    │
                              vmstorage ×3 (replicationFactor=2)
                                    │
                              vmselect ×2 (HA)
                                    │
                           Central Grafana
```

| 項目 | 每月 |
|------|:----:|
| vminsert（2× c5.large） | ~$125 |
| vmselect（2× m5.large） | ~$140 |
| vmstorage（3× r5.large，16GB RAM） | ~$277 |
| EBS gp3（3× 500GB，90 天保留） | ~$120 |
| 跨 Region 傳輸（TGW） | ~$25 |
| **合計** | **~$555-575** |

**選用理由：**

| 面向 | 說明 |
|------|------|
| 遷移風險最低 | 每個 Region 只改 `prometheus.yml`，不動 manifest，不重啟 pod |
| 費用固定 | EC2 規格決定費用，不受 sample 量影響 |
| RAM 效率最佳 | 同基數下比 Prometheus/Thanos 省 7-10 倍 RAM |
| 元件最少 | 3 個（vminsert/vmselect/vmstorage）vs Thanos 的 5 個 |
| 無外部依賴 | 不需 S3、不需 Zookeeper |
| 內建基數探索器 | VMUI 幫助調查高基數爆炸問題 |
| 100% PromQL 相容 | 既有 query 和 alert 規則無需修改 |

---

## 遷移策略（零中斷）

```
1. 在驗證環境部署 VMCluster + vmauth + Central Grafana
2. 驗證環境 Prometheus 加 remote_write → 確認資料正確
3. 逐步將其他環境 Prometheus 加 remote_write → 逐一驗證
4. 各 Region 依序接入（基數最高的 Region 最後，先解決基數問題）
5. 保留各 Region 原有 Grafana 作為隨時可用的 rollback
```

---

## 關鍵教訓

1. **先量再估算** — 假設 50K series，實際 613K，估算誤差 12 倍
2. **託管服務隱藏的 per-sample 計費陷阱** — AMP 零維運代價是在大規模下成本爆炸
3. **遷移策略制約技術選型** — 若必須零中斷，Thanos Sidecar 模式就不適合
4. **跨 Region 傳輸費是雜音** — ~$25/月 vs ~$555/月 compute，不要過度優化
