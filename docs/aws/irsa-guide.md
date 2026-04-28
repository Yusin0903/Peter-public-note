---
sidebar_position: 10
---

# IRSA：K8s Pod 存取 AWS 資源的正確方式

IRSA（IAM Roles for Service Accounts）是 EKS 上讓 Pod 取得 AWS 資源存取權限的正確方式。

---

## 為什麼不要把 AWS credentials 放進 Secret

```
❌ 錯誤做法：
AWS_ACCESS_KEY_ID + SECRET_ACCESS_KEY
    → K8s Secret
        → Pod 環境變數

問題：
- Key 一旦洩漏就完了（沒有自動過期）
- 手動 rotate，容易忘記
- 稽核困難（誰用了這個 key？）
- 一個 key 可能被多個服務共用，權限無法細分

✅ 正確做法：IRSA
IAM Role → 綁定到 K8s ServiceAccount → Pod 自動取得臨時 token

好處：
- 不需要管理任何 key
- Token 自動 rotate（每小時）
- 細粒度：每個 service 有自己的 IAM Role
- CloudTrail 可以追蹤每個 Pod 的 AWS API 呼叫
```

---

## IRSA 運作原理

```
Pod 啟動
  ↓
K8s 注入 projected token（放在 /var/run/secrets/eks.amazonaws.com/serviceaccount/token）
  ↓
boto3 / AWS SDK 自動偵測這個 token
  ↓
向 AWS STS 換取臨時 credentials（AssumeRoleWithWebIdentity）
  ↓
用臨時 credentials 存取 S3 / Secrets Manager / etc.
```

---

## 設定步驟

### Step 1：建立 IAM Role（Terraform）

```hcl
# 允許 EKS 的 ServiceAccount 使用這個 Role
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:monitoring:prometheus-sa"]
      #                                   ^namespace  ^serviceaccount name
    }
  }
}

resource "aws_iam_role" "prometheus" {
  name               = "prometheus-irsa-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# 附加需要的權限
resource "aws_iam_role_policy_attachment" "prometheus_s3" {
  role       = aws_iam_role.prometheus.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}
```

### Step 2：建立 K8s ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus-sa
  namespace: monitoring
  annotations:
    # 指向 Step 1 建立的 IAM Role
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/prometheus-irsa-role
```

### Step 3：Deployment 使用這個 ServiceAccount

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      serviceAccountName: prometheus-sa   # 指定使用上面的 SA
      containers:
        - name: my-app
          image: my-app:latest
          # 完全不需要設定 AWS_ACCESS_KEY_ID！
          # AWS SDK 自動從 projected token 取得憑證
```

---

## Python Code 不需要改

```python
import boto3

# 有沒有 IRSA，code 完全一樣
# SDK 自動偵測環境，找到 projected token 就用 IRSA
s3 = boto3.client("s3", region_name="us-east-1")
response = s3.get_object(Bucket="my-bucket", Key="data.csv")

# 本地開發：用 ~/.aws/credentials 的 profile
# EKS 上：自動用 IRSA token
# 完全透明，code 不需要判斷環境
```

> **類比：**
> ```python
> # IRSA = 動態取得 token，而不是 hardcode 密碼
>
> # ❌ 錯誤（hardcode）：
> AWS_KEY = "AKIAIOSFODNN7EXAMPLE"   # 洩漏就完了
>
> # ✅ 正確（IRSA）：
> import boto3
> session = boto3.Session()
> # SDK 自動去取臨時 token，每小時自動 rotate
> creds = session.get_credentials()
> ```

---

## 確認 IRSA 是否正確設定

```bash
# 進 Pod 確認 token 存在
kubectl exec -it <pod> -n <namespace> -- ls /var/run/secrets/eks.amazonaws.com/serviceaccount/

# 確認 AWS identity（應該顯示 IAM Role 的 ARN）
kubectl exec -it <pod> -n <namespace> -- \
  aws sts get-caller-identity

# 預期輸出：
# {
#   "Arn": "arn:aws:sts::123456789:assumed-role/prometheus-irsa-role/..."
# }
```

---

## 常見錯誤

### `An error occurred (AccessDenied)`
IAM Role 的 policy 沒有足夠權限，去 IAM Console 確認 Role 附加的 policy。

### Pod 還是用舊的 credentials
ServiceAccount 改了之後要重啟 Pod：
```bash
kubectl rollout restart deployment/<name> -n <namespace>
```

### `WebIdentityErr: failed to retrieve credentials`
OIDC provider 沒有正確設定，確認 EKS cluster 有啟用 OIDC：
```bash
aws eks describe-cluster --name <cluster> \
  --query "cluster.identity.oidc.issuer" --output text
```
