---
date: 2026-05-18
type: concept
tags: [prometheus, thanos, high-availability, observability]
---
<!-- generated from ~/peter-llm-wiki; edit source there, not here -->

# Prometheus HA Limitations and How Thanos Handles Them

## Core Problem

Prometheus is **stateful and does not replicate its TSDB**. Running multiple Prometheus replicas does not give you replicated data — each replica scrapes and stores independently.

## Why Replicas Diverge

Two Prometheus replicas pointing at the same targets will never produce identical data:

1. **Scrape timing**: Each replica's scrape loop fires on its own schedule. Sample timestamps differ by milliseconds to seconds.
2. **Crash / restart windows**: When replica A is down for rolling restart, replica B keeps scraping. A's TSDB has a gap that B doesn't, and vice versa.
3. **Network blips**: A scrape failure on one replica produces a gap that the other may not have.

The result: replica A and replica B each hold a **slightly different copy** of "the truth" about your targets.

## Why a Load Balancer Breaks HA

The naive HA pattern — put a LB (NLB / ALB / Service ClusterIP with random selection) in front of N Prometheus replicas — **does not work**.

```
       LB picks one randomly
            │
   ┌────────┴────────┐
   ▼                 ▼
Replica A         Replica B
(had a gap        (was healthy
 during rolling    during that
 restart 09:00)    window)
```

If your query hits Replica A for the 09:00 window, you see a gap. If it hits Replica B, you see complete data. Same query, different answers, depending on which backend the LB picked. **This is worse than no HA** — it makes data quality non-deterministic.

## How Thanos Solves It

Thanos Query connects to **all replicas simultaneously** (via DNS service discovery — typically `dnssrv+_grpc._tcp.<headless-svc>`). It then:

1. Pulls the same time range from every replica
2. Deduplicates overlapping samples (using `replica` label)
3. **Fills gaps from one replica with data from another**
4. Returns a single, gap-free merged view to the caller

This requires **direct endpoint access to every replica**, not a single LB endpoint that hides them. The "many endpoints" model is essential to the algorithm.

## Design Implication

| Scenario | Right pattern |
|----------|--------------|
| 1 replica Prometheus | LB OK (no dedup needed) |
| N replica HA Prometheus + Thanos | **DNS discovery / Headless Service** — never a single LB |
| N replica HA + only a single LB | Anti-pattern — breaks Thanos dedup |
| Thanos Receive (not Sidecar) | Receive handles its own replication via RF flag |

## Key Takeaway

LB and HA-Prometheus-with-Thanos are **mutually exclusive design choices**. Choosing HA replicas forces you to expose them via DNS-based service discovery so Thanos Query can reach every replica directly.

## Source

Thanos official documentation:
- [Configuring Thanos Secure TLS Cross-Cluster Communication](https://thanos.io/tip/operating/cross-cluster-tls-communication.md/)
- [Thanos Querier deduplication design](https://thanos.io/tip/components/query.md/)
