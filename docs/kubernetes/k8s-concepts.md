---
sidebar_position: 1
---

# Kubernetes 核心概念

K8s 的核心架構拆成幾個主題，每個主題都有對應的 Python 類比幫助快速理解。

## 章節導覽

| 章節 | 內容 |
|------|------|
| [Ingress & Service](./k8s-ingress-and-service) | 請求如何從外部進入 Pod、三種 Service type、內部 DNS |
| [Workload 類型](./k8s-workloads) | Deployment / StatefulSet / DaemonSet / Job / CronJob 選哪個 |
| [Storage](./k8s-storage) | StorageClass / PVC / PV 三層關係、gp2 vs gp3、IOPS vs Throughput |
| [CronJob](./k8s-cronjob) | 定時任務設定、concurrencyPolicy、適合的場景 |
| [可觀測性](./k8s-observability) | Pod log 查詢、多 replica 的 log 問題、EKS vs Lambda 選型 |

---

## 快速心智模型

```
外部流量進來：
  Internet → Ingress（路由規則）→ Service（找 Pod）→ Pod（跑你的程式）

你的 inference system 對應的 workload 類型：
  - Model server（常駐）→ Deployment
  - 資料庫 / 向量 DB  → StatefulSet
  - Log collector     → DaemonSet
  - Batch inference   → CronJob
  - DB migration      → Job
```

```python
# 整個 K8s cluster 就像一個 Python 應用的部署平台：

# Deployment  = uvicorn 跑的 FastAPI server（可以開多個 replica）
# StatefulSet = PostgreSQL（資料要持久化，名字要固定）
# DaemonSet   = 每台 GPU server 上的 dcgm-exporter（node 級別的 agent）
# Job         = python migrate.py（跑完就退）
# CronJob     = crontab 的 K8s 版（定時觸發 Job）
```

---

## 名詞速查

詳細的 K8s & AWS 名詞對照表請參考 [K8s & AWS 基礎名詞對照表](./k8s-and-aws-glossary)。
