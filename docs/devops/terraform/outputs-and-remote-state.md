---
sidebar_position: 10
sources:
  - https://developer.hashicorp.com/terraform/language/values/outputs
  - https://developer.hashicorp.com/terraform/language/state/remote-state-data
  - https://developer.hashicorp.com/terraform/cli/commands/output
---
<!-- generated from ~/peter-llm-wiki; edit source there, not here -->

# Terraform Outputs 與 Remote State

## Output 基礎

Output 是模組的「return value」。但有一個關鍵事實：

> **Output 的值會存進 state。**

```hcl
output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.web.id
}
```

Apply 後，`terraform.tfstate`（或遠端 state）裡會記錄這個值。這讓其他配置可以跨 state 讀取它。

### sensitive output 的陷阱

標記 `sensitive = true` 只防止 CLI 顯示，**state 裡還是有明文**：

```hcl
output "db_password" {
  value     = random_password.main.result
  sensitive = true
}
```

- `terraform output` → 顯示 `<sensitive>`
- `terraform output -json` 或 `-raw` → **顯示明文**
- state 檔案裡 → **明文**

`ephemeral = true` 才是真正不進 state（Terraform 1.10+）。

---

## terraform_remote_state — 跨 state 讀 output

`terraform_remote_state` 是 built-in data source，讀取**另一個 root module 的 state 的 outputs**。

```hcl
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "my-terraform-state"
    key    = "vpc/terraform.tfstate"
    region = "us-east-1"
  }
}

# 取用 output
resource "aws_instance" "web" {
  subnet_id = data.terraform_remote_state.vpc.outputs.subnet_id
}
```

### 重要限制

| 限制 | 說明 |
|---|---|
| 只能讀 root module outputs | 子模組的 output 不會暴露，除非 root 有 re-export |
| 需要完整 state 讀取權限 | 讀 outputs 就代表能看整份 state（包含所有 sensitive 值） |
| 推薦替代方案 | HCP Terraform / Enterprise 用 `tfe_outputs`，不需完整 state 讀取 |

### 與 SSM Parameter Store 的比較

```
terraform_remote_state：
  優點：直接引用，不需要額外資源
  缺點：要讀整份 state，IAM 權限範圍大

SSM Parameter Store（把 output 手動存進去）：
  優點：細粒度 IAM，只讀特定參數
  缺點：需要額外寫 aws_ssm_parameter resource
```

---

## terraform output 指令

從 state 讀取 output 值：

```bash
# 列出所有 outputs
terraform output

# 取特定 output（純文字）
terraform output instance_id

# JSON 格式（適合 jq 處理）
terraform output -json

# 只取值（適合 shell script 使用）
terraform output -raw instance_id

# 指定 state 檔案
terraform output -state=path/to/terraform.tfstate
```

常見 pipeline 用法：

```bash
# 取出 EKS cluster name 後直接 update kubeconfig
aws eks update-kubeconfig \
  --name "$(terraform output -raw cluster_name)" \
  --region us-east-1
```

> `-raw` 只支援 string / number / bool。list 或 map 要用 `-json | jq`。
