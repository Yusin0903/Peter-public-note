---
tags: [monitoring, sre, grafana, dashboard, on-call, alerting, golden-signals]
created: 2026-05-06
updated: 2026-05-06
---
# Alert-Driven Dashboard Philosophy

對照 Google SRE 的設計理念。Dashboard 不是用來「常駐盯盤」的，而是 **alert
觸發後的 triage surface** ——目的是讓 on-call 在 30 秒內找到問題位置與影響範圍。

> 設計順序：**先 alert → 進 dashboard 看 → 資訊要能立刻找到問題**

---

## 一、設計三原則

| 原則 | 說明 |
|---|---|
| 1. Alert first | Dashboard 的入口是 alert，不是「打開來看」。所以 dashboard 第一眼必須回答「在燒嗎？燒在哪？」|
| 2. Triage on entry | Alert 進來後第一層必須是紅綠燈式總覽；下一層才是 drill-down |
| 3. Fast comprehension | 第一層的訊號越少越獨立越好；第二層只在「真的有問題」時呈現資訊 |

---

## 二、第一層 stat row 的設計

### 2.1 訊號必須**互相獨立** (orthogonal)

第一排每個 stat 應該回答**不同類別**的問題。如果兩個 stat 訊號高度相關，
那其中一個就是 noise，不該佔黃金位置。

| 問題類別 | Stat |
|---|---|
| 服務還在嗎？ | Service Up / Ready Replicas Ratio |
| 服務在發錯嗎？ | Error Rate (5xx) |
| 服務慢嗎？ | Latency p95, p99 |
| 有人用嗎 / 流量正常嗎？ | Traffic vs Baseline (今天 vs 一小時前 / 一週前) |

### 2.2 訊號要**雙向警報**

例如 traffic：

- 流量太低 → 可能 ingress / DNS / 上游壞了（5xx 抓不到，因為「沒有請求 = 沒錯誤」）
- 流量太高 → 可能 retry storm / bot / loop bug（latency 抓得到但較慢）

只看「太高」是 capacity dashboard 的設計，**不是 alert→triage dashboard 的設計**。
on-call 入口面板寧可保守警報，誤報 1 次比漏看 1 次重要。

### 2.3 Service Up 必須**獨立**於 5xx / latency

當服務全 down 時：
- Error rate = 0%（沒請求 = 沒錯誤）
- Latency = N/A（沒資料）
- **只有 Service Up 能告訴你「真的全壞了」**

這個 case 是 alert→triage dashboard 最常被忽略的盲區。

---

## 三、第二層的設計：「沒事就空白」

第一層回答「在燒嗎」，第二層必須回答「燒在哪」。**第二層的 panel 在沒問題時應該完全空白。**

| 第二層需求 | 推薦 panel 類型 |
|---|---|
| 列出有問題的東西 | **Instant table + PromQL `> 0` 過濾 + cell coloring** |
| 看趨勢、看相關性 | timeseries + `topk(N) > 0` |
| 摘要紅綠燈 | stat（series 不會多） |

### 3.1 為什麼用 instant table 而不是 stat panel 列問題？

**Stat panel 多 series 會爆**：10 region × 3 個壞 pod = 30 個小格子，
字小到看不清，全部紅燈反而失去資訊。

**Table 才是業界正解**（Kubernetes Dashboard、k9s、ArgoCD 都用 table）：
- 每個問題一行
- 排序可控
- 用 cell coloring 表示嚴重度
- PromQL 端先 `> 0` 過濾、empty 時整張表空白

### 3.2 為什麼不放原始 path / per-instance 訊號在第一層？

`path`、`pod`、`instance` 這類 label 是**高 cardinality**：
- 每個 URL / pod 一條 series → query 成本高、legend 雜亂
- 低流量 path 的 p99 容易抖動且誤導

正確分層：
- **第一層 stat / alert**：用 aggregated 訊號（`route_group`, deployment）
- **第二層 drill-down**：才看 raw `path`, raw `pod`

---

## 四、跟 Google SRE 的對照

### 4.1 對齊的部分

#### Four Golden Signals
([SRE Book ch.6 — Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/))

> "If you can only measure four metrics of your user-facing system, focus on
> these: **latency, traffic, errors, saturation**."

對應一般 alert→triage dashboard：

| Google Golden Signal | 一般做法                            |
| -------------------- | ------------------------------- |
| Latency              | p95 / p99 stat                  |
| Traffic              | Traffic vs Baseline stat（雙向）    |
| Errors               | Error Rate stat                 |
| Saturation           | CPU/memory utilization vs limit |

#### Alert-driven workflow
([SRE Workbook ch.5 — Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/))

> "Good SLOs that measure the reliability of your platform, as experienced
> by your customers, provide the highest-quality indication for when an
> on-call engineer should respond."

→ Dashboard 是 alert 的延伸，不是反過來。

