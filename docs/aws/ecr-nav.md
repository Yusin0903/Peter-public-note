---
sidebar_position: 14
---

# ECR（Elastic Container Registry）

AWS 的私有 Docker image 倉庫。Push 前 repository 必須先手動建立。

---

## URI 結構

```
123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:v1
│             │               │              │       │
account_id   region          domain       repo     tag
```

---

## 3 個核心指令

```bash
# Step 0 — Login（每 12 小時需重新執行）
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin \
    123456789012.dkr.ecr.us-east-1.amazonaws.com

# Step 1 — Build & Tag
docker build -t my-app:v1 .
docker tag my-app:v1 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:v1

# Step 2 — Push
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:v1
```

流程：

```
docker build ──→ docker tag ──→ docker push ──→ ECR Repository
                                                      │
                                             EKS pull image ←──┘
```

完整操作（跨帳號、批次 push、常見錯誤）見 [ECR 完整指南](./ecr-complete-guide)。
