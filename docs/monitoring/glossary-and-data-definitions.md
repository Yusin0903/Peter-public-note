---
sidebar_position: 2
---

# 監控成本分析 — 名詞解釋與資料定義

> **注意**：此頁的名詞解釋已合併入 [Prometheus & Monitoring 名詞教學](./prometheus-glossary)，請前往該頁查閱完整內容。
> 以下保留費用計算的補充說明。

---

## Pod Resource Requests / Limits

K8s 中每個 pod 可以設定要求（requests）和上限（limits）的 CPU/Memory。

```yaml
resources:
  requests:
    cpu: "100m"      # 保證 0.1 vCPU
    memory: "256Mi"  # 保證 256 MB
  limits:
    cpu: "500m"      # 最多用 0.5 vCPU
    memory: "512Mi"  # 最多用 512 MB
```

> CPU 單位：`m` = millicores，1000m = 1 vCPU
> Memory 單位：`Mi` = Mebibytes，1024 Mi ≈ 1 GB

---

## Prometheus 實際資源用量（參考值）

| Pod | CPU | Memory | 說明 |
|-----|:---:|:---:|------|
| prometheus-server (primary) | ~80m | ~1.4 Gi | 主要 Prometheus |
| prometheus-server (replica) | ~40m | ~1.7 Gi | 副本 Prometheus |
| grafana | ~25m | ~110 Mi | Grafana |
| kube-state-metrics | ~1m | ~22 Mi | K8s 物件指標 |
| node-exporter (per node) | ~10m | ~77 Mi | 每個 node 一個 |

---

## Node Instance Type（節點機型）

EKS cluster 使用的 EC2 機型，常見配置：

| 機型 | vCPU | RAM | On-demand (us-east-1) |
|------|:---:|:---:|:---:|
| t3.medium | 2 | 4 GB | ~$30/month |
| t3.xlarge | 4 | 16 GB | ~$120/month |
| m5.large | 2 | 8 GB | ~$70/month |
| m5.xlarge | 4 | 16 GB | ~$140/month |