#### Noise reduction
([SRE Book ch.6](https://sre.google/sre-book/monitoring-distributed-systems/))

> "Effective alerting systems have **good signal and very low noise**."

→ 「沒事就空白」 = 把 noise 在 query 層就過濾掉。

#### Progressive disclosure
([Grafana Best Practices](https://grafana.com/docs/grafana/latest/visualizations/dashboards/build-dashboards/best-practices/))

> "Lead with high-level SLO charts and drill down to per-service,
> per-endpoint, per-pod details."

→ Row 結構：CUJ → Traffic / Loading → App Resource → Service Health。

### 4.2 比 Google SRE 更實務的部分

#### Traffic 雙向警報

Google Golden Signals 的 Traffic 主要描述為 "a measure of demand"，
**沒明確強調「low traffic = bad」**。

但實務上：
- Service 全 down → traffic = 0 → error rate = 0 → 看似綠燈
- Ingress / DNS / cert 壞 → traffic 突降，但 Service Up 可能還是 100%

→ Traffic 必須**雙向警報**（過低過高都警報），這是 alert→triage 場景的剛需。
Datadog、Netflix、大型電商也是雙向警報。

#### Missing Signals 顯式化

把 dashboard **涵蓋不到的 CUJ** 用一個 row 標出來（"Missing CUJ Signals /
Instrumentation Backlog"），避免「綠燈 = 一切正常」的錯覺。

業界叫 "known unknowns visible in dashboard"，符合 SRE 精神
([SRE Workbook ch.4 — Implementing SLOs](https://sre.google/workbook/implementing-slos/))
但不在 Google book 範例裡。

#### 用 instant table 取代 stat panel 列問題

Google book 沒講具體呈現選擇。實務上 stat panel 列 N 個問題會擠爆，
table 才是正解。這是 **operational experience > book example** 的地方。

### 4.3 Saturation 的細節

Google 的 Saturation 定義：

> "**A measure of your system fraction**, emphasizing the resources that are
> most constrained."

關鍵是「**有上限的資源使用率**」 —— 必須要有「容量」當分母：

| 訊號 | 是不是真的 Saturation |
|---|---|
| In-flight requests（瞬時計數）| ❌ 沒有上限分母，是 Traffic × Latency 衍生（Little's Law）|
| In-flight / max_concurrent | ✅ 有分母 |
| CPU usage / CPU limit | ✅ |
| Memory working set / memory limit | ✅ |
| Connection pool used / max | ✅ |
| Queue depth / max queue size | ✅ |

**常見錯誤**：把 in-flight requests 當成 saturation 訊號。
它只是 traffic 與 latency 的乘積（Little's Law: `in-flight = arrival_rate × latency`），
跟 latency 同向變動，沒有獨立資訊。

**正確做法**：
- 真正的 Saturation 訊號要有「容量分母」
- HPA + stateless 場景下，CPU saturation 較不關鍵（HPA 會自動 scale）
- Stateful / connection-pool / queue 場景下，Saturation 必須放第一層

---

## 五、Dashboard 還沒做但 Google SRE 強調的進階項

對照 Google SRE 與 Grafana 官方文件，下列項目通常需要分階段實作：

### Burn-rate alert / SLO-based alert
([SRE Workbook ch.5](https://sre.google/workbook/alerting-on-slos/))

Google 推薦 multiwindow, multi-burn-rate alerts：

> "Fast burn (2% budget consumed in 1 hour) means page immediately;
> Slow burn (5% budget consumed in 6 hours) means ticket for investigation."

→ 比靜態 threshold 更精準。需要先把 SLO 定下來。

### Runbook link
([Grafana Best Practices](https://grafana.com/docs/grafana/latest/visualizations/dashboards/build-dashboards/best-practices/))

每個 stat panel 加 `links` 欄位 → on-call 點 stat 直接跳 runbook。

### SLO panel
顯示「目前 error budget 剩多少」，通常 horizontal bar 加在 CUJ row 上方。

---

## 六、總結

| 維度 | 對照結果 |
|---|---|
| Four Golden Signals 覆蓋 | 與 Google 對齊；Saturation 視場景決定放第一層或 drill-down |
| Alert-driven triage 工作流 | 完全對齊 SRE Workbook ch.5 哲學 |
| Empty-state / noise reduction | 對齊 SRE Book ch.6；實務上比 Grafana 預設模板更徹底 |
| Progressive disclosure | 對齊 Grafana 官方 best practices |
| Traffic 雙向警報 | 比 Google book 範例更貼近真實 on-call 場景 |
| Missing Signals 顯式化 | 超出 Google book 範圍但符合 SRE 精神 |
| SLO + Error Budget | 多數團隊在 alerting 階段才補上 |
| Runbook link | 容易補但常被遺漏 |

**結論**：核心理念跟 Google SRE Workbook + RED Method + Grafana 官方
best practices 幾乎完全對齊。差異點主要在「實務取捨」，不是「方向錯誤」。

---

## Sources

- [Google SRE — Monitoring Distributed Systems (Four Golden Signals)](https://sre.google/sre-book/monitoring-distributed-systems/)
- [Google SRE Workbook — Alerting on SLOs (ch.5)](https://sre.google/workbook/alerting-on-slos/)
- [Google SRE Workbook — Implementing SLOs (ch.4)](https://sre.google/workbook/implementing-slos/)
- [Google SRE Workbook — Monitoring Systems with Advanced Analytics](https://sre.google/workbook/monitoring/)
- [Grafana Dashboard Best Practices](https://grafana.com/docs/grafana/latest/visualizations/dashboards/build-dashboards/best-practices/)
- [Better Stack — RED vs USE Metrics](https://betterstack.com/community/guides/monitoring/red-use-metrics/)
- [PagerTree — Four Golden Signals: SRE Monitoring](https://pagertree.com/learn/devops/what-is-site-reliability-engineering-sre/four-golden-signals-sre-monitoring)
