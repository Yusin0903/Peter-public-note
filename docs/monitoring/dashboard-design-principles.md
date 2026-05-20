---
tags: [monitoring, sre, grafana, dashboard]
updated: 2026-05-06
---

# Dashboard Design Principles for User-Facing Apps

設計監控 dashboard 的通用原則：先 CUJ（使用者體驗）再往下 drill。
依賴系統（DB / storage）可以例外，從 K8s health 出發。

## 為什麼先 CUJ？

對應 Google SRE 的 Golden Signals：Latency、Traffic、Errors、Saturation。
前 3 個剛好對應 API latency、request rate、5xx rate；saturation
則放到資源層（CPU/memory/queue/storage）。

- **Golden Signals** ([Google SRE Book](https://sre.google/sre-book/monitoring-distributed-systems/))
- **RED method**: Rate / Errors / Duration — 適合 request-driven service
- **USE method**: Utilization / Saturation / Errors — 適合資源層
  ([RED vs USE on betterstack](https://betterstack.com/community/guides/monitoring/red-use-metrics/))
- **Grafana 官方**建議 dashboard 用清楚結構、變數和可維護的 panel 組織
  ([Grafana best practices](https://grafana.com/docs/grafana/latest/visualizations/dashboards/build-dashboards/best-practices/))

## 5-Row Dashboard 骨架

每個 user-facing app dashboard 用同一個骨架，方便 on-call 形成肌肉記憶。

### Header / Filters

變數應該設計成可組合查詢，避免直接用 raw path 當主維度（cardinality 太高）：

- `$region`, `$environment`, `$namespace`
- `$service` 或 `$app`
- `$route_group`（path 太多時，先分組再用）

### Row 1 — CUJ / User Experience

**問題：使用者現在有沒有成功？**

- API 5xx rate
- p95 / p99 latency
- request rate
- async CUJ：worker success rate、last success age、oldest queue age
- data freshness：last successful sync/update age

### Row 2 — Traffic / Loading

**問題：是不是流量或 workload 造成的？**

- request rate by region
- top API paths by traffic / by 4xx5xx
- in-flight requests
- queue depth / oldest age

### Row 3 — App Resource

**問題：app process 本身是否吃滿？**

- pod CPU / memory working set
- runtime heap（Node.js heap、Python RSS、JVM heap）
- event loop lag（若 runtime 提供）
- container restart trend

### Row 4 — AWS / K8s Health

**問題：runtime 有沒有壞？**

- non-running / failed / pending pods
- restart count、OOMKilled / Error termination reason
- desired vs available replicas
- node pressure（memory / disk）

### Row 5 — Storage / Capacity

**問題：容量會不會造成故障？**

- PVC usage % / free bytes
- disk growth trend
- backup last success age
- object missing count / external storage error

## Dependency 系統的例外

Database / storage / shared infra 不適合硬套「CUJ 第一層」骨架，
因為它們不是直接 user journey。第一版可以從 K8s health + storage 出發：

1. **Overview**: pod failed/pending、restart、CPU/memory、PVC usage、backup age
2. **Debug**: per-component pod phase、per-pod CPU/memory、PVC by claim、termination reason
3. **Backlog / Future CUJ**: 等到有 app-level metrics（成功率、latency histogram、
   synthetic read/write check）才能從「DB 健康」進化到「app 真的能用 DB」。

> 這樣比較誠實：能監控 storage health，不代表能保證 app operation 成功。

## 命名 convention

Dashboard 名稱可以反映層級：

- `<Org> App - <App Name> - CUJ Health`
- `<Org> Dependency - <System> - K8s and Storage Health`
- `<Org> Platform - <Infra> - Cluster Health`
