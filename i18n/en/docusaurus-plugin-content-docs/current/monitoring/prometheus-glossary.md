---
sidebar_position: 1
---

# Prometheus & Monitoring Terminology

> Key terms for communicating with SREs

---

## Core Concepts

### Metric
A measured value being monitored. Examples: `cpu_usage`, `http_requests_total`.

### Label
Key-value pairs attached to a metric to distinguish different dimensions:
```
http_requests_total{method="GET", status="200", pod="app-a"}
```

### Time Series
One metric name + one fixed set of labels = one time series.

### Sample
One timestamp + one value = one sample. Each scrape of one time series produces 1 sample.

### Active Time Series
The number of time series currently being tracked by Prometheus. Goes stale ~5 minutes after a Pod is deleted.

### Cardinality
The number of label value combinations for a metric. High cardinality = many time series = high memory and cost.
Cardinality Explosion = too many label values (e.g., user_id, request_id), causing the time series count to explode.

---

## Data Collection

### Scrape
Prometheus actively pulls data from a target's `/metrics` endpoint (pull model).

### Scrape Interval
How often to scrape. Common values: 15s / 30s / 60s.

### Scrape Target
The endpoint to scrape, typically a pod's IP:port.

### Job
A named group of scrape targets in the Prometheus config.

### Service Discovery
Auto-discovering scrape targets (in K8s via `kubernetes_sd_config`).

### Exporter
A middleware that converts non-Prometheus metrics into Prometheus format:
- `node-exporter` → machine-level metrics
- `kube-state-metrics` → K8s object state
- `blackbox-exporter` → external endpoint probes

---

## Storage

### TSDB
Time Series Database — optimized for time-series data, built into Prometheus and stored on local disk.

### Head Block
The most recent 2 hours of data, stored in memory for fast queries.

### WAL
Write-Ahead Log — ensures data isn't lost after a crash.

### Retention
How long data is kept before automatic deletion.

### Remote Write
The mechanism for Prometheus to push data to an external TSDB — the core of centralized monitoring.

### Ingestion
The process of writing data into the TSDB. Ingestion Rate = samples written per second.

---

## Querying

### PromQL Common Functions

| Function | Purpose | Example |
|----------|---------|---------|
| `rate()` | Per-second growth rate of a counter | `rate(http_requests_total[5m])` |
| `sum()` | Sum | `sum(rate(http_requests_total[5m]))` |
| `avg()` | Average | `avg(cpu_usage)` |
| `count()` | Count | `count({__name__=~".+"})` |
| `sort_desc()` | Sort descending | `sort_desc(sum by (job) (...))` |
| `avg_over_time()` | Average over a time range | `avg_over_time(metric[7d])` |
| `by` | Group by label | `sum by (namespace) (...)` |

### Recording Rule
A pre-computed PromQL result stored as a new time series.

### Alert Rule
When a PromQL expression continuously satisfies a condition, triggers an alert.

---

## Architecture Components

- **Prometheus Server** — core: scrapes, stores, queries, evaluates alerts
- **Alertmanager** — receives alerts, handles dedup, grouping, routing, and notifications
- **Grafana** — visualization tool, connects to Prometheus for dashboards
- **VictoriaMetrics** — high-performance TSDB alternative, 100% PromQL-compatible, better compression and memory efficiency
  - vmagent / vminsert / vmselect / vmstorage
- **Thanos** — extension layer on top of Prometheus for cross-cluster queries and S3 long-term storage
  - Sidecar / Querier / Store Gateway / Compactor

---

## Common Abbreviations

| Abbreviation | Full Name |
|---|---|
| TSDB | Time Series Database |
| WAL | Write-Ahead Log |
| HA | High Availability |
| QSP | Query Samples Processed |
| IRSA | IAM Roles for Service Accounts |
| OTel | OpenTelemetry |
| CRD | Custom Resource Definition |
| AMP | Amazon Managed Prometheus |
| AMG | Amazon Managed Grafana |
