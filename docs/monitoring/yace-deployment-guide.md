---
title: "YACE Deployment Guide — Pitfalls & Working Recipe"
date: 2026-05-07
type: guide
---
<!-- generated from ~/peter-llm-wiki; edit source there, not here -->

# YACE Deployment Guide — Pitfalls & Working Recipe

YACE (Yet Another CloudWatch Exporter) lessons learned from deploying v0.61.2 + chart 0.38.0 to EKS.

## What YACE Is

Pulls AWS CloudWatch metrics → exposes Prometheus-format `/metrics`. Cheaper than the official `cloudwatch_exporter` because it batches `GetMetricData` calls.

## Architecture (push-based, not pull-based)

YACE runs a background scraper at `scraping-interval` (default 300s).
`/metrics` returns **cached** results — Prometheus scrape doesn't trigger CloudWatch calls.

```
[CloudWatch] ←─── background goroutine (300s) ─── [YACE]
                                                     ↓ /metrics (cached)
                                              [Prometheus scrape every 15s]
```

## Pitfalls (with fixes)

### 1. Image registry double-prepend

Chart values `image:` defaults `registry: ghcr.io`. Setting `repository: <ECR>/v1-ti-yace` results in `ghcr.io/<ECR>/v1-ti-yace:<tag>` → `400 Bad Request`.

**Fix**: split registry + repository:

```yaml
image:
  registry: <ECR-host>
  repository: v1-ti-yace
  tag: 0.61.2-test
```

Setting `registry: ""` produces leading `/` → `InvalidImageName`. Don't.

### 2. `searchTags` requires the tag exists

If your AWS resources don't carry a `Name` tag (most don't unless you set them), `searchTags: [{key: Name, ...}]` discovers zero resources → `No tagged resources made it through filtering`.

**Fix**: use `dimensionNameRequirements` on the dimension AWS itself emits:

```yaml
dimensionNameRequirements: [QueueName]              # SQS
dimensionNameRequirements: [DBInstanceIdentifier]   # RDS
dimensionNameRequirements: [LoadBalancer]           # ALB
```

Then filter at Prometheus scrape with `metric_relabel_configs` if you want a subset.

### 3. Schema fields are version-pinned

`includeLinkedAccounts: false` is a v0.62+ field. v0.61.2 logs `field includeLinkedAccounts not found in type config.Job` and **silently skips the job** (or applies defaults). Always pin chart + app version and check release notes for the YACE version, not the chart version.

### 4. IAM `sqs:ListQueues` cannot be resource-scoped

Splitting SQS Statement is mandatory:

```hcl
statement { sid="SQSList"; actions=["sqs:ListQueues"]; resources=["*"] }
statement { sid="SQSRead"; actions=["sqs:GetQueueAttributes"]; resources=[<arn>] }
```

### 5. `iam:ListAccountAliases` warning

Not strictly needed but YACE calls it on startup to enrich `account_alias` label. Without it: warn log, no functional impact. Adding it is cleaner.

### 6. Metric name suffix from `statistics`

Statistics get appended to metric name:
- `statistics: [Maximum]` → `aws_sqs_approximate_number_of_messages_visible_maximum`
- `statistics: [Average]` → `aws_sqs_approximate_number_of_messages_visible_average`
- `statistics: [Maximum, Average]` → both metrics emitted

Querying without the suffix returns nothing.

### 7. `nilToZero: true` worth it

Without it, queues with no traffic emit no sample → Grafana stat panel shows "No data". With it, emits `0` → flat line.

## Minimal Working Config

```yaml
# helm values
image:
  registry: <your-registry>
  repository: yet-another-cloudwatch-exporter
  tag: <version>
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: <irsa-role>
service:
  port: 5000
config: |
  apiVersion: v1alpha1
  sts-region: <region>
  discovery:
    jobs:
      - type: AWS/SQS
        regions: [<region>]
        dimensionNameRequirements: [QueueName]
        period: 300
        metrics:
          - name: ApproximateNumberOfMessagesVisible
            statistics: [Maximum]
            nilToZero: true
```

## Cost Tuning

Cost = `metrics × statistics × (3600/period) × 24 × 30 × $0.01/1000`.

- 1 region, 30 queues, 3 metrics (visible/age/sent), 5min: ~$26/month
- 10 regions, same: ~$260/month
- Cut to `period: 600` (10min): half the cost, lose nothing for backlog alerting

## Verify End-to-End

```bash
# 1. YACE has data
kubectl exec deploy/yace -- wget -qO- http://localhost:5000/metrics | grep aws_sqs_ | head

# 2. Prometheus scraped successfully
curl prometheus:9090/api/v1/query?query='up{job="yace"}'

# 3. Metric stored
curl prometheus:9090/api/v1/query?query='aws_sqs_approximate_number_of_messages_visible_maximum'
```

## Source

- YACE: https://github.com/nerdswords/yet-another-cloudwatch-exporter
- Helm chart: https://github.com/nerdswords/helm-charts
