---
sidebar_position: 3
---

# 集中式監控系統 — 技術提案

> **狀態：** 參考架構
> **使用情境：** 多 Region EKS 部署，各 Region 有獨立 Prometheus stack

---

## 目錄

1. [背景與問題描述](#1-背景與問題描述)
2. [目標與範圍](#2-目標與範圍)
3. [現有架構](#3-現有架構)
4. [方案比較](#4-方案比較)
5. [詳細比較](#5-詳細比較)
6. [成本估算](#6-成本估算)
7. [遷移策略](#7-遷移策略)
8. [建議](#8-建議)

---

## 1. 背景與問題描述

### 目前的痛點

| 問題 | 影響 |
| ---- | ---- |
| N 個 Region = N 個獨立 Grafana URL | 工程師必須切換多個 dashboard 才能看到全貌 |
| 無法跨 Region 關聯 | 無法在同一個畫面比較各 Region 的 metrics |
| Dashboard 維護重複 | 任何 dashboard 修改都必須在每個 Region 手動同步 |
| Alert 規則不一致 | 各 Region alert 規則可能逐漸偏離 |
| 維運負擔 | N 套獨立的 Prometheus + Grafana 需要維護與升級 |
| 無全局 SLA 視圖 | 難以彙整所有 Region 的 uptime / error rate |

### 情境描述

- 服務部署在 **AWS EKS** 的**多個 Region**
- 每個 Region 各有一套獨立的 **Prometheus + Grafana**
- 監控範圍：**K8s cluster metrics + 應用程式自訂 metrics**

---

## 2. 目標與範圍

### 目標

- **單一入口**：一個 Grafana URL 查看所有 Region
- **跨 Region 查詢**：可以在同一個畫面比較與關聯各 Region 的 metrics
- **統一 alert**：集中管理 alert 規則，支援 region-aware 路由
- **降低維運負擔**：減少需要維護的監控 stack 數量
- **Dashboard 一致性**：dashboard 定義的單一 source of truth

### 不在範圍內

- 替換應用程式層的 logging（ELK / CloudWatch Logs）
- 替換分散式 tracing（X-Ray / Jaeger）
- 修改應用程式的 metrics instrumentation 程式碼

---

## 3. Current Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Current State                            │
│                                                                 │
│  Region 1 (e.g. us-east-1)    Region 2 (e.g. eu-west-1)       │
│  ┌───────────────────┐        ┌───────────────────┐            │
│  │ EKS Cluster       │        │ EKS Cluster       │            │
│  │  ┌─────────────┐  │        │  ┌─────────────┐  │            │
│  │  │ Prometheus  │  │        │  │ Prometheus  │  │            │
│  │  └──────┬──────┘  │        │  └──────┬──────┘  │            │
│  │         │         │        │         │         │            │
│  │  ┌──────▼──────┐  │        │  ┌──────▼──────┐  │            │
│  │  │  Grafana    │  │        │  │  Grafana    │  │            │
│  │  │  URL #1     │  │        │  │  URL #2     │  │  ... ×N    │
│  │  └─────────────┘  │        │  └─────────────┘  │            │
│  └───────────────────┘        └───────────────────┘            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. 方案比較

### 方案 A：Prometheus Federation

**概念：** 各 Region 保留本地 Prometheus，部署一個中央「Global Prometheus」透過 `/federate` endpoint 拉取各 Region 的 aggregated metrics。

```
Region 1: Prometheus (local) ──┐
Region 2: Prometheus (local) ──┤  /federate (pull)
Region 3: Prometheus (local) ──┼─────────────────▶ Central Prometheus ──▶ Central Grafana
...                            │
Region N: Prometheus (local) ──┘
```

- 中央 Prometheus 透過 `federate` endpoint scrape 各 Region Prometheus
- 只拉取 selected/aggregated metrics，不是 raw data

---

### 方案 B：Remote Write + 自架 VictoriaMetrics

**概念：** 各 Region Prometheus 透過 `remote_write` 將所有 metrics 推送到中央部署的 VictoriaMetrics cluster。

```
Region 1: Prometheus ──remote_write──┐
Region 2: Prometheus ──remote_write──┤
Region 3: Prometheus ──remote_write──┼──▶ VictoriaMetrics ──▶ Central Grafana
...                                  │    (Central EKS)
Region N: Prometheus ──remote_write──┘
```

**VictoriaMetrics Cluster 元件：**
- `vminsert` — 接收 remote_write 資料
- `vmstorage` — 將 time-series 資料持久化到 EBS
- `vmselect` — 處理來自 Grafana 的 PromQL 查詢

---

### 方案 C：Remote Write + 自架 Thanos

**概念：** 各 Region Prometheus 掛載 Thanos Sidecar，中央 Thanos Query 對所有 Region 做 fan-out 查詢，長期儲存使用 S3。

```
Region 1: Prometheus + Thanos Sidecar ──┐
Region 2: Prometheus + Thanos Sidecar ──┤  gRPC StoreAPI
Region 3: Prometheus + Thanos Sidecar ──┼──────────────▶ Thanos Query ──▶ Central Grafana
...                                     │
Region N: Prometheus + Thanos Sidecar ──┘
                                              ▲
                                              │
                                        Thanos Store ◀── S3 (長期儲存)
                                        Thanos Compact
```

**Thanos 元件：**
- `Sidecar` — 掛在各 Region Prometheus 旁，上傳 blocks 到 S3
- `Query` — 中央元件，向所有 Sidecar 和 Store fan-out 查詢
- `Store` — 從 S3 提供歷史資料
- `Compact` — 壓縮和降採樣 S3 資料

---

### 方案 D：AWS 全託管（AMP + AMG）

**概念：** 使用 AWS 原生託管服務。各 Region Prometheus 透過 `remote_write` + SigV4 認證推送到 Amazon Managed Prometheus（AMP）。

```
Region 1: Prometheus ──remote_write + SigV4──┐
Region 2: Prometheus ──remote_write + SigV4──┤
Region 3: Prometheus ──remote_write + SigV4──┼──▶ AMP Workspace ──▶ AMG Workspace
...                                          │   (central region)    (central region)
Region N: Prometheus ──remote_write + SigV4──┘
```

- **AMP** — 全託管，基於 Cortex/Mimir 的 TSDB
- **AMG** — 全託管 Grafana，原生整合 IAM/SSO

---

## 5. 詳細比較

### 5.1 架構設計

| 評估項目 | A: Federation | B: VictoriaMetrics | C: Thanos | D: AMP + AMG |
|----------|:---:|:---:|:---:|:---:|
| 資料流方向 | Pull（中央拉） | Push（Region 推） | Hybrid | Push（Region 推） |
| 中央有完整 raw metrics | 否（僅 aggregated） | 是 | 是 | 是 |
| 單點失敗 | 中央 Prom | 中央 VM cluster | Thanos Query | AWS 託管（內建 HA） |
| 多租戶支援 | 手動（relabeling） | 原生支援 | 有限 | 原生支援 |

### 5.2 維運複雜度

| 評估項目 | A: Federation | B: VictoriaMetrics | C: Thanos | D: AMP + AMG |
|----------|:---:|:---:|:---:|:---:|
| 中央需部署元件數 | 1 | 3 (vminsert/select/storage) | 4+ | 0（託管） |
| 各 Region 需修改 | 無 | 無（加 remote_write config） | 需加 Sidecar | 無（加 remote_write config） |
| 升級複雜度 | 低 | 中 | 高 | 無（AWS 負責） |
| **整體維運負擔** | **低** | **中** | **高** | **極低** |

### 5.3 效能與擴展性

| 評估項目 | A: Federation | B: VictoriaMetrics | C: Thanos | D: AMP + AMG |
|----------|:---:|:---:|:---:|:---:|
| 資料壓縮率 | 1x | 7-10x vs Prometheus | 2-4x | N/A（託管） |
| 最大保留期 | 受限於磁碟 | 受限於 EBS | 無限（S3） | 預設 150 天，最長 1095 天 |

---

## 6. 成本估算

### 假設條件

| 參數 | 值 | 說明 |
|------|----|------|
| Region 數量 | 10（範例） | 依實際部署調整 |
| 每 Region 平均 active time series | 50,000 | 用 `prometheus_tsdb_head_series` 確認 |
| Scrape interval | 30 秒 | Prometheus 標準預設 |
| 每月時數 | 744 | 31 天 |
| 資料保留期 | 90 天 | |

### 推算數量

```
每 Region 每月 samples = 50,000 × (3600/30) × 744 = 44.6 億
10 個 Region 合計 = 446 億 samples/月
```

> 在自己的 Prometheus 執行 `count({__name__=~".+"})` 確認實際數字。

### 成本比較摘要

| 方案 | 每月估算 | 每年 | 維運負擔 |
|------|:--------:|:----:|:-------:|
| A: Federation | ~$220 | ~$2,640 | 低 |
| B: VictoriaMetrics | ~$610 | ~$7,320 | 中 |
| C: Thanos | ~$442 | ~$5,304 | 高 |
| D: AMP + AMG | ~$614 | ~$7,368 | 極低 |

> 以上估算基於每 Region 50K active series，實際數字請用 [AWS Pricing Calculator](https://calculator.aws) 重新計算。

---

## 7. 遷移策略

### 第一階段：平行運行（第 1-2 週）

1. 在一個 Region 部署選定的中央方案
2. 設定**一個 Region** 的 Prometheus `remote_write` 到中央 TSDB
3. 保留既有本地 Prometheus + Grafana（不中斷服務）
4. 驗證資料一致性：比較本地與中央的 metrics

### 第二階段：逐步推廣（第 3-4 週）

1. 逐一將其餘 Region 加入 `remote_write`
2. 將 dashboard 遷移到中央 Grafana
3. 設定集中式 alert 規則
4. 為每個 Region 加上 `external_labels`：
   ```yaml
   global:
     external_labels:
       region: "ap-southeast-1"
       cluster: "prod"
       environment: "production"
   ```

### 第三階段：驗證與切換（第 5-6 週）

1. 兩套系統平行運行至少 1-2 週
2. 確認所有 dashboard、alert、查詢都正常
3. 將團隊導向使用中央 Grafana URL
4. 下線各 Region Grafana（保留本地 Prometheus）

### 回滾方案

- 本地 Prometheus 永遠不刪除
- 若中央方案出問題，直接切回各 Region 的 Grafana URL
- 不會有資料遺失風險

---

## 8. 建議

### 決策矩陣（加權評分）

| 評估項目（權重） | A: Federation | B: VictoriaMetrics | C: Thanos | D: AMP + AMG |
|---|:---:|:---:|:---:|:---:|
| 維運簡單度（30%） | 8 | 6 | 4 | **10** |
| 中央有完整資料（20%） | 3 | **10** | **10** | **10** |
| 成本效益（15%） | **10** | 6 | 7 | 6 |
| AWS 生態整合（15%） | 3 | 4 | 5 | **10** |
| 擴展性（10%） | 3 | 9 | 8 | **10** |
| 可靠性 / HA（10%） | 5 | 7 | 8 | **10** |
| **加權總分** | **5.6** | **7.0** | **6.6** | **9.3** |

### 主要建議：方案 D — AMP + AMG

1. **零維運負擔**：AWS 全管 HA、擴展、升級、安全修補。
2. **AWS 原生整合**：SigV4、IAM/IRSA、VPC PrivateLink、SSO。
3. **規模驗證**：AMP 基於 Cortex/Mimir。
4. **最快上線**：每個 Region 只需加一段 `remote_write` config。

### 備選方案：方案 B — VictoriaMetrics

適合改選的情況：
- 每 Region active time series 超過 200K（AMP 費用暴增）
- 資料保留需求超過 AMP 上限 1095 天
- 團隊希望完全掌控監控後端

---

## 參考資料

- [Amazon Managed Prometheus — 定價](https://aws.amazon.com/prometheus/pricing/)
- [Amazon Managed Grafana — 定價](https://aws.amazon.com/grafana/pricing/)
- [VictoriaMetrics — Cluster 文件](https://docs.victoriametrics.com/victoriametrics/cluster-victoriametrics/)
- [Thanos vs VictoriaMetrics 比較（Last9）](https://last9.io/blog/thanos-vs-victoriametrics/)
