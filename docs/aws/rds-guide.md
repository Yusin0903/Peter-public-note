---
sidebar_position: 16
---

# RDS（Relational Database Service）

半托管 SQL 資料庫。AWS 管 OS 和 engine，你管 schema 和查詢。

---

## 責任劃分

```
AWS 負責：
├── 硬體、OS patch
├── 資料庫 engine 安裝與升級
├── 自動備份（PITR，最多 35 天）
├── Multi-AZ 主從切換
└── 儲存自動擴容

你負責：
├── Instance type 選擇
├── Schema 設計與 migration
├── 查詢優化（index、explain）
├── 是否開啟 Multi-AZ（要額外付費）
└── 連線池設定
```

---

## Multi-AZ

```
可用區 A                    可用區 B
─────────────               ─────────────
RDS Primary   ──同步複製──→  RDS Standby
（寫入 / 讀取）               （不對外服務）
      │
      │  Primary 掛掉時
      ▼
DNS endpoint 自動切換到 Standby（約 1-2 分鐘）
你的應用程式連線字串不用改
```

Multi-AZ 不是 Read Replica（不能分流讀取），純粹是為了 HA。

---

## Endpoint 格式

```
mydb.cluster-xyz.us-east-1.rds.amazonaws.com
```

連線字串：

```
postgresql://user:pass@mydb.cluster-xyz.us-east-1.rds.amazonaws.com:5432/mydb
```

---

## RDS vs DynamoDB

| | RDS | DynamoDB |
|---|---|---|
| 查詢模式 | 任意 SQL，支援 JOIN | 只能用 PK / Index |
| Schema | 固定 | 彈性 |
| 聚合查詢 | GROUP BY、AVG、percentile | 不支援 |
| 擴容 | 手動調整 instance size | 全自動 |
| 連線管理 | 需要連線池 | HTTP-based，無需 pool |

選擇邏輯詳見 [AWS Managed Service 型態](./self-managed-vs-fully-managed)。

---

## 一句話總結

| 情境 | 選擇 |
|---|---|
| 需要 JOIN / 聚合 / ad-hoc 查詢 | RDS |
| 已知 PK 查詢，高吞吐 | DynamoDB |
| 需要高可用但不想管 failover | RDS Multi-AZ |
