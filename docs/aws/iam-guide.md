---
sidebar_position: 18
---

# IAM（Identity and Access Management）

回答一個問題：**誰（Identity）可以對什麼資源（Resource）做什麼操作（Action）**。

---

## 核心關係

```
Identity                    Policy                      Resource
──────────────────────────────────────────────────────────────────
IAM User   ──attach──→  [ Effect: Allow/Deny      ]
IAM Group  ──attach──→  [ Action: s3:GetObject    ]  ──→  AWS Resource
IAM Role   ──attach──→  [ Resource: arn:aws:s3::: ]       (S3, EC2, RDS...)
AWS Service              [ Condition: {...}        ]
```

Policy 是獨立物件，可附加到任何 Identity。

---

## User vs Role

| | IAM User | IAM Role |
|---|---|---|
| 代表誰 | 真實的人或機器帳號 | 可被 assume 的身份 |
| 憑證類型 | 長期 Access Key / 密碼 | 臨時 STS token（自動過期）|
| 適合場景 | 本機開發、CLI 操作 | EC2、Lambda、EKS Pod、跨帳號 |
| 推薦程度 | 盡量少用 | 服務優先使用 Role |

> 服務不應該用 User。User 的 Access Key 洩漏後沒有自動過期機制。

---

## Policy 結構

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::my-bucket",
        "arn:aws:s3:::my-bucket/*"
      ]
    }
  ]
}
```

Deny 優先於 Allow，加一個 Deny Statement 就覆蓋其他 Allow。

Policy 類型：
- **AWS Managed** — AWS 維護，如 `AmazonS3ReadOnlyAccess`，方便但粒度粗
- **Customer Managed** — 自己寫，精確控制，推薦
- **Inline** — 直接嵌在 User/Role 上，不建議，難重用

---

## 常見 Scenario

### EC2 存取 S3

```
EC2 Instance
  └── Instance Profile
        └── IAM Role: ec2-app-role
              └── Policy: Allow s3:GetObject on arn:aws:s3:::my-bucket/*
```

Trust Policy（允許 EC2 服務 assume 這個 role）：

```json
{
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
```

EC2 上的程式透過 IMDS 自動取得臨時 credentials，不需要 hardcode Access Key。

### EKS Pod 存取 DynamoDB

Node 的 Role 不應該直接給 Pod 用，需要 IRSA：

```
EKS Pod
  └── K8s ServiceAccount（annotation: eks.amazonaws.com/role-arn）
        └── IAM Role（Trust Policy 允許 OIDC provider assume）
              └── Policy: Allow dynamodb:GetItem / PutItem / Query
```

詳細設定見 [IRSA 指南](./irsa-guide)。

---

## 一句話總結

| 概念 | 一句話 |
|---|---|
| IAM User | 代表人的長期身份，有密碼或 Access Key |
| IAM Role | 代表服務的臨時身份，憑證自動過期 |
| Policy | 定義 Allow / Deny 的 Action + Resource 規則 |
| Trust Policy | 定義誰可以 assume 這個 Role |
| Instance Profile | 把 Role 綁到 EC2 |
| IRSA | 把 Role 綁到 EKS Pod（透過 OIDC）|
