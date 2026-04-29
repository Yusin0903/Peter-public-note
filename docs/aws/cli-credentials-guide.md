---
sidebar_position: 8
---

# AWS CLI 認證完整指南：Access Key、Session Token、Profile

AWS CLI 的認證方式有很多種，這份筆記從最基礎的 Access Key 講起，說明各種認證方式的差異和使用情境。

---

## 認證方式總覽

```
AWS CLI 認證方式（優先順序由高到低）：
1. 環境變數（AWS_ACCESS_KEY_ID 等）
2. ~/.aws/credentials 檔案
3. ~/.aws/config 的 profile
4. EC2 Instance Profile / EKS IRSA（在 AWS 上跑時）
```

---

## Access Key 是什麼

Access Key 是 IAM User 的長期憑證，由兩個部分組成：

```
AWS_ACCESS_KEY_ID     = AKIAIOSFODNN7EXAMPLE       # 像帳號，可以公開
AWS_SECRET_ACCESS_KEY = wJalrXUtnFEMI/K7MDENG/...  # 像密碼，絕對不能外洩
```

> **類比：**
> - `ACCESS_KEY_ID` = 你的員工編號（公開）
> - `SECRET_ACCESS_KEY` = 你的密碼（私密）
>
> 兩個加在一起才能登入。

---

## Session Token 是什麼

某些認證方式（AssumeRole、SSO、臨時 credentials）會額外給一個 `SESSION_TOKEN`。

```
AWS_ACCESS_KEY_ID     = EXAMPLE   # 開頭是 ASIA（臨時的）
AWS_SECRET_ACCESS_KEY = EXAMPLE
AWS_SESSION_TOKEN     = EXAMPLE    # 額外的臨時 token
```

> **Access Key vs Session Token 的差別：**
>
> | | Access Key（長期） | Session Token（臨時） |
> |--|--|--|
> | KEY_ID 開頭 | `AKIA` | `ASIA` |
> | 有效期 | 永久（手動 rotate） | 15分鐘 ~ 12小時 |
> | 取得方式 | IAM Console 建立 | AssumeRole / SSO |
> | 安全性 | 低（洩漏就完了） | 高（自動過期） |

---

## 設定方式

### 方法一：環境變數（臨時使用）

```bash
export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
export AWS_DEFAULT_REGION=us-east-1

# 如果是臨時 credentials（AssumeRole / SSO），還需要：
export AWS_SESSION_TOKEN=EXAMPLE
```

> **注意：** 環境變數只在當前 shell session 有效，開新的 terminal 就消失了。

### 方法二：aws configure（寫入 ~/.aws/credentials）

```bash
aws configure
# 互動式輸入：
# AWS Access Key ID: AKIAIOSFODNN7EXAMPLE
# AWS Secret Access Key: wJalrXUtnFEMI...
# Default region name: us-east-1
# Default output format: json

# 結果寫入 ~/.aws/credentials：
# [default]
# aws_access_key_id = AKIAIOSFODNN7EXAMPLE
# aws_secret_access_key = wJalrXUtnFEMI...
```

### 方法三：多個 Profile（管理多個帳號）

```bash
# 設定環境 profile（例：staging）
aws configure --profile staging
# 輸入該環境帳號的 credentials

# 設定 prod profile
aws configure --profile prod
# 輸入 PROD 帳號的 credentials

# 使用指定 profile
aws s3 ls --profile staging
aws ecr describe-repositories --region us-east-1 --profile prod
```

`~/.aws/credentials` 長這樣：

```ini
[default]
aws_access_key_id = AKIA...
aws_secret_access_key = ...

[staging]
aws_access_key_id = ASIA...
aws_secret_access_key = ...
aws_session_token = EXAMPLE

[prod]
aws_access_key_id = AKIA...
aws_secret_access_key = ...
```

---

## 臨時 Credentials 過期怎麼辦

Session token 有效期很短（通常 1 小時），過期後會看到：

