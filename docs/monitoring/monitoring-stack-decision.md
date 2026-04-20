---
sidebar_position: 7
---

# Centralized Multi-Region Monitoring — Stack Decision

> **Context:** 10 AWS regions, each with independent Prometheus + Grafana.
> Goal: one central TSDB + one Grafana URL for all regions.
> **Decision: VictoriaMetrics (self-hosted)**

---

## The Problem

When you run the same service across 10 regions, each with its own Prometheus + Grafana:

- Engineers must check 10 separate URLs to get a cross-region picture
- No alerting — each region is siloed
- Dashboard changes must be replicated 10 times manually
- No global view of error rates, queue depths, or pod health

---

## Options Evaluated

| Option | Monthly Cost | Ops Burden | Verdict |
|--------|:-----------:|:----------:|:-------:|
| A: Prometheus Federation | ~$215 | Low | ❌ Aggregated metrics only |
| B: VictoriaMetrics | ~$555-575 | Medium | ✅ Selected |
| C: Thanos | ~$427 | High | ❌ Too complex |
| D: AMP + AMG (AWS managed) | ~$8,460 | Very Low | ❌ Cost 14-17x |
| E: SigNoz | ~$475+ | High | ❌ No multi-region support |

> Cross-region transfer via Transit Gateway (AWS internal) — not public internet.

---

## Critical: Measure Your Active Series Before Deciding

The most common mistake is estimating costs based on assumed series counts.

**Original assumption:** 50,000 active series/region → AMP looked affordable (~$614/month)

**Reality after measurement:** avg ~613,000 series/region → AMP costs ~$8,460/month

Run this on each Prometheus before finalizing your stack choice:
```promql
avg_over_time(prometheus_tsdb_head_series[7d])
```

And ingestion rate:
```promql
sum(rate(prometheus_tsdb_head_samples_appended_total[7d]))
```

**The numbers will surprise you.**

---

## Option A: Prometheus Federation — ❌

**How it works:**
```
Central Prometheus  ──/federate──▶  Region 1 Prometheus
                    ──/federate──▶  Region 2 Prometheus
                    ...
```

**Cost breakdown:**

| Item | Spec | Monthly |
|------|------|:-------:|
| Central Prometheus (EC2) | m5.xlarge | ~$140 |
| EBS storage (gp3) | 500GB | ~$40 |
| Central Grafana (EC2) | t3.medium | ~$30 |
| Cross-region transfer | Minimal (aggregated) | ~$5 |
| **Total** | | **~$215** |

**Why not:**
- Only pulls **aggregated** metrics — raw time series stay in each region
- Cannot do cross-region queries on raw data (e.g., "show pod restarts across all regions in one panel")
- Cheapest option, but the capability gap makes it a dead end

---

## Option C: Thanos — ❌

**Two modes — both problematic:**

### Sidecar mode (official)
```
Each region EKS pod:
  ├── container: prometheus     ← existing
  └── container: thanos-sidecar ← must add to EVERY region manifest

Central:
  ├── Thanos Query
  ├── Thanos Store Gateway
  ├── Thanos Compactor
  └── S3 (long-term storage, required)
```

### Receive mode (newer, less proven)
```
Each region: Prometheus ──remote_write──▶ Thanos Receive
Central: Query + Store + Compactor + S3
```

**Cost breakdown:**

| Item | Spec | Monthly |
|------|------|:-------:|
| Thanos Query (EC2) | 2× m5.large (HA) | ~$140 |
| Thanos Store Gateway (EC2) | 2× m5.large | ~$140 |
| Thanos Compactor (EC2) | 1× m5.large | ~$70 |
| S3 storage | ~500GB compressed | ~$12 |
| S3 API requests | PUT/GET for blocks | ~$20 |
| Thanos Sidecar | Shared with Prometheus pod | ~$0 |
| Central Grafana (EC2) | t3.medium | ~$30 |
| Cross-region transfer | Via Transit Gateway | ~$15 |
| **Total** | | **~$427** |

**Why not:**
- **Sidecar mode:** requires adding a container to every region's Kubernetes manifest — 10 regions = 10 manifest changes + rollouts. High migration risk.
- **Receive mode:** newer pattern, fewer production case studies, was previously "experimental"
- **5 components** (Query, Store, Compactor, Sidecar/Receive, Query Frontend) vs 3 for VictoriaMetrics
- **S3 required** — extra managed service to configure and monitor
- **Cost savings marginal:** ~$427 vs ~$555 — saves ~$128/month but adds significant operational complexity

---

## Option D: AMP + AMG — ❌

**How it works:**
```
Each region: Prometheus ──remote_write + SigV4──▶ AMP Workspace ──▶ AMG
```

Zero infrastructure to manage — AWS handles everything.

**Cost breakdown (at ~75,000 samples/sec):**

| Item | Calculation | Monthly |
|------|------------|:-------:|
| AMP ingestion Tier 1 (first 2B) | 2B × $0.90/10M | ~$180 |
| AMP ingestion Tier 2 (next 18B) | 18B × $0.72/10M | ~$1,296 |
| AMP ingestion Tier 3 (~174B remaining) | 174B × $0.54/10M | ~$9,396 |
| AMP storage | ~200GB × $0.03/GB | ~$6 |
| AMG editors | 5 × $9 | ~$45 |
| AMG viewers | 15 × $5 | ~$75 |
| Cross-region transfer | No DT-IN charge | ~$0 |
| **Total** | | **~$8,460** |

