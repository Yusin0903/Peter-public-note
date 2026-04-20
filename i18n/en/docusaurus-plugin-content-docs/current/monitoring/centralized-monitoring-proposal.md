---
sidebar_position: 3
---

# Centralized Monitoring System — Technical Proposal

> **Status:** Reference Architecture
> **Use case:** Multi-region EKS deployments with independent Prometheus stacks

---

## Table of Contents

1. [Background & Problem Statement](#1-background--problem-statement)
2. [Goals & Non-Goals](#2-goals--non-goals)
3. [Current Architecture](#3-current-architecture)
4. [Proposed Solutions](#4-proposed-solutions)
5. [Detailed Comparison](#5-detailed-comparison)
6. [Cost Estimation](#6-cost-estimation)
7. [Migration Strategy](#7-migration-strategy)
8. [Recommendation](#8-recommendation)

---

## 1. Background & Problem Statement

### Current Pain Points

| Problem | Impact |
|---------|--------|
| N regions = N separate Grafana URLs | Engineers must switch dashboards to get a full picture |
| No cross-region correlation | Cannot compare metrics across regions in a single view |
| Duplicated dashboard maintenance | Any dashboard change must be replicated manually per region |
| Inconsistent alerting | Alert rules may drift between regions |
| Operational overhead | N independent Prometheus + Grafana stacks to maintain and upgrade |
| No global SLA view | Cannot easily aggregate uptime/error rates across all regions |

### Scenario Context

- Service deployed on **AWS EKS** across **multiple regions**
- Each region runs an independent **Prometheus + Grafana** stack
- Monitoring scope: **K8s cluster metrics + application-specific custom metrics**

---

## 2. Goals & Non-Goals

### Goals

- **Single pane of glass**: One Grafana URL to view all regions
- **Cross-region query**: Compare and correlate metrics across regions
- **Unified alerting**: Centralized alert rules with region-aware routing
- **Reduced operational burden**: Fewer monitoring stacks to maintain
- **Dashboard consistency**: Single source of truth for dashboard definitions

### Non-Goals

- Replacing application-level logging (ELK/CloudWatch Logs)
- Replacing distributed tracing (X-Ray/Jaeger)
- Modifying the application's metric instrumentation code

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

## 4. Proposed Solutions

### Option A: Prometheus Federation

**Concept:** Keep local Prometheus in each region. Deploy a central "Global Prometheus" that uses the `/federate` endpoint to pull aggregated metrics from each regional Prometheus.

```
Region 1: Prometheus (local) ──┐
Region 2: Prometheus (local) ──┤  /federate (pull)
Region 3: Prometheus (local) ──┼─────────────────▶ Central Prometheus ──▶ Central Grafana
...                            │
Region N: Prometheus (local) ──┘
```

- Central Prometheus scrapes each regional Prometheus via `federate`
- Only selected/aggregated metrics are pulled (not raw data)

---

### Option B: Remote Write + Self-Hosted VictoriaMetrics

**Concept:** Each regional Prometheus pushes all metrics via `remote_write` to a centrally deployed VictoriaMetrics cluster.

```
Region 1: Prometheus ──remote_write──┐
Region 2: Prometheus ──remote_write──┤
Region 3: Prometheus ──remote_write──┼──▶ VictoriaMetrics ──▶ Central Grafana
...                                  │    (Central EKS)
Region N: Prometheus ──remote_write──┘
```

**VictoriaMetrics Cluster Components:**
- `vminsert` — accepts incoming remote_write data
- `vmstorage` — persists time-series data on EBS
- `vmselect` — handles PromQL queries from Grafana

---

### Option C: Remote Write + Self-Hosted Thanos

**Concept:** Each regional Prometheus runs a Thanos Sidecar. A central Thanos Query fans out queries across all regions. Long-term storage uses S3.

```
Region 1: Prometheus + Thanos Sidecar ──┐
Region 2: Prometheus + Thanos Sidecar ──┤  gRPC StoreAPI
Region 3: Prometheus + Thanos Sidecar ──┼──────────────▶ Thanos Query ──▶ Central Grafana
...                                     │
Region N: Prometheus + Thanos Sidecar ──┘
                                              ▲
                                              │
                                        Thanos Store ◀── S3 (long-term)
                                        Thanos Compact
```

---

### Option D: AWS Managed (AMP + AMG)

**Concept:** Use AWS-native managed services. Each regional Prometheus pushes via `remote_write` with SigV4 auth to Amazon Managed Prometheus (AMP).

```
Region 1: Prometheus ──remote_write + SigV4──┐
Region 2: Prometheus ──remote_write + SigV4──┤
Region 3: Prometheus ──remote_write + SigV4──┼──▶ AMP Workspace ──▶ AMG Workspace
...                                          │   (central region)    (central region)
Region N: Prometheus ──remote_write + SigV4──┘
```

- **AMP** — fully managed, Cortex/Mimir-based TSDB
- **AMG** — fully managed Grafana with IAM/SSO integration

---

## 5. Detailed Comparison

### 5.1 Architecture & Design

| Criteria | A: Federation | B: VictoriaMetrics | C: Thanos | D: AMP + AMG |
|----------|:---:|:---:|:---:|:---:|
| Data flow direction | Pull | Push | Hybrid | Push |
| Full raw metrics at center | No (aggregated only) | Yes | Yes | Yes |
| Single point of failure | Central Prom | Central VM cluster | Thanos Query | AWS managed (HA built-in) |

### 5.2 Operational Complexity

| Criteria | A: Federation | B: VictoriaMetrics | C: Thanos | D: AMP + AMG |
|----------|:---:|:---:|:---:|:---:|
| Components to deploy (central) | 1 | 3 | 4+ | 0 (managed) |
| Upgrade complexity | Low | Medium | High | None |
| Overall operational burden | **Low** | **Medium** | **High** | **Very Low** |

### 5.3 Performance & Scalability

| Criteria | A: Federation | B: VictoriaMetrics | C: Thanos | D: AMP + AMG |
|----------|:---:|:---:|:---:|:---:|
| Data compression | 1x | 7-10x vs Prometheus | 2-4x | N/A (managed) |
| Max retention | Limited by disk | Limited by EBS | Unlimited (S3) | 150 days default, max 1095 days |

---

## 6. Cost Estimation

### Assumptions

| Parameter | Value | Notes |
|-----------|-------|-------|
| Number of regions | 10 (example) | Adjust based on your deployment |
| Avg active time series per region | 50,000 | Verify with `prometheus_tsdb_head_series` |
| Scrape interval | 30 seconds | Standard Prometheus default |

### Derived Metrics

```
Samples per region per month = 50,000 × (3600/30) × 744 = 4.464 billion
Total samples across 10 regions = 44.64 billion samples/month
```

> Run `count({__name__=~".+"})` on your Prometheus to get actual numbers.

### Cost Comparison Summary

| Option | Monthly Cost (est.) | Annual Cost | Ops Effort |
|--------|:----------:|:----------:|:---:|
| A: Federation | ~$220 | ~$2,640 | Low |
| B: VictoriaMetrics | ~$610 | ~$7,320 | Medium |
| C: Thanos | ~$442 | ~$5,304 | High |
| D: AMP + AMG | ~$614 | ~$7,368 | Very Low |

> Recalculate using the [AWS Pricing Calculator](https://calculator.aws) for your actual numbers.

---

## 7. Migration Strategy

### Phase 1: Parallel Run (Week 1-2)

1. Deploy the chosen central solution in one region
2. Configure **one region** to `remote_write` to the central TSDB
3. Keep existing local Prometheus + Grafana running (no disruption)
4. Validate data consistency: compare local vs central metrics

### Phase 2: Incremental Rollout (Week 3-4)

1. Add remaining regions to `remote_write` one at a time
2. Migrate dashboards to central Grafana
3. Set up centralized alerting rules
4. Add `external_labels` per region:
   ```yaml
   global:
     external_labels:
       region: "ap-southeast-1"
       cluster: "prod"
       environment: "production"
   ```

### Phase 3: Validation & Cutover (Week 5-6)

1. Run both systems in parallel for at least 1-2 weeks
2. Validate all dashboards, alerts, and queries
3. Redirect team to central Grafana URL
4. Decommission regional Grafana instances (keep local Prometheus)

### Rollback Plan

- Local Prometheus instances are never removed
- If central solution fails, simply switch back to regional Grafana URLs
- No data loss risk since local Prometheus retains full data

---

## 8. Recommendation

### Decision Matrix (Weighted Scoring)

| Criteria (Weight) | A: Federation | B: VictoriaMetrics | C: Thanos | D: AMP + AMG |
|---|:---:|:---:|:---:|:---:|
| Operational simplicity (30%) | 8 | 6 | 4 | **10** |
| Full data at center (20%) | 3 | **10** | **10** | **10** |
| Cost efficiency (15%) | **10** | 6 | 7 | 6 |
| AWS ecosystem fit (15%) | 3 | 4 | 5 | **10** |
| Scalability (10%) | 3 | 9 | 8 | **10** |
| Reliability / HA (10%) | 5 | 7 | 8 | **10** |
| **Weighted Score** | **5.6** | **7.0** | **6.6** | **9.3** |

### Primary Recommendation: Option D — AMP + AMG

1. **Zero operational overhead**: AWS fully manages HA, scaling, upgrades, and patching.
2. **Native AWS integration**: SigV4, IAM/IRSA, VPC PrivateLink, SSO.
3. **Proven at scale**: AMP is built on Cortex/Mimir.
4. **Fastest time-to-value**: Each region only needs a `remote_write` config change.

### Fallback: Option B — VictoriaMetrics

Consider when:
- Active time series per region exceeds 200K (AMP becomes expensive)
- Retention requirement exceeds AMP's 1095-day max
- Team prefers full control over the monitoring backend

---

## References

- [Amazon Managed Prometheus — Pricing](https://aws.amazon.com/prometheus/pricing/)
- [Amazon Managed Grafana — Pricing](https://aws.amazon.com/grafana/pricing/)
- [VictoriaMetrics — Cluster Docs](https://docs.victoriametrics.com/victoriametrics/cluster-victoriametrics/)
- [Thanos vs VictoriaMetrics (Last9)](https://last9.io/blog/thanos-vs-victoriametrics/)
