---
sidebar_position: 13
---

# EBS（Elastic Block Store）

掛在 EC2 上的磁碟，像 `/dev/sda`，只有那台機器能用。

---

## 架構

```
EC2 Instance
└── EBS Volume（掛載為 /dev/xvda 或 /dev/xvdb...）
      ├── root volume：OS 所在磁碟，instance 終止時預設一起刪除
      └── data volume：額外掛載，可 detach 後 attach 到其他 EC2
```

---

## Volume Type

| Type | 適合 | IOPS | 費用 |
|---|---|---|---|
| gp3 | 一般用途，預設選這個 | 最高 16,000 | 便宜 |
| io2 | 高 IOPS 資料庫（RDS、Oracle）| 最高 256,000 | 貴 |
| st1 | 大檔案循序讀寫（data warehouse）| 低 | 便宜 |
| sc1 | 極少存取的封存資料 | 最低 | 最便宜 |

大多數情況用 **gp3** 就夠了。

---

## 限制

- 同時只能掛在一台 EC2（Multi-Attach 除外，但限 io2）
- 同一 AZ 才能掛載（跨 AZ 要先 snapshot → 在新 AZ 建新 volume）
- 需要跨多台 EC2 共享 → 改用 EFS

---

## 常用 CLI

```bash
# 建立 100GB gp3 volume
aws ec2 create-volume \
  --availability-zone us-east-1a \
  --volume-type gp3 \
  --size 100

# 掛載到 EC2
aws ec2 attach-volume \
  --volume-id vol-0abc123 \
  --instance-id i-0xyz456 \
  --device /dev/xvdb

# 查看 volume 狀態
aws ec2 describe-volumes --volume-ids vol-0abc123
```

---

## S3 vs EBS

```
S3  → 任何地方都能存取（HTTP API），適合靜態檔案
EBS → 掛在特定機器，低延遲 block storage，適合 DB、OS 磁碟
```

---

## 一句話總結

| 情境 | 選擇 |
|---|---|
| OS 磁碟、資料庫資料目錄 | EBS gp3 |
| 高 IOPS 生產資料庫 | EBS io2 |
| 多台 EC2 共享檔案 | EFS |
| 靜態檔案、備份 | S3 |