**Cost at different scales:**

| Scale | AMP + AMG | VictoriaMetrics | Difference |
|-------|:---------:|:---------------:|:----------:|
| Current (~75K samples/sec) | ~$8,460/month | ~$555/month | **15x** |
| After cardinality cleanup (~57K) | ~$7,136/month | ~$555/month | **13x** |
| Aggressive cleanup (100K series/region) | ~$2,616/month | ~$555/month | **5x** |

**Why not:**
- AMP charges **per ingested sample** — cost grows linearly with series count
- VictoriaMetrics charges for **EC2 size** — cost stays flat regardless of sample volume
- At avg ~613K series/region (real measured), AMP is 15x more expensive
- Even aggressive cardinality cleanup keeps us above the cost-effective range for AMP

**When AMP makes sense:** fewer than 100K active series/region, or if AWS introduces per-series pricing.

---

## Option E: SigNoz — ❌

**How it works:**
```
Each region: OTel Collector ──OTLP──▶ Central SigNoz (ClickHouse) ──▶ Built-in UI
```

**Cost breakdown:**

| Item | Spec | Monthly |
|------|------|:-------:|
| ClickHouse nodes (EC2) | 3× r5.xlarge (32GB RAM) | ~$330 |
| EBS storage (gp3) | 3× 500GB | ~$120 |
| OTel Collector (per region) | Runs in existing pod | ~$0 |
| Cross-region transfer | Via Transit Gateway | ~$25 |
| **Total** | | **~$475+** |

**Why not:**
- **No mature multi-region federation** — official docs only cover single-region; no proven self-hosted multi-region pattern
- **ClickHouse complexity:** CPU spikes with multiple dashboards open (reported 80%+), diagnostic logs grow to 70GB+, Zookeeper/Keeper dependency, AVX2 CPU requirement
- **Community edition limits:** dashboard count limits, no SSO, no multi-tenancy
- **Scope mismatch:** SigNoz's value is unified metrics+traces+logs; if you only need metrics, you're paying ClickHouse complexity cost without the benefit

---

## Option B: VictoriaMetrics — ✅ Selected

**How it works:**
```
Each region (only change: add remote_write to prometheus.yml):
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

**Cost breakdown:**

| Item | Spec | Monthly |
|------|------|:-------:|
| vminsert (EC2) | 2× c5.large (HA) | ~$125 |
| vmselect (EC2) | 2× m5.large (HA) | ~$140 |
| vmstorage (EC2) | 3× r5.large (replicationFactor=2) | ~$277 |
| EBS storage (gp3) | 3× 500GB (90-day retention) | ~$120 |
| Central Grafana | Runs in existing EKS | ~$0 |
| Cross-region transfer | Via Transit Gateway | ~$25 |
| **Total** | | **~$555-575** |

**Key advantages:**

| Factor | Detail |
|--------|--------|
| Lowest migration risk | Only change per region = 3 lines in `prometheus.yml`. No manifest changes, no pod restarts. |
| Cost is fixed | Driven by EC2 size, not sample volume. Cost stays flat as metrics grow. |
| RAM efficiency | 7-10x less RAM than Prometheus at same cardinality. Critical for high-cardinality regions. |
| 3 components only | vminsert, vmselect, vmstorage — vs 5 for Thanos |
| No external deps | No S3, no Zookeeper |
| Built-in cardinality explorer | VMUI cardinality explorer helps investigate and fix series explosions |
| 100% PromQL compatible | Existing queries and alert rules work without modification |

**Component sizing (pre-production estimate, recalibrate after 1 day real load):**

| Component | Replicas | CPU | RAM | Storage |
|-----------|:--------:|-----|-----|---------|
| vminsert | 2 (HA) | 1-2 vCPU | 1-2Gi | — |
| vmstorage | 3 (replicationFactor=2) | 2-4 vCPU | 8-16Gi | 500Gi gp3 |
| vmselect | 2 (HA) | 2-4 vCPU | 4-8Gi | — |
| vmauth | 2 (HA) | 0.5 vCPU | 256Mi | — |

---

## Migration Strategy (Zero Disruption)

```
Step 1: Deploy VictoriaMetrics + central Grafana in one region (INT/staging)
Step 2: Add remote_write to ONE region's Prometheus
Step 3: Validate data + dashboards
Step 4: Roll out to remaining regions one by one
Step 5: Keep existing per-region Grafana as rollback — never delete Prometheus
```

Rollback is always available: point engineers back to the regional Grafana URL.

---

## Lessons Learned

1. **Measure before estimating** — assumed 50K series/region, reality was 613K average. Cost estimates were wrong by 12x.
2. **Managed services hide costs** — AMP's zero-ops story is compelling, but per-sample billing at scale is brutal.
3. **Migration strategy constrains tech choice** — Thanos Sidecar is a fine architecture, but if you want zero-disruption migration (just add remote_write), VictoriaMetrics is the natural fit.
4. **Transfer costs are secondary** — at $25-50/month, cross-region transfer is noise compared to compute costs. Don't over-optimize for it.
