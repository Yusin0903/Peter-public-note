---
sidebar_position: 5
---

# Decision Record: Why SigNoz Was Not Adopted (Current Phase)

> **Conclusion:** Not adopted for now — may be reconsidered in the future
> **Alternative:** Grafana Stack (VictoriaMetrics + Grafana, with Loki + Tempo later)

SigNoz is an open-source full-stack Observability platform (metrics + traces + logs), built around OpenTelemetry with ClickHouse as the unified database.

## Pros (Why It Was Considered)

- **Full-stack Observability**: One platform covering metrics + traces + logs
- **Unified database**: Everything in ClickHouse — native joins across signal types
- **OpenTelemetry-native**: trace-to-log and log-to-metric correlation more reliable than Grafana Stack
- **Fewer components, built-in UI, open source**

## Reasons Not Adopted

1. **No mature cross-region solution** — No native federation; official docs only cover Cloud version; almost no self-hosted multi-region examples in the community
2. **ClickHouse operational overhead** — Zookeeper dependency, CPU spikes, internal logs growing to 70GB+, AVX2 CPU architecture requirements, "monitoring the monitor" problem
3. **Community edition limitations** — Limited dashboard count, limited Traces/Logs panels, no SSO/SAML, no multi-tenancy
4. **Immature ecosystem** — Small community, no plugin support, only partial PromQL compatibility, sparse reference material
5. **Migration cost** — Must learn ClickHouse SQL, SigNoz UI, deploy OTel Collector; messy documentation

## When to Reconsider

- SigNoz releases native multi-region federation
- Community edition removes dashboard count limits
- Team has dedicated ClickHouse operator
- Confirmed need for deep metrics + traces + logs correlation that Grafana Stack can't satisfy
- SigNoz production case studies and community size grow significantly
