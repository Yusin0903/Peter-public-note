---
sidebar_position: 7
---

# Centralized Multi-Region Monitoring — Tech Stack Decision

> **Context:** Multiple AWS Regions, each with independent Prometheus + Grafana.
> Goal: One central TSDB + one Grafana URL to view all Regions.
> **Decision: VictoriaMetrics (self-hosted)**

---

## Problem Statement

When you deploy the same services across multiple Regions, each with its own Prometheus + Grafana:

- Engineers must check multiple URLs to get a cross-Region picture
- No unified alerting — each Region is isolated
- Dashboard changes must be manually synced to every Region
- No global view of error rates, queue depths, or pod health

---

## Options Evaluated

| Option | Monthly Cost | Ops Burden | Verdict |
|--------|:-----------:|:---------:|:------:|
| A: Prometheus Federation | ~$215 | Low | ❌ Aggregated metrics only |
| B: VictoriaMetrics | ~$555-575 | Medium | ✅ Selected |
| C: Thanos | ~$427 | High | ❌ Too complex |
| D: AMP + AMG (AWS managed) | ~$8,460 | Very Low | ❌ 14-17x cost |
| E: SigNoz | ~$475+ | High | ❌ No multi-Region support |

> Cross-Region transfer uses Transit Gateway (AWS internal network), not public internet.

---

## Critical: Measure Your Active Series First

The most common mistake is estimating costs with guessed numbers.

**Original assumption:** 50,000 active series per Region → AMP looks affordable (~$614/month)

**After measurement:** Average ~613,000 series per Region → AMP costs ~$8,460/month

Before deciding on a tech stack, run this on every Prometheus:
```promql
avg_over_time(prometheus_tsdb_head_series[7d])
```

And ingestion rate:
```promql
sum(rate(prometheus_tsdb_head_samples_appended_total[7d]))
```

**The numbers will surprise you.**

---

## Why VictoriaMetrics (Option B) ✅

**How it works:**
```
Each Region (only change: add remote_write to prometheus.yml):
  Prometheus ──remote_write──▶ vmauth (TLS + bearer token)
                                    │
                               vminsert ×2
                                    │
                              vmstorage ×3
                                    │
                              vmselect ×2
                                    │
                           Central Grafana
```

**Key advantages:**

| Aspect | Details |
|--------|---------|
| Lowest migration risk | Each Region only needs 3 lines added to `prometheus.yml`. No manifest changes, no pod restarts. |
| Fixed cost | Determined by EC2 specs, not sample volume. Costs don't grow with metrics. |
| RAM efficiency | 7-10x less RAM than Prometheus at same cardinality. |
| Only 3 components | vminsert, vmselect, vmstorage — vs Thanos's 5 |
| No external dependencies | No S3, no Zookeeper |
| Built-in cardinality explorer | VMUI helps investigate and fix series explosions |
| 100% PromQL compatible | Existing queries and alert rules work without changes |

---

## Why Not Thanos (Option C) ❌

- **Sidecar mode:** Every Region's K8s manifests need a new container — multiple Regions means multiple manifest changes + rollouts
- **Receive mode:** Newer, fewer production case studies
- **5 components** (Query, Store, Compactor, Sidecar/Receive, Query Frontend) vs VM's 3
- **Requires S3** — additional managed service to configure and monitor
- Cost savings are minimal (~$128/month less) but ops complexity increases significantly

---

## Why Not AMP + AMG (Option D) ❌

- AMP **charges per ingested sample** — costs scale linearly with series count
- VictoriaMetrics **charges per EC2 spec** — costs are fixed regardless of sample volume
- At ~613K series per Region, AMP is **15x more expensive**
- Even with aggressive cardinality reduction, still outside AMP's sweet spot

---

## Migration Strategy (Zero Disruption)

```
Step 1: Deploy VictoriaMetrics + Central Grafana in one Region (INT/staging)
Step 2: Add remote_write to one Region's Prometheus
Step 3: Verify data + dashboards
Step 4: Roll out to remaining Regions one by one
Step 5: Keep per-Region Grafana as rollback — never delete Prometheus
```

Rollback is always available: just point engineers back to per-Region Grafana URL.

---

## Lessons Learned

1. **Measure before estimating** — Originally assumed 50K series per Region, actual was 613K average. Cost estimate was off by 12x.
2. **Managed services have hidden costs** — AMP's zero-ops story is appealing, but per-sample pricing is expensive at scale.
3. **Migration strategy constrains tech choice** — Thanos Sidecar is solid architecture, but for zero-disruption migration (just add remote_write), VictoriaMetrics is the natural fit.
4. **Transfer costs are noise** — $25-50/month cross-Region transfer is negligible vs compute costs. Don't over-optimize.
