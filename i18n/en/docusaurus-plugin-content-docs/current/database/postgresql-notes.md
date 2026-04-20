---
sidebar_position: 4
---

# PostgreSQL Notes

## MVCC (Multiversion Concurrency Control)

MVCC is PostgreSQL's core mechanism for handling concurrent reads and writes.

Each write doesn't overwrite old data — it creates a new version. Reads see a snapshot of the data as it was when the transaction started, so reads are never blocked by writes.

## Serial Column Trap

If you manually include a `serial` (auto-increment) column value in an INSERT, the auto-counter won't trigger. Subsequent auto-inserts will then conflict:

```
key(id=8) is exists.
```

**Fix:** Don't include the serial column in INSERT — let the database generate it. If there's already a conflict, manually reset the sequence:

```sql
SELECT setval('table_id_seq', (SELECT MAX(id) FROM table));
```

## Multiprocessing Notes

In a multiprocessing environment, **database connections must not be shared across processes**:

> TCP connections are represented as file descriptors, which usually work across process boundaries, meaning this will cause concurrent access to the file descriptor on behalf of two or more entirely independent Python interpreter states.

**Fix:** Each process creates its own connection, managed by a process key:

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

## SQLite Performance Reference

| Row Count | Query Time | With Index |
|-----------|:---:|:---:|
| 300K rows (6GB) | ~13s | ~6s |
| 650K rows (12GB) | ~28s | ~12s |
| 1.3M rows (24GB) | ~55s | ~25s |
| 2M rows (36GB) | ~82s | ~38s |

Adding an index improves speed by more than half.
