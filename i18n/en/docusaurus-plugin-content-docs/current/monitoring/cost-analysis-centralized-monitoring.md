---
sidebar_position: 4
---

# Centralized Monitoring Cost Analysis

## Executive Summary

| Option | Monthly Cost | Annual Cost | Ops Effort | Recommendation |
|--------|:---:|:---:|:---:|:---:|
| A: Federation | ~$220 | ~$2,640 | Low | Not recommended (aggregated only) |
| B: VictoriaMetrics | ~$610 | ~$7,320 | Medium | Fallback if AMP too expensive |
| C: Thanos | ~$442 | ~$5,304 | High | Not recommended |
| **D: AMP + AMG** | **~$614** | **~$7,368** | **Very Low** | **Primary recommendation** |

> Baseline: 10 regions × 50K series/region × 30s interval

---

## Baseline Assumptions

| Parameter | Value | How to Verify |
|-----------|-------|---------------|
| Number of regions | 10 | Adjust to your actual count |
| Active time series per region | 50,000 | `prometheus_tsdb_head_series` |
| Scrape interval | 30s | Check Prometheus config |
| Monthly hours | 744 | 31-day month |
| Data retention | 90 days | |
| Dashboard editors | 5 | |
| Dashboard viewers | 15 | |

### Derived Numbers

```
Samples/region/month  = 50,000 × (3600/30) × 744 = 4.464 billion
Total samples (10 regions) = 44.64 billion samples/month
```

---

## Option A: Prometheus Federation

| Cost Item | Monthly |
|-----------|---------|
| Central Prometheus node (t3.xlarge) | ~$120 |
| EBS 200GB (90 days retention) | ~$20 |
| Data transfer IN (free) | $0 |
| Central Grafana node (t3.medium) | ~$30 |
| AMG license (5 editors + 15 viewers) | — (self-hosted) |
| **Total** | **~$170–220** |

**Limitation:** Federation only pulls aggregated metrics. Cannot do full cross-region raw data analysis.

---

## Option B: VictoriaMetrics (Self-Hosted)

| Cost Item | Monthly |
|-----------|---------|
| VM cluster nodes (3×m5.large) | ~$210 |
| EBS storage (90 days, high compression) | ~$60 |
| Data transfer IN (free within region) | $0 |
| Grafana node (t3.medium) | ~$30 |
| **Total** | **~$300–610** |

> Storage cost is much lower than Prometheus due to 7-10x compression ratio.

---

## Option C: Thanos (Self-Hosted)

| Cost Item | Monthly |
|-----------|---------|
| Thanos Query + Store nodes | ~$140 |
| S3 storage (90 days) | ~$15 |
| Data transfer (Sidecar → S3) | ~$27 |
| Grafana node | ~$30 |
| **Total** | **~$212–442** |

**Note:** Operational complexity is high. Requires managing Query, Store, Compact, and Sidecar components.

---

## Option D: AMP + AMG (AWS Managed)

| Cost Item | Monthly | Calculation |
|-----------|---------|-------------|
| AMP Ingestion | ~$450 | 44.64B samples × $0.90/10M (Tier 1) + discount for Tier 2 |
| AMP Storage | ~$54 | ~1.8TB compressed × $0.03/GB |
| AMP Query (QSP) | ~$5 | estimated |
| AMG Editors (5) | $45 | 5 × $9 |
| AMG Viewers (15) | $75 | 15 × $5 |
| Data Transfer IN | $0 | AMP remote_write is free |
| **Total** | **~$629** | |

---

## Cost Sensitivity Analysis

### By Number of Regions (AMP)

| Regions | Active Series | Monthly AMP Cost |
|---------|:---:|:---:|
| 5 | 250K | ~$315 |
| 10 | 500K | ~$504 |
| 20 | 1M | ~$864 |
| 50 | 2.5M | ~$1,800 |

### By Scrape Interval (AMP, 10 regions)

| Interval | Samples/month | Monthly Cost |
|----------|:---:|:---:|
| 60s | 22.3B | ~$295 |
| 30s | 44.6B | ~$504 |
| 15s | 89.3B | ~$864 |

> **Key lever:** Increasing scrape interval from 30s → 60s roughly halves AMP ingestion cost.

---

## Cost Optimization Strategies (Option D)

1. **Adjust scrape interval** — increase to 60s for non-critical metrics, keep 15s for SLO metrics
2. **Recording Rules** — pre-aggregate high-cardinality metrics before remote_write
3. **Metric filtering** — use `remote_write` `write_relabel_configs` to drop unnecessary metrics
4. **Active series audit** — run `sort_desc(count by (__name__) ({__name__=~".+"}))` to find high-cardinality metrics

---

## References

- [AWS Pricing Calculator](https://calculator.aws)
- [AMP Pricing](https://aws.amazon.com/prometheus/pricing/)
- [AMG Pricing](https://aws.amazon.com/grafana/pricing/)
