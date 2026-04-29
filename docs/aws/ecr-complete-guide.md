---
sidebar_position: 7
---

# ECR 完整指南：建立、推送、跨帳號操作

ECR（Elastic Container Registry）是 AWS 的 Docker image 倉庫，功能類似 Docker Hub，但只在 AWS 內部使用。

---

## ECR 跟 Docker Hub 的最大差異

```
Docker Hub：
  docker push myimage:latest  ← 不用先建 repo，自動建立

ECR：
  docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/myimage:latest
  ❌ Error: name unknown: The repository with name 'myimage' does not exist
```

**ECR 的 repository 必須先手動建立，才能 push。** 這是最常踩到的雷。

---

## 核心概念

```
ECR Registry（帳號層級）
└── Repository（一個 image 的倉庫）
    ├── image:tag1
    ├── image:tag2
    └── image:latest

完整 image URI 格式：
<account_id>.dkr.ecr.<region>.amazonaws.com/<repository_name>:<tag>

例如：
123456789012.dkr.ecr.us-east-1.amazonaws.com/my-grafana:11.6.14
│              │               │              │               │
account_id   region           domain      repo name        tag
```

> **類比：**
> - ECR Registry = 你在 AWS 上的私人 Docker Hub 帳號
> - Repository = 一個 image 專案（像 GitHub 的 repo）
> - Tag = commit hash 或版本號

---

## 基本操作

### 1. 建立 Repository（push 前必做）

```bash
# 建立單一 repository
aws ecr create-repository \
  --repository-name my-grafana \
  --region us-east-1 \
  --image-tag-mutability MUTABLE \
  --image-scanning-configuration scanOnPush=false

# 批次建立多個
for repo in my-grafana my-vminsert my-vmselect my-vmstorage; do
  aws ecr create-repository \
    --repository-name $repo \
    --region us-east-1 \
    --image-tag-mutability MUTABLE \
    --image-scanning-configuration scanOnPush=false
  echo "Created: $repo"
done
```

`--image-tag-mutability MUTABLE` = 同一個 tag 可以重複 push 覆蓋（IMMUTABLE 則不行）

### 2. Login（push/pull 前必做）

ECR 不用帳號密碼，用 AWS credentials 換取 docker token：

```bash
# 格式
aws ecr get-login-password --region <region> \
  | docker login --username AWS --password-stdin \
    <account_id>.dkr.ecr.<region>.amazonaws.com

# 實際例子（us-east-1）
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin \
    123456789012.dkr.ecr.us-east-1.amazonaws.com

# Login token 有效期：12 小時
# 過期後需要重新執行上面的指令
```

### 3. Push Image

```bash
ECR="123456789012.dkr.ecr.us-east-1.amazonaws.com"

# Step 1: Build（或從其他地方 pull）
docker build -t my-grafana:11.6.14 .

# Step 2: Tag（加上 ECR 完整 URI）
docker tag my-grafana:11.6.14 $ECR/my-grafana:11.6.14

# Step 3: Push
docker push $ECR/my-grafana:11.6.14
```

### 4. Pull Image

```bash
ECR="123456789012.dkr.ecr.us-east-1.amazonaws.com"

docker pull $ECR/my-grafana:11.6.14
```

### 5. 查看 Repository 內的 images

```bash
# 列出所有 tags
aws ecr list-images \
  --repository-name my-grafana \
  --region us-east-1 \
  --query "imageIds[*].imageTag" \
  --output table

# 列出所有 repositories
aws ecr describe-repositories \
  --region us-east-1 \
  --query "repositories[*].repositoryName" \
  --output table
```

---

## 跨帳號 / 跨 Region 操作

### Retag + Push（從一個 ECR 推到另一個）

最常見的情境：把來源環境的 image 推到目標環境，或跨 Region 同步。

