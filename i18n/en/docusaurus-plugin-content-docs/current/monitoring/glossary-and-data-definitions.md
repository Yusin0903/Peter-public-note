---
sidebar_position: 2
---

# Monitoring Cost Analysis — Glossary & Data Definitions

> Confirms the definition and source of each data point to ensure cost estimates are based on correct inputs.

---

## 1. Prometheus Basics

### 1.1 Metric — e.g. `cpu_usage`, `http_requests_total`, `queue_depth`
### 1.2 Time Series — metric name + fixed label set = 1 time series (directly tied to AMP billing)
### 1.3 Active Time Series — currently scraped series count, query: `prometheus_tsdb_head_series`
### 1.4 Sample — each scrape of one time series produces 1 sample (AMP billed per sample)
### 1.5 Scrape Interval — 15s=240/hr, 30s=120/hr (industry default), 60s=60/hr
### 1.6 Retention — how long data is kept, query: `kubectl get pod prometheus-server-0 -o yaml | grep retention`
### 1.7 Scrape Samples Scraped — how many samples per scrape, query: `sort_desc(scrape_samples_scraped)`

---

## 2. Cost Calculation

### 2.1 Ingestion
AMP billing: monthly samples = active_time_series × (3600 ÷ scrape_interval) × monthly_hours

AMP pricing (tiered):
- Tier 1 (first 2B): $0.90 / 10M samples
- Tier 2 (2B–20B): ~$0.72 / 10M samples

### 2.2 Storage
AMP rate: $0.03/GB/month (high compression ratio, usually very low cost)

### 2.3 QSP (Query Samples Processed)
AMP rate: $0.10 / 1B samples (usually very low cost)

### 2.4 Data Transfer
AMP remote_write (Data Transfer IN) is free; cross-region self-hosted ~$0.02/GB

### 2.5 AMG User License
Editor: $9/person/month, Viewer: $5/person/month (only active users who logged in that month)

---

## 3. K8s Infrastructure

### 3.1 Node Instance Types

| Instance Type | vCPU | RAM | On-demand (us-east-1) |
|---------------|:---:|:---:|:---:|
| t3.medium | 2 | 4 GB | ~$30/month |
| t3.xlarge | 4 | 16 GB | ~$120/month |
| m5.large | 2 | 8 GB | ~$70/month |
| m5.xlarge | 4 | 16 GB | ~$140/month |

### 3.2 Pod Resource Requests / Limits

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "256Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"
```

### 3.3 Prometheus Actual Resource Usage (Reference)

| Pod | CPU | Memory |
|-----|:---:|:---:|
| prometheus-server (primary) | ~80m | ~1.4 Gi |
| prometheus-server (replica) | ~40m | ~1.7 Gi |
| grafana | ~25m | ~110 Mi |
| kube-state-metrics | ~1m | ~22 Mi |
| node-exporter (per node) | ~10m | ~77 Mi |
