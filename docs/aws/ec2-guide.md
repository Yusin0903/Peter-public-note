---
sidebar_position: 10
---

# EC2（Elastic Compute Cloud）

租一台虛擬機，你有 root 權限，決定 OS、規格、網路。

---

## 架構

```
EC2 Instance
├── Instance Type（CPU / RAM 規格）
│     └── e.g. t3.medium, m6i.xlarge, c7g.large
├── AMI（OS 映像檔）
│     └── Amazon Linux 2023 / Ubuntu 22.04 / Windows Server
├── EBS Volume（磁碟）
│     ├── root volume（/dev/xvda）
│     └── 額外 data volume（可選）
└── VPC Subnet
      ├── Security Group（instance 層級防火牆）
      ├── 公有 subnet → 可分配 Public IP / Elastic IP
      └── 私有 subnet → 只有 VPC 內部可達
```

---

## Instance Type 命名規則

```
t  3  .  medium
│  │     └── 大小：nano / micro / small / medium / large / xlarge / 2xlarge...
│  └──── 世代：數字越大越新
└─────── 家族：決定使用場景
```

| 家族 | 適合 |
|---|---|
| t | 一般用途，可 burst CPU（開發、低流量服務）|
| m | 一般用途，穩定 CPU（web server、API）|
| c | 計算密集（batch job、encoding）|
| r | 記憶體密集（大型 cache、資料庫）|
| p / g | GPU（ML 訓練、推理）|

---

## 常用 CLI

```bash
# 列出執行中的 instance
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].[InstanceId,InstanceType,PublicIpAddress]" \
  --output table

# SSH 連進去
ssh -i ~/.ssh/my-key.pem ec2-user@<public-ip>

# 停止 / 啟動
aws ec2 stop-instances --instance-ids i-0abc123
aws ec2 start-instances --instance-ids i-0abc123
```

---

## 什麼時候用 vs 不用

**用 EC2：**
- 需要完整 OS 控制（GPU driver、特殊 kernel module）
- 跑不適合 container 的 legacy 服務
- EKS worker node 底層就是 EC2（但你不用直接管）

**不用 EC2，改用：**
- 跑 container → EKS / ECS
- 跑函數 → Lambda
- 跑資料庫 → RDS / DynamoDB（別自己管 DB）

---

## 一句話總結

| 場景 | 選擇 |
|---|---|
| 需要完整 OS 控制 | EC2 |
| 跑 container | EKS / ECS |
| 不想管伺服器 | Lambda / Fargate |
