---
sidebar_position: 1
---

# Kubernetes 核心概念

K8s 的核心架構拆成幾個主題，每個主題都有對應的 Python 類比幫助快速理解。

## 章節導覽

| 章節 | 內容 |
|------|------|
| [Ingress & Service](./k8s-ingress-and-service) | 請求如何從外部進入 Pod、三種 Service type、內部 DNS、Health Check Probe、Resource Requests/Limits、HPA |
| [Workload 類型](./k8s-workloads) | Deployment / StatefulSet / DaemonSet / Job / CronJob 選哪個、Rolling Update、Init Container、Sidecar、完整 GPU Deployment YAML |
| [Storage](./k8s-storage) | StorageClass / PVC / PV 三層關係、emptyDir、ConfigMap as volume、gp2 vs gp3、IOPS vs Throughput |
| [CronJob](./k8s-cronjob) | 定時任務設定、concurrencyPolicy、activeDeadlineSeconds、資源限制、真實 Batch Inference YAML |
| [可觀測性](./k8s-observability) | Pod log 查詢、kubectl exec/describe/top、events、CrashLoopBackOff 診斷流程、EKS vs Lambda 選型 |
| [名詞對照表](./k8s-and-aws-glossary) | K8s & AWS 核心名詞、ConfigMap/Secret/Namespace/HPA/ResourceQuota/LimitRange/IRSA 詳解 |
| [部署工具](./k8s-deployment-tools) | Terraform 定位、Helm values 多環境管理、Kustomize overlay、ArgoCD GitOps 流程 |
| [Docker 技巧](./docker-tips) | Multi-stage build、GPU Dockerfile、.dockerignore 最佳實踐 |

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

## Inference System 關鍵設定清單

部署 inference server 到 EKS 前，確認這些設定都到位：

| 項目 | 設定 | 文件 |
|------|------|------|
| Model 載入等待 | `readinessProbe.initialDelaySeconds >= 60` | [Ingress & Service](./k8s-ingress-and-service) |
| 防止誤殺 | `livenessProbe.initialDelaySeconds > readinessProbe.initialDelaySeconds` | [Ingress & Service](./k8s-ingress-and-service) |
| GPU 資源申請 | `requests.nvidia.com/gpu == limits.nvidia.com/gpu` | [Ingress & Service](./k8s-ingress-and-service) |
| 零停機更新 | `maxUnavailable: 0` | [Workload 類型](./k8s-workloads) |
| Model 下載 | Init Container 從 S3 下載 | [Workload 類型](./k8s-workloads) |
| /dev/shm | `emptyDir medium: Memory` | [Workload 類型](./k8s-workloads) |
| AWS 權限 | IRSA + ServiceAccount，不用 hardcode credentials | [名詞對照表](./k8s-and-aws-glossary) |
| Batch Job timeout | `activeDeadlineSeconds` | [CronJob](./k8s-cronjob) |
| Image 大小 | Multi-stage build，model weights 不打包進 image | [Docker 技巧](./docker-tips) |

---

## 名詞速查

詳細的 K8s & AWS 名詞對照表請參考 [K8s & AWS 基礎名詞對照表](./k8s-and-aws-glossary)。
