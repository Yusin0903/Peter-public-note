---
sidebar_position: 3
---

# SQLite 遷移到 PostgreSQL（pgloader）

## 安裝

```bash
sudo apt-get install pgloader
```

## 撰寫設定檔

```
LOAD DATABASE
  FROM sqlite:///path/to/your/sqlite.db
  INTO postgresql://username:password@localhost/your_postgresql_db
WITH
  include no drop,
  create tables,
  create indexes,
  reset sequences,
  SET maintenance_work_mem to '512MB',
  work_mem to '64MB',
  search_path to 'public'
```

## 執行

```bash
pgloader migrate.load
```

## 參數說明

| 參數 | 說明 |
|------|------|
| `include no drop` | 不刪除目標資料庫既有的 table |
| `create tables` | 在目標資料庫建立 table |
| `create indexes` | 在目標資料庫建立 index |
| `reset sequences` | 重置 auto-increment sequence，避免衝突 |
| `data only` | 只遷移資料，不遷移 schema |
| `maintenance_work_mem` | 分配給維護工作（如建 index）的記憶體 |
| `work_mem` | 分配給查詢操作（排序、join）的記憶體 |
| `search_path to 'public'` | 設定 PostgreSQL schema 為 public |

## 遷移後的狀態

- **SQLite** 保持不變，pgloader 只讀取不修改
- **PostgreSQL** 會有從 SQLite schema 建立的新 table，以及遷移過來的所有資料

## Reference

- [pgloader SQLite 文檔](https://pgloader.readthedocs.io/en/latest/ref/sqlite.html)
