---
sidebar_position: 4
---

# Cost Analysis: Centralized Monitoring System

> **Status:** Reference Analysis
> **Related:** [Technical Proposal](./centralized-monitoring-proposal)

---

## Executive Summary

Evaluating 4 solutions to centralize monitoring from N separate regional Prometheus + Grafana stacks into a single unified dashboard.

| Option                           | Monthly Cost | Annual Cost |  Ops Effort  |            Recommendation            |
| -------------------------------- | :----------: | :---------: | :----------: | :----------------------------------: |
| A: Prometheus Federation         |    ~$220     |   ~$2,640   |     Low      | Not recommended (limited capability) |
| B: VictoriaMetrics (self-hosted) |    ~$610     |   ~$7,320   |    Medium    |           Fallback option            |
| C: Thanos (self-hosted)          |    ~$442     |   ~$5,304   |     High     |     Not recommended (complexity)     |
| **D: AMP + AMG (AWS managed)**   |  **~$614**   | **~$7,368** | **Very Low** |           **Recommended**            |

**Bottom line:** Option D (AWS managed) costs roughly the same as self-hosted VictoriaMetrics (~$614 vs ~$610/month), but eliminates all infrastructure maintenance overhead. The hidden cost of self-hosted solutions is the engineering time spent on operations, upgrades, and on-call — which is not reflected in the dollar amounts.

