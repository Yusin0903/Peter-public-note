---
sidebar_position: 2
---

# AWS 基礎服務名詞

先看整張架構圖，再點進各主題。

---

## 全局架構圖

```
Internet
   │
   ▼
[ALB] ── HTTP/HTTPS 入口，分流流量
   │
   ▼
[EKS] ── 跑你的 container（K8s）
   │   └── Node 是 EC2，磁碟是 EBS
   │
   ├──→ [RDS]      SQL 資料庫（MySQL/PostgreSQL）
   ├──→ [DynamoDB] NoSQL key-value
   ├──→ [S3]       物件儲存（檔案、模型、圖片）
   └──→ [ECR]      Container image 倉庫（pull image 用）

[IAM] ── 橫跨所有服務，控制「誰可以對誰做什麼」
```

---

## 各主題

### 運算
- **[EC2](./ec2-guide)** — 虛擬機，你全部自己管
- **[EKS](./eks-guide)** — AWS 管 K8s master，你管 workload

### 儲存
- **[S3](./s3-guide)** — 物件儲存，任何地方都能存取
- **[EBS](./ebs-guide)** — 掛在機器上的磁碟，只有那台能用
- **[ECR](./ecr-nav)** — AWS 的 Docker Hub

### 網路
- **[ALB](./alb-guide)** — HTTP 流量入口，自動分流

### 資料庫
- **[RDS](./rds-guide)** — 托管 SQL，AWS 管 OS/engine
- **[DynamoDB](./dynamodb-guide)** — 全託管 NoSQL，自動擴縮

### 身份與權限
- **[IAM](./iam-guide)** — 誰能對什麼做什麼，全域生效

### Managed Service 選型
- **[Self-managed vs Fully managed](./self-managed-vs-fully-managed)** — EC2+MySQL、RDS、DynamoDB 三種管理層次比較
