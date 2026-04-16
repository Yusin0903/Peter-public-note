---
sidebar_position: 5
---

# Decision Record: 為什麼不採用 SigNoz（目前階段）

> **結論：** 目前不採用，未來可重新評估
> **替代方案：** Grafana Stack（VictoriaMetrics + Grafana，之後可加 Loki + Tempo）

---

## 方案概述

SigNoz 是開源的全棧 Observability 平台（metrics + traces + logs），以 OpenTelemetry 為核心、ClickHouse 為統一資料庫。各 region 部署 OTel Collector push 資料到中央 SigNoz。

```
Region 1: OTel Collector ──OTLP push──┐
Region 2: OTel Collector ──OTLP push──┤
...                                   ├──> 中央 SigNoz (ClickHouse) ──> 內建 UI
Region N: OTel Collector ──OTLP push──┘
```

## 優點（為什麼曾經考慮）

| 優點 | 說明 |
|------|------|
| 全棧 Observability | 一個平台涵蓋 metrics + traces + logs，不需要拼裝多個工具 |
| 統一資料庫 | 全部存在 ClickHouse，信號之間可以做原生 join（metric → trace → log） |
| OpenTelemetry 原生 | 架構核心就是 OTel，trace-to-log、log-to-metric 的關聯比 Grafana Stack 更可靠 |
| 元件少 | 只需管 SigNoz + ClickHouse，比 Grafana Stack 的 4+ 元件少 |
| 內建 UI | 不需要額外部署 Grafana |
| 開源免費 | 社群版無授權費 |

## 不採用的原因

### 1. 跨 Region 沒有成熟方案（核心需求不滿足）

目標是「一個 dashboard 看所有 region」。

| | VictoriaMetrics | SigNoz |
|---|---|---|
| 跨 region 方案 | 官方文件、best practice、生產案例都有 | **沒有原生 federation，官方文件只講 Cloud 版** |
| Multi-region 部署 | `vmagent` remote_write → 中央 VM cluster（成熟模式） | 要自己設計 OTel Collector → 中央 SigNoz pipeline |
| 參考資料 | 豐富 | **幾乎沒有 self-hosted multi-region 的案例** |

這代表要自己設計、自己踩坑、自己解決問題，風險太高。

### 2. ClickHouse 運維門檻高

| 坑 | 影響 |
|---|---|
| **Zookeeper 依賴** | 即使單節點也要裝 Zookeeper（JVM，吃記憶體），官方建議改用 ClickHouse Keeper 但需自己配 |
| **CPU 暴衝** | 使用者回報打開 8-9 個 dashboard chart 時 CPU 飆到 80% |
| **內部 log 暴長** | ClickHouse 預設診斷日誌可長到 70GB+，要手動設定 TTL |
| **CPU 架構相容** | ClickHouse 24.1+ 需要 AVX2 指令集，部分 EC2 instance type 不支援 |
| **「監控的監控」** | SigNoz 自己掛了怎麼知道？需要另一套 ClickHouse 來監控 SigNoz 本身 |

相比之下，VictoriaMetrics 是單一 Go binary、無外部依賴、自帶 TSDB，運維複雜度低很多。

### 3. 社群版功能限制

| 功能 | 社群版（免費） | 企業版（付費） |
|------|:---:|:---:|
| Dashboard 數量 | **有限制** | 無限 |
| Traces/Logs panels | **有限制** | 無限 |
| SSO / SAML | 無 | 有 |
| 多租戶 | 無 | 有 |

Dashboard 數量限制對多 region × 多個 domain 的場景可能會很快觸頂。

### 4. 生態系不夠成熟

| 維度 | Grafana Stack | SigNoz |
|------|:---:|:---:|
| 社群大小 | 極大 | 小 |
| Plugin 生態 | 上千個 | 封閉 UI，無 plugin |
| 生產案例 | 非常多 | 較少 |
| 遇到問題能找到的參考 | 多 | **少** |
| PromQL 相容性 | 100% | 部分，可能踩雷 |

### 5. 遷移成本仍然存在

| 額外成本 | 說明 |
|----------|------|
| 學 ClickHouse SQL | 團隊要學新的查詢語言 |
| 學 SigNoz UI | 不能沿用任何 Grafana 經驗 |
| OTel Collector 部署 | 每個 region 要部署和維護 OTel Collector pipeline |
| 部署文件混亂 | Reddit 使用者反映部署腳本跟 docker-compose 混用，不清楚怎麼正確設定 |

## 結論

SigNoz 的理念很好（統一平台、OTel 原生、信號關聯），但目前階段不適合：

1. **跨 region 方案不成熟** — 核心需求無法滿足
2. **ClickHouse 運維門檻高** — 團隊資源有限
3. **社群版功能限制** — 可能不夠用
4. **生態系和參考資料不足** — 踩坑時缺少支援

選擇 Grafana Stack 可以先用 VictoriaMetrics + Grafana 解決 metrics 集中化，之後按需求逐步加入 Loki（logs）和 Tempo（traces），每一步都有成熟方案和大量參考。

## 什麼情況下可以重新考慮

- SigNoz 推出原生的 multi-region federation 方案
- SigNoz 社群版取消 dashboard 數量限制
- 團隊有專人可以投入 ClickHouse 維運
- 確定需要 metrics + traces + logs 的深度關聯，且 Grafana Stack 的 UI 層拼接無法滿足
- SigNoz 的生產案例和社群規模明顯成長

## 參考資料

- [SigNoz GitHub](https://github.com/SigNoz/signoz)
- [SigNoz vs Grafana - In Depth Comparison](https://signoz.io/product-comparison/signoz-vs-grafana/)
- [SigNoz - ClickHouse Cluster Issue #8784](https://github.com/SigNoz/signoz/issues/8784)
- [SigNoz - Zookeeper vs ClickHouse Keeper Issue #7002](https://github.com/SigNoz/signoz/issues/7002)
- [SigNoz vs The Stack (Medium)](https://medium.com/@PlanB./signoz-vs-the-stack-can-it-really-replace-prometheus-grafana-and-loki-79814196f1b8)
