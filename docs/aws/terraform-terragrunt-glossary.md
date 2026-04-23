---
sidebar_position: 9
---

# Terraform & Terragrunt 名詞對照表

---

## Terraform 核心概念

| 名詞 | 一句話 | 類比 |
|---|---|---|
| **Terraform** | IaC 工具，用 HCL 定義雲端資源 | 用 code 描述「我要這些 AWS 資源」 |
| **Provider** | Terraform 跟雲端 API 的橋接 | AWS SDK，讓 Terraform 知道怎麼呼叫 AWS |
| **Resource** | 一個 AWS 資源（EC2、S3 bucket、EKS cluster 等） | 你要建立的東西 |
| **Module** | 一組 resource 打包成可重用模組 | Python 的 function，避免重複寫同樣的 resource |
| **Variable** | 模組的輸入參數 | function 的參數 |
| **Output** | 模組的輸出值 | function 的 return value |
| **Data Source** | 查詢已存在的資源（不建立） | `SELECT` 而不是 `INSERT` |
| **State** | Terraform 記錄目前資源狀態的檔案 | 資料庫，記錄「我現在管理哪些 AWS 資源」 |
| **Plan** | 預覽要做哪些變更（不執行） | git diff，看改動再決定要不要 apply |
| **Apply** | 實際執行變更 | git push，真正改動 AWS |
| **Destroy** | 刪除所有 Terraform 管理的資源 | 危險！確認清楚才能跑 |

---

## State 為什麼重要

```
沒有 State：
  Terraform 每次都不知道 AWS 現在長什麼樣
  → 可能重複建立資源、無法更新、無法刪除

有 State（存在 S3）：
  Terraform 知道「上次 apply 之後 AWS 的狀態」
  → 可以計算出這次 apply 需要做哪些變更

State 存放位置：
  本地：terraform.tfstate（只有自己能用，不能團隊協作）
  遠端：S3 + DynamoDB lock（團隊協作的標準做法）
```

**遠端 State 設定範例：**

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "prod/eks/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-lock"  # 防止多人同時 apply
  }
}
```

---

## Module 結構

```
modules/
├── eks-cluster/
│   ├── main.tf        # 主要 resource
│   ├── _variables.tf  # 輸入變數
│   ├── outputs.tf     # 輸出值
│   └── versions.tf    # provider 版本鎖定
└── monitoring/
    ├── main.tf
    └── _variables.tf

# 呼叫 module
module "eks" {
  source       = "./modules/eks-cluster"
  cluster_name = "my-cluster"
  region       = "us-east-1"
}

# 使用 module 的 output
resource "aws_route53_record" "eks" {
  name = module.eks.cluster_endpoint  # 取得 module 的輸出
}
```

---

## 常用指令

```bash
# 初始化（下載 provider，設定 backend）
terraform init

# 預覽變更
terraform plan

# 執行變更
terraform apply

# 只預覽/執行特定 resource
terraform plan -target=module.monitoring
terraform apply -target=module.monitoring

# 查看目前 state
terraform state list
terraform state show <resource>

# 強制重新整理 state（從 AWS 重新讀取）
terraform refresh

# 銷毀（危險！）
terraform destroy
```

---

## Terragrunt

Terragrunt 是 Terraform 的 wrapper，解決多環境管理的問題。

### 為什麼要用 Terragrunt

```
問題：
  有 10 個 region，每個都要跑同樣的 Terraform module
  但 region、帳號、CIDR 不同
  → 10 個資料夾，每個都有重複的 backend 設定 = 很難維護

解法（Terragrunt）：
  一個 Terraform module（共用）
  10 個 terragrunt.hcl（各自的 inputs）
  → DRY（Don't Repeat Yourself）
```

### Terragrunt 結構

```
terraform/
├── eks/                        # 共用的 Terraform module
│   ├── main.tf
│   ├── variables.tf
│   └── modules/
│       └── monitoring/
└── terragrunt/
    ├── int/
    │   └── terragrunt.hcl      # INT 環境的 inputs
    ├── us-stg/
    │   └── terragrunt.hcl      # STG 環境的 inputs
    └── us-prod/
        └── terragrunt.hcl      # PROD 環境的 inputs
```

### terragrunt.hcl 範例

```hcl
# 產生 backend 設定（每個環境獨立的 S3 state）
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents = <<EOF
terraform {
  backend "s3" {
    bucket = "my-terraform-state-prod"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}
EOF
}

# 指向共用的 Terraform module
terraform {
  source = "../..//eks"
}

# 這個環境的具體值
inputs = {
  name          = "my-cluster-prod"
  region        = "us-east-1"
  cluster_name  = "v1-ti-eks-prod"
  desired_size  = 5
  monitor_enabled = true
}
```

### 常用 Terragrunt 指令

```bash
# 等同 terraform plan（在 terragrunt 目錄下跑）
cd terragrunt/us-prod
terragrunt plan

# 等同 terraform apply
terragrunt apply

# 對所有環境一起跑（run-all）
terragrunt run-all plan
terragrunt run-all apply
```

---

## Terraform vs Terragrunt 一句話

| | Terraform | Terragrunt |
|--|--|--|
| 角色 | IaC 工具本體 | Terraform 的多環境管理 wrapper |
| 解決問題 | 定義 AWS 資源 | 避免多環境重複設定 |
| 設定檔 | `.tf` 檔案 | `terragrunt.hcl` |
| 常見搭配 | 單一環境 | 多環境（int/stg/prod） |
