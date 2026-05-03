---
sidebar_position: 12
---

# S3（Simple Storage Service）

物件儲存，用 `s3://bucket/key` 定址，沒有真正的目錄結構。

---

## URI 結構

```
s3://my-bucket/models/v2.3/model.pt
       │          └─────────────── key（/ 只是命名慣例，不是真實目錄）
       └── bucket name（全球唯一）
```

---

## 常用 CLI

```bash
# 上傳
aws s3 cp model.pt s3://my-bucket/models/v2.3/model.pt

# 下載
aws s3 cp s3://my-bucket/models/v2.3/model.pt ./model.pt

# 列出
aws s3 ls s3://my-bucket/models/

# 同步（只傳差異）
aws s3 sync ./dist s3://my-bucket/static/

# 刪除
aws s3 rm s3://my-bucket/logs/old.log
aws s3 rm s3://my-bucket/logs/ --recursive
```

---

## Storage Class

| Class | 適合 | 最低儲存期 |
|---|---|---|
| Standard | 頻繁存取（預設） | 無 |
| Standard-IA | 不常存取但需快速讀取 | 30 天 |
| Glacier Instant | 每季存取，備份 | 90 天 |
| Glacier Deep Archive | 法規封存 7 年以上 | 180 天 |

Lifecycle policy 可自動把舊物件降到低成本 class。

---

## S3 vs EBS

```
S3  → 任何地方 HTTP 存取，適合靜態檔案、備份
EBS → 掛在特定 EC2 上，適合 OS 磁碟、資料庫資料目錄
```

---

## 一句話總結

| 情境 | 選擇 |
|---|---|
| 靜態檔案、log 封存、ML model | S3 Standard |
| 不常存取的歷史資料 | S3-IA |
| 法規封存 | Glacier Deep Archive |
| OS 磁碟、資料庫 | EBS（不是 S3）|
