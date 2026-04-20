---
sidebar_position: 3
---

# SQLite to PostgreSQL Migration (pgloader)

## Install

```bash
sudo apt-get install pgloader
```

## Write a Config File

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

## Execute

```bash
pgloader migrate.load
```

## Parameter Reference

| Parameter | Description |
|-----------|-------------|
| `include no drop` | Don't drop existing tables in the target database |
| `create tables` | Create tables in the target database |
| `create indexes` | Create indexes in the target database |
| `reset sequences` | Reset auto-increment sequences to avoid conflicts |
| `data only` | Migrate data only, skip schema |
| `maintenance_work_mem` | Memory allocated for maintenance tasks (e.g. building indexes) |
| `work_mem` | Memory allocated for query operations (sorting, joins) |
| `search_path to 'public'` | Set PostgreSQL schema to public |

## Post-Migration State

- **SQLite** remains unchanged — pgloader only reads, never modifies
- **PostgreSQL** will have new tables built from the SQLite schema, with all migrated data

## Reference

- [pgloader SQLite Docs](https://pgloader.readthedocs.io/en/latest/ref/sqlite.html)