```bash
SRC_ECR="987654321098.dkr.ecr.us-west-2.amazonaws.com"   # 來源環境
DST_ECR="123456789012.dkr.ecr.us-east-1.amazonaws.com"   # 目標環境

# Step 1: Login 兩個 ECR（如果 image 不在本機）
aws ecr get-login-password --region us-west-2 \
  | docker login --username AWS --password-stdin $SRC_ECR

aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin $DST_ECR

# Step 2: Pull from source（如果本機已有就跳過）
docker pull $SRC_ECR/my-grafana:11.6.14

# Step 3: Retag
docker tag $SRC_ECR/my-grafana:11.6.14 $DST_ECR/my-grafana:11.6.14

# Step 4: Push to destination
docker push $DST_ECR/my-grafana:11.6.14
```

> **注意：** 本機已有 image 時不需要 pull，直接 retag 就好。
> `docker images` 查看本機有哪些 image。

### 批次 Retag + Push

```bash
SRC_ECR="987654321098.dkr.ecr.us-west-2.amazonaws.com"
DST_ECR="123456789012.dkr.ecr.us-east-1.amazonaws.com"

# Login destination
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin $DST_ECR

# Retag and push all
for img in \
  "my-grafana:11.6.14" \
  "my-vm-operator:0.68.4-test" \
  "my-vmstorage:1.140.0-cluster-test" \
  "my-vmselect:1.140.0-cluster-test" \
  "my-vminsert:1.140.0-cluster-test" \
  "my-vmauth:1.140.0-test" \
  "my-vmalert:1.140.0-test"; do
    docker tag $SRC_ECR/$img $DST_ECR/$img
    docker push $DST_ECR/$img
    echo "Pushed: $img"
done
```

---

## Image Tag 策略

| 策略 | 例子 | 適合情境 |
|------|------|----------|
| 版本號 | `11.6.14` | 穩定版本，可追溯 |
| Git SHA | `abc1234` | CI/CD，每個 commit 一個 image |
| 環境 + 版本 | `11.6.14-test` | 測試版本和正式版本分開 |
| `latest` | `latest` | 本地開發（不推薦用在 prod） |

> **為什麼不建議 prod 用 `latest`：**
> MUTABLE tag 的 `latest` 可以被覆蓋，你不知道現在跑的是哪個版本。
> 用具體版本號（`11.6.14`）才能確保每次部署的 image 是預期的那顆。

---

## 常見錯誤

### `name unknown: The repository does not exist`
```bash
# 原因：repository 還沒建立
# 解法：先建 repository
aws ecr create-repository --repository-name <name> --region <region>
```

### `no basic auth credentials`
```bash
# 原因：沒有 login 或 login 已過期（12小時）
# 解法：重新 login
aws ecr get-login-password --region <region> \
  | docker login --username AWS --password-stdin <ecr_uri>
```

### `ExpiredTokenException`
```bash
# 原因：AWS credentials 過期（session token 通常 1 小時）
# 解法：重新取得 credentials（重新 assume role 或 sso login）
```

### `denied: User is not authorized`
```bash
# 原因：IAM 權限不足
# 需要的 IAM 權限：
# ecr:GetAuthorizationToken
# ecr:BatchCheckLayerAvailability
# ecr:PutImage
# ecr:InitiateLayerUpload
# ecr:UploadLayerPart
# ecr:CompleteLayerUpload
```

---

## 一句話總結

| 操作 | 指令 |
|------|------|
| 建立 repo | `aws ecr create-repository --repository-name <name> --region <region>` |
| Login | `aws ecr get-login-password --region <r> \| docker login --username AWS --password-stdin <uri>` |
| Push | `docker tag <img> <ecr_uri>/<name>:<tag> && docker push <ecr_uri>/<name>:<tag>` |
| Pull | `docker pull <ecr_uri>/<name>:<tag>` |
| 查看 images | `aws ecr list-images --repository-name <name> --region <region>` |
| Retag | `docker tag <src> <dst>` |