```
An error occurred (ExpiredTokenException) when calling the GetCallerIdentity operation:
The security token included in the request is expired
```

**解法：重新取得一組新的 credentials。**

取得方式取決於你用什麼認證：

```bash
# 用 SSO
aws sso login --profile <profile>

# 用 AssumeRole
aws sts assume-role \
  --role-arn arn:aws:iam::123456789012:role/my-role \
  --role-session-name my-session \
  --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
  --output text

# 用 AWS Console（手動複製 credentials）
# 去 Console → 右上角帳號 → Security credentials → 複製
```

---

## 確認目前用哪個 Credentials

```bash
# 查看目前是哪個 identity
aws sts get-caller-identity

# 輸出：
# {
#     "UserId": "AIDAIOSFODNN7EXAMPLE",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/peter"
# }

# 查看目前用的 region
aws configure get region

# 查看所有 profile
aws configure list-profiles
```

---

## 認證優先順序（重要）

CLI 會依照這個順序找 credentials，**找到就停止**：

```
1. 環境變數 AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
   ↓ 沒有的話
2. ~/.aws/credentials 的 [default] 或 --profile 指定的 section
   ↓ 沒有的話
3. ~/.aws/config 的 profile
   ↓ 沒有的話
4. EC2 Instance Profile（在 EC2 上跑時）
   ↓ 沒有的話
5. EKS IRSA / ECS Task Role（在容器裡跑時）
```

> **常見坑：**
> 你以為在用 profile A，但其實環境變數 `AWS_ACCESS_KEY_ID` 設了另一組 credentials，
> 環境變數的優先順序最高，蓋過了 profile。
>
> 排查時先跑 `aws sts get-caller-identity` 確認你實際用的是哪個 identity。

---

## 安全注意事項

### 不要做的事

```bash
# ❌ 不要把 credentials 直接貼在 chat / PR / commit 裡
export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE  # 這樣會洩漏

# ❌ 不要把 credentials commit 進 git
git add .aws/credentials  # 千萬不要

# ❌ 不要用長期 Access Key（能用 IRSA 或 SSO 就用）
```

### 要做的事

```bash
# ✅ 用 .gitignore 保護
echo ".aws/" >> ~/.gitignore_global

# ✅ 定期 rotate Access Key
aws iam create-access-key --user-name peter
aws iam delete-access-key --access-key-id AKIAOLD...

# ✅ 盡量用短期 credentials（Session Token）
# ✅ 在 AWS 上跑的服務用 IRSA，不要用 Access Key
```

---

## ECR Login 流程說明

ECR 的 login 特別一點，不是直接用 Access Key，而是：

```
Access Key / Session Token
    ↓
aws ecr get-login-password（呼叫 ECR API 換 docker token）
    ↓
docker login（用這個 token 認證）
    ↓
docker push / pull（token 有效期 12 小時）
```

```bash
# 完整指令
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin \
    123456789012.dkr.ecr.us-east-1.amazonaws.com

# 等同於：
TOKEN=$(aws ecr get-login-password --region us-east-1)
echo $TOKEN | docker login --username AWS --password-stdin \
  123456789012.dkr.ecr.us-east-1.amazonaws.com
```

> **為什麼要這樣做：**
> Docker 的認證是帳號密碼，ECR 沒有帳號密碼，
> 所以用 AWS credentials 去換一個「臨時 docker password」，
> username 永遠是 `AWS`，password 是那個臨時 token。

---

## 一句話總結

| 情境 | 做法 |
|------|------|
| 臨時用一次 | `export AWS_ACCESS_KEY_ID=...` |
| 長期使用 | `aws configure` |
| 多帳號切換 | `aws configure --profile <name>` + `--profile` flag |
| 確認目前身份 | `aws sts get-caller-identity` |
| Token 過期 | 重新取得 credentials，重新 export |
| ECR login | `aws ecr get-login-password \| docker login ...` |
