---
sidebar_position: 17
---

# DynamoDB 概覽

全託管 NoSQL，用 partition key（+ 可選 sort key）定址 item，不需要管伺服器或連線 pool。

---

## 資料結構

```
Table
└── Item（一筆資料，schema-free，每筆欄位可不一樣）
      ├── Partition Key  ← 必填，決定資料分到哪個節點
      ├── Sort Key       ← 選填，同一 partition 內排序與範圍查詢
      └── attributes     ← 任意 key-value
```

範例（複合鍵）：

```
user_id (PK)  │  job_id (SK)  │  status   │  latency_ms
──────────────┼───────────────┼───────────┼────────────
user_abc      │  job_001      │  done     │  234
user_abc      │  job_002      │  running  │  (無此欄位)
user_xyz      │  job_003      │  pending  │  (無此欄位)
```

---

## Partition Key vs Sort Key

| | Partition Key | Sort Key |
|---|---|---|
| 必填 | 是 | 否 |
| 查詢方式 | 只能 `=` | 支援 `=`, `begins_with`, `between`, `>`, `<` |
| 唯一性 | 單獨作為唯一識別 | PK + SK 合起來才唯一 |

---

## 你管什麼 vs AWS 管什麼

| 你管 | AWS 管 |
|---|---|
| Table 設計（PK / SK 選擇）| 伺服器、OS patch |
| GSI / LSI 設計 | 跨 AZ 複製、高可用 |
| 避免 hot partition | 自動擴縮容 |
| IAM 權限 | 備份（PITR）|

---

## 常見陷阱

- **熱分區（Hot Partition）**：所有請求集中同一個 PK → 用 UUID 或加 shard suffix 分散
- **scan 費用**：全表掃再過濾，費用照讀出量計，能用 `query` 就不要用 `scan`
- **FilterExpression 不減費用**：server 讀出後才過濾，計費仍以讀出量算

---

## 什麼時候用 DynamoDB vs RDS

**用 DynamoDB：** 查詢模式固定、高吞吐、schema 彈性  
**改用 RDS：** 需要 JOIN、聚合查詢、ad-hoc SQL

詳細比較見 [AWS Managed Service 型態](./self-managed-vs-fully-managed)。

---

## 詳細筆記

- [DynamoDB 連線、查詢、hot partition、boto3 操作](./dynamodb-no-connection-pool)
- [從 DynamoDB 動態取得 Service Token](./service-token-dynamodb)

---

## 一句話總結

| 情境 | 結論 |
|---|---|
| 已知 PK，高吞吐，schema 彈性 | DynamoDB |
| 需要 JOIN / 聚合 / ad-hoc 查詢 | RDS |
