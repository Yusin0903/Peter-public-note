---
sidebar_position: 11
---

# EKS（Elastic Kubernetes Service）

AWS 托管的 K8s control plane。你管 workload，AWS 管 master。

---

## 架構

```
EKS Cluster
├── Control Plane（AWS 管，你看不到這層）
│     ├── API Server
│     ├── etcd
│     └── Controller Manager / Scheduler
└── Node Group（你的 EC2 worker node）
      └── Node（EC2 instance）
            └── Pod
                  └── Container（image 從 ECR pull）
```

---

## 你管什麼 vs AWS 管什麼

| 你管 | AWS 管 |
|---|---|
| Deployment / Service / Ingress | API Server 高可用 |
| Node Group 規格與數量 | etcd 備份 |
| Namespace、RBAC | Control plane 版本升級 |
| HPA / VPA / Cluster Autoscaler | Control plane 自動修復 |
| Pod resource limits | |

---

## 常用指令

```bash
# 取得 kubeconfig（連到 EKS cluster）
aws eks update-kubeconfig --region us-east-1 --name my-cluster

# 確認目前 context
kubectl config current-context

# 看 node 狀態
kubectl get nodes

# 看 pod 狀態
kubectl get pods -n my-namespace

# 看 pod log
kubectl logs -n my-namespace my-pod --tail=100

# 進入 container
kubectl exec -it -n my-namespace my-pod -- /bin/sh
```

---

## 什麼時候用

**用 EKS：**
- 服務已經 containerized，需要 orchestration
- 需要 rolling update、auto scaling、service discovery
- 多服務之間有依賴關係（Ingress routing、service mesh）

**不用 EKS，改用：**
- 單一小服務 → Lambda 或 ECS（更簡單）
- 只有一台機器的需求 → 直接 EC2

---

## 一句話總結

| 概念 | 一句話 |
|---|---|
| EKS | K8s control plane 是 AWS 的，node 是你的 EC2 |
| Node Group | 一組規格相同的 EC2，組成 K8s worker |
| Pod | K8s 最小部署單位，跑一個或多個 container |
| Fargate | 連 node 都不用管，按 Pod CPU/Memory 計費 |
