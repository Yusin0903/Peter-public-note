---
sidebar_position: 4
---

# PostgreSQL 注意事項

## MVCC（Multiversion Concurrency Control）

MVCC（多版本並行控制）是 PostgreSQL 處理並發讀寫的核心機制。

每次寫入不會覆蓋舊資料，而是建立新版本，讀取時看到的是當下 transaction 開始時的資料快照，所以讀不會被寫擋住。

## Serial 欄位陷阱

如果 INSERT 時手動帶入 serial（auto-increment）欄位的值，自動計數器不會觸發，導致之後自動新增時出現衝突：

```
key(id=8) is exists.
```

**解法：** INSERT 時不要帶 serial 欄位，讓資料庫自動產生。如果已有衝突，手動重置 sequence：

```sql
SELECT setval('table_id_seq', (SELECT MAX(id) FROM table));
```

## Multiprocessing 注意事項

在多進程環境下，**不能共用資料庫連線**：

> TCP connections are represented as file descriptors, which usually work across process boundaries, meaning this will cause concurrent access to the file descriptor on behalf of two or more entirely independent Python interpreter states.

**解法：** 每個 process 建立自己的連線，用 process key 管理：

```python
def init_process_db():
    current_process = multiprocessing.current_process()
    process_key = f"{current_process.name}_{current_process.pid}"

    if process_key in _process_local:
        return _process_local[process_key].get("db_manager")

    db_manager = DatabaseManager(database_config=db_config)
    _process_local[process_key] = {"db_manager": db_manager}
    return db_manager
```

## SQLite 效能參考

| 資料量 | 查詢時間 | 加 Index 後 |
|--------|----------|-------------|
| 30 萬 rows (6GB) | ~13s | ~6s |
| 65 萬 rows (12GB) | ~28s | ~12s |
| 130 萬 rows (24GB) | ~55s | ~25s |
| 200 萬 rows (36GB) | ~82s | ~38s |

加上 index 後速度提升超過一半。