> These estimates assume **10 regions × 50K active series/region × 30s scrape interval**.
> Adjust using the [AWS Pricing Calculator](https://calculator.aws) for your actual numbers.

---

## 1. Baseline Assumptions

> Run `count({__name__=~".+"})` on any regional Prometheus to verify your actual numbers.

| Parameter | Value | Notes |
|-----------|-------|-------|
| Number of regions | 10 | Example value |
| Active time series per region | 50,000 | Conservative estimate (K8s + app metrics) |
| Scrape interval | 30 seconds | Standard Prometheus default |
| Monthly hours | 744 | 31-day month |
| Data retention | 90 days | |
| Dashboard editors | 5 | Engineers who create/edit dashboards |
| Dashboard viewers | 15 | Engineers with read-only access |

### Derived Ingestion Volume

```
Samples per region per month:
  = 50,000 series × 120 scrapes/hour × 744 hours/month
  = 4.464 billion samples/region/month

Total across 10 regions:
  = 44.64 billion samples/month
```

---

## 2. Option-by-Option Cost Breakdown

### Option A: Prometheus Federation — $220/month

| Item | Spec | Monthly (USD) |
|------|------|:---:|
| Central Prometheus (EC2) | m5.xlarge (4 vCPU, 16 GB) | $140 |
| EBS storage (gp3) | 500 GB | $40 |
| Central Grafana (EC2) | t3.medium | $30 |
| Cross-region data transfer | Minimal (aggregated only) | $10 |
| **Total** | | **$220** |

**Why cheapest:** Only pulls aggregated metrics, not raw data.
**Trade-off:** Cannot do full cross-region analysis on raw metrics.

---

### Option B: VictoriaMetrics (self-hosted) — $610/month

| Item | Spec | Monthly (USD) |
|------|------|:---:|
| vminsert (EC2) | 2x c5.large (HA) | $125 |
| vmselect (EC2) | 2x m5.large (HA) | $140 |
| vmstorage (EC2) | 2x r5.large (16 GB RAM, HA) | $185 |
| EBS storage (gp3) | 2x 500 GB (HA, 90-day retention) | $80 |
| Central Grafana (EC2/EKS) | t3.medium | $30 |
| Cross-region data transfer | remote_write ~89 GB/month | $50 |
| **Total** | | **$610** |

**Hidden costs not included:**
- Engineering time: ~2-4 hours/month for upgrades, monitoring, troubleshooting
- On-call coverage for VictoriaMetrics cluster issues
- Capacity planning as metrics volume grows

---

### Option C: Thanos (self-hosted) — $442/month

| Item | Spec | Monthly (USD) |
|------|------|:---:|
| Thanos Query (EC2) | 2x m5.large (HA) | $140 |
| Thanos Store Gateway (EC2) | 2x m5.large | $140 |
| Thanos Compactor (EC2) | 1x m5.large | $70 |
| S3 storage | ~500 GB compressed (90 days) | $12 |
| S3 API requests | PUT/GET for blocks | $20 |
| Thanos Sidecar (per region) | Shared with Prometheus pod | $0 |
| Central Grafana (EC2/EKS) | t3.medium | $30 |
| Cross-region data transfer | gRPC query fan-out | $30 |
| **Total** | | **$442** |

**Hidden costs not included:**
- Engineering time: ~4-8 hours/month (4+ components to manage)
- Steep learning curve for Thanos architecture

---

### Option D: AMP + AMG (AWS managed) — $614/month

| Item                           | Calculation               | Monthly (USD) |
| ------------------------------ | ------------------------- | :-----------: |
| **AMP Ingestion**              |                           |               |
| - Tier 1 (first 2B samples)    | 2B x $0.90/10M            |     $180      |
| - Tier 2 (next ~42.6B samples) | ~42.6B x $0.72/10M (est.) |     $307      |
| **AMP Storage**                | ~200 GB x $0.03/GB        |      $6       |
| **AMP Query (QSP)**            | ~10B samples x $0.10/B    |      $1       |
| **AMG Editors**                | 5 users x $9/user         |      $45      |
| **AMG Viewers**                | 15 users x $5/user        |      $75      |
| Cross-region data transfer     | No DT-IN charge for AMP   |      $0       |
| **Total**                      |                           |   **$614**    |

**What's included (no hidden costs):**
- HA / multi-AZ redundancy
- Auto-scaling
- Upgrades and patching
- 150-day default retention (configurable up to 1095 days)
- IAM/SSO integration
- 99.9% SLA

---

## 3. Total Cost of Ownership (TCO) — 1-Year View

### Including Estimated Operational Cost (Engineering Hours)

Assuming engineering cost of $50/hour (internal cost allocation):

| Option | Infra $/year | Ops Hours/month | Ops $/year | **TCO/year** |
|--------|:---:|:---:|:---:|:---:|
| A: Federation | $2,640 | 1-2 hrs | $1,200 | **$3,840** |
| C: Thanos | $5,304 | 4-8 hrs | $3,600 | **$8,904** |
| B: VictoriaMetrics | $7,320 | 2-4 hrs | $1,800 | **$9,120** |
| D: AMP + AMG | $7,368 | 0.5-1 hr | $450 | **$7,818** |

> When operational cost is factored in, **Option D becomes more cost-effective than Option B**,
> despite having higher infrastructure costs. The gap widens as the team scales.

---

## 4. Cost Sensitivity Analysis

### What if active time series per region is different?

| Active Series / Region | Option B (VM) | Option D (AMP) | AMP vs VM |
|:---:|:---:|:---:|:---:|
| 20,000 (low) | ~$450/mo | ~$280/mo | AMP cheaper |
| 50,000 (baseline) | ~$610/mo | ~$614/mo | Roughly equal |
| 100,000 | ~$750/mo | ~$1,100/mo | AMP 47% more |
| 200,000 | ~$950/mo | ~$2,050/mo | AMP 116% more |
| 500,000+ | ~$1,200/mo | ~$4,800/mo | AMP 300% more |

**Key insight:** AMP is cost-competitive at ~50K series/region.
If actual metrics volume is significantly higher (200K+), VictoriaMetrics becomes more economical.

### What if scrape interval changes?

| Scrape Interval | Samples/month (10 regions) | Option D Cost |
|:---:|:---:|:---:|
| 15 seconds | 89.3B | ~$1,100/mo |
| **30 seconds** | **44.6B** | **~$614/mo** |
| 60 seconds | 22.3B | ~$340/mo |

> Doubling the scrape interval halves the AMP ingestion cost.
> This is the most effective cost lever for AMP.

---

## 5. Cost Optimization Strategies (for Option D)

| Strategy | Effort | Savings Impact |
|----------|:---:|:---:|
| Increase scrape interval from 30s to 60s | Low | ~50% ingestion reduction |
| Drop unused metrics via `metric_relabel_configs` | Medium | 10-30% reduction |
| Use recording rules for frequently queried aggregations | Medium | Reduce QSP costs |
| Set appropriate retention period | Low | Reduce storage costs |

Example `metric_relabel_configs` to drop high-cardinality unused metrics:
```yaml
metric_relabel_configs:
  - source_labels: [__name__]
    regex: 'go_.*|promhttp_.*'  # Drop Go runtime / Prometheus internal metrics
    action: drop
```

---

## Appendix: Pricing Sources

- [AMP Pricing](https://aws.amazon.com/prometheus/pricing/)
- [AMG Pricing](https://aws.amazon.com/grafana/pricing/)
- [AMP Cost Optimization Guide](https://docs.aws.amazon.com/prometheus/latest/userguide/AMP-costs.html)
- [AWS Pricing Calculator](https://calculator.aws)
