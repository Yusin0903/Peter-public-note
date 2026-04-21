---
sidebar_position: 4
---

# 集中式監控系統 — 成本分析

> **狀態：** 參考分析
> **相關文件：** [技術提案](./centralized-monitoring-proposal)

---

## 摘要

評估 4 種方案，將 N 個獨立 Region 的 Prometheus + Grafana 集中到單一統一 dashboard。

| 方案 | 每月成本 | 每年成本 | 維運負擔 | 建議 |
| ---- | :------: | :------: | :------: | ---- |
| A: Prometheus Federation | ~$220 | ~$2,640 | 低 | 不建議（能力有限） |
| B: VictoriaMetrics（自架） | ~$610 | ~$7,320 | 中 | 備選方案 |
| C: Thanos（自架） | ~$442 | ~$5,304 | 高 | 不建議（複雜度高） |
| **D: AMP + AMG（AWS 託管）** | **~$614** | **~$7,368** | **極低** | **建議** |

**結論：** 方案 D（AWS 託管）成本與自架 VictoriaMetrics 幾乎相同（~$614 vs ~$610/月），但免去所有基礎設施維護負擔。自架方案的隱藏成本是工程師花在維運、升級、on-call 的時間，這部分不反映在金額上。

> 以上估算基於 **10 Regions × 每 Region 50K active series × 30s scrape interval**。
> 實際數字請用 [AWS Pricing Calculator](https://calculator.aws) 重新計算。

---

## 1. 基準假設

> 在任一 Region 的 Prometheus 執行 `count({__name__=~".+"})` 確認實際數字。

| 參數 | 值 | 說明 |
|------|----|------|
| Region 數量 | 10 | 範例值 |
| 每 Region Active time series | 50,000 | 保守估計（K8s + app metrics） |
| Scrape interval | 30 秒 | Prometheus 標準預設 |
| 每月時數 | 744 | 31 天 |
| 資料保留期 | 90 天 | |
| Dashboard 編輯者 | 5 人 | 建立/編輯 dashboard 的工程師 |
| Dashboard 檢視者 | 15 人 | 唯讀權限的工程師 |

### 推算攝取量

```
每 Region 每月 samples：
  = 50,000 series × 120 scrapes/hr × 744 hr/月
  = 44.6 億 samples/Region/月

10 個 Region 合計：
  = 446 億 samples/月
```

---

## 2. 各方案成本明細

### 方案 A：Prometheus Federation — $220/月

| 項目 | 規格 | 每月（USD） |
|------|------|:-----------:|
| 中央 Prometheus（EC2） | m5.xlarge（4 vCPU, 16 GB） | $140 |
| EBS 儲存（gp3） | 500 GB | $40 |
| 中央 Grafana（EC2） | t3.medium | $30 |
| 跨 Region 資料傳輸 | 極少（aggregated only） | $10 |
| **合計** | | **$220** |

**最便宜的原因：** 只拉取 aggregated metrics，不是 raw data。
**代價：** 無法對 raw metrics 做完整的跨 Region 分析。

---

### 方案 B：VictoriaMetrics（自架）— $610/月

| 項目 | 規格 | 每月（USD） |
|------|------|:-----------:|
| vminsert（EC2） | 2× c5.large（HA） | $125 |
| vmselect（EC2） | 2× m5.large（HA） | $140 |
| vmstorage（EC2） | 2× r5.large（16 GB RAM, HA） | $185 |
| EBS 儲存（gp3） | 2× 500 GB（HA, 90 天保留） | $80 |
| 中央 Grafana（EC2/EKS） | t3.medium | $30 |
| 跨 Region 資料傳輸 | remote_write ~89 GB/月 | $50 |
| **合計** | | **$610** |

**未計入的隱藏成本：**
- 工程師時間：每月約 2-4 小時（升級、監控、除錯）
- VictoriaMetrics cluster 問題的 on-call 覆蓋
- 隨 metrics 量成長的容量規劃

---

### 方案 C：Thanos（自架）— $442/月

| 項目 | 規格 | 每月（USD） |
|------|------|:-----------:|
| Thanos Query（EC2） | 2× m5.large（HA） | $140 |
| Thanos Store Gateway（EC2） | 2× m5.large | $140 |
| Thanos Compactor（EC2） | 1× m5.large | $70 |
| S3 儲存 | ~500 GB 壓縮後（90 天） | $12 |
| S3 API 請求 | PUT/GET blocks | $20 |
| Thanos Sidecar（per region） | 與 Prometheus pod 共用 | $0 |
| 中央 Grafana（EC2/EKS） | t3.medium | $30 |
| 跨 Region 資料傳輸 | gRPC query fan-out | $30 |
| **合計** | | **$442** |

**未計入的隱藏成本：**
- 工程師時間：每月約 4-8 小時（4+ 個元件需管理）
- Thanos 架構的學習曲線陡峭

---

### 方案 D：AMP + AMG（AWS 託管）— $614/月

| 項目 | 計算 | 每月（USD） |
| ---- | ---- | :---------: |
| **AMP 攝取** | | |
| - Tier 1（前 20 億 samples） | 20億 × $0.90/1000萬 | $180 |
| - Tier 2（後約 426 億 samples） | ~426億 × $0.72/1000萬（估） | $307 |
| **AMP 儲存** | ~200 GB × $0.03/GB | $6 |
| **AMP 查詢（QSP）** | ~100億 samples × $0.10/10億 | $1 |
| **AMG 編輯者** | 5 人 × $9/人 | $45 |
| **AMG 檢視者** | 15 人 × $5/人 | $75 |
| 跨 Region 資料傳輸 | AMP DT-IN 免費 | $0 |
| **合計** | | **$614** |

**已包含（無隱藏成本）：**
- HA / 多 AZ 備援
- 自動擴展
- 升級與安全修補
- 預設 150 天保留（最長可設 1095 天）
- IAM/SSO 整合
- 99.9% SLA

---

## 3. 總持有成本（TCO）— 一年視角

### 含估算維運成本（工程師時數）

假設工程師成本 $50/hr（內部成本分攤）：

| 方案 | 基礎設施/年 | 維運時數/月 | 維運成本/年 | **TCO/年** |
|------|:-----------:|:-----------:|:-----------:|:----------:|
| A: Federation | $2,640 | 1-2 hr | $1,200 | **$3,840** |
| C: Thanos | $5,304 | 4-8 hr | $3,600 | **$8,904** |
| B: VictoriaMetrics | $7,320 | 2-4 hr | $1,800 | **$9,120** |
| D: AMP + AMG | $7,368 | 0.5-1 hr | $450 | **$7,818** |

> 計入維運成本後，**方案 D 比方案 B 更划算**，
> 儘管基礎設施費用較高。隨著團隊規模增長，差距會拉大。

---

## 4. 成本敏感度分析

### 每 Region Active Series 不同時的影響

| Active Series / Region | 方案 B（VM） | 方案 D（AMP） | AMP vs VM |
|:---:|:---:|:---:|:---:|
| 20,000（低） | ~$450/月 | ~$280/月 | AMP 更便宜 |
| 50,000（基準） | ~$610/月 | ~$614/月 | 幾乎相同 |
| 100,000 | ~$750/月 | ~$1,100/月 | AMP 貴 47% |
| 200,000 | ~$950/月 | ~$2,050/月 | AMP 貴 116% |
| 500,000+ | ~$1,200/月 | ~$4,800/月 | AMP 貴 300% |

**關鍵洞察：** AMP 在每 Region ~50K series 時具有成本競爭力。
若實際 metrics 量顯著更高（200K+），VictoriaMetrics 更划算。

### Scrape Interval 變化的影響

| Scrape Interval | 每月 Samples（10 Regions） | 方案 D 成本 |
|:---:|:---:|:---:|
| 15 秒 | 893 億 | ~$1,100/月 |
| **30 秒** | **446 億** | **~$614/月** |
| 60 秒 | 223 億 | ~$340/月 |

> Scrape interval 加倍，AMP 攝取成本減半。
> 這是降低 AMP 成本最有效的槓桿。

---

## 5. 方案 D 的成本優化策略

| 策略 | 難度 | 節省幅度 |
|------|:----:|:-------:|
| Scrape interval 從 30s 調為 60s | 低 | 攝取成本降約 50% |
| 用 `metric_relabel_configs` 丟棄不用的 metrics | 中 | 降低 10-30% |
| 用 recording rules 預先彙總常查詢的 aggregation | 中 | 降低 QSP 費用 |
| 設定適當的保留期 | 低 | 降低儲存費用 |

範例 `metric_relabel_configs`，丟棄高基數但不需要的 metrics：
```yaml
metric_relabel_configs:
  - source_labels: [__name__]
    regex: 'go_.*|promhttp_.*'  # 丟棄 Go runtime / Prometheus internal metrics
    action: drop
```

---

## 附錄：定價來源

- [AMP 定價](https://aws.amazon.com/prometheus/pricing/)
- [AMG 定價](https://aws.amazon.com/grafana/pricing/)
- [AMP 成本優化指南](https://docs.aws.amazon.com/prometheus/latest/userguide/AMP-costs.html)
- [AWS Pricing Calculator](https://calculator.aws)
