---
sidebar_position: 4
---

# PostgreSQL 深度筆記（推論服務版）

## MVCC（Multiversion Concurrency Control）

MVCC（多版本並行控制）是 PostgreSQL 處理並發讀寫的核心機制。

每次寫入不會覆蓋舊資料，而是建立新版本，讀取時看到的是當下 transaction 開始時的資料快照，所以讀不會被寫擋住。

> **Python 類比**：MVCC 就像 Python 的 `copy-on-write`。當你修改一個 list 時，舊的 snapshot 仍然存在，讀取舊 snapshot 的人不受影響。

---

## Serial 欄位陷阱

如果 INSERT 時手動帶入 serial（auto-increment）欄位的值，自動計數器不會觸發，導致之後自動新增時出現衝突：

```
key(id=8) is exists.
```

**解法：** INSERT 時不要帶 serial 欄位，讓資料庫自動產生。如果已有衝突，手動重置 sequence：

```sql
SELECT setval('table_id_seq', (SELECT MAX(id) FROM table));
```

---

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

---

## EXPLAIN ANALYZE：讀懂查詢計畫

`EXPLAIN ANALYZE` 是優化查詢的最重要工具。它不只告訴你「計畫怎麼跑」，還會實際執行並告訴你「實際花了多少時間」。

> **Python 類比**：`EXPLAIN` 就像 Python 的 `cProfile` 加上 `line_profiler`，讓你看到每一步實際的執行時間和資源消耗。

```sql
EXPLAIN ANALYZE
SELECT * FROM inference_results
WHERE model_name = 'gpt-4' AND created_at > NOW() - INTERVAL '7 days'
ORDER BY score DESC
LIMIT 100;
```

### 讀懂輸出

```
Limit  (cost=1234.56..1235.06 rows=100 width=128) (actual time=45.123..45.234 rows=100 loops=1)
  ->  Sort  (cost=1234.56..1237.81 rows=1300 width=128) (actual time=45.120..45.180 rows=100 loops=1)
        Sort Key: score DESC
        Sort Method: top-N heapsort  Memory: 52kB
        ->  Index Scan using idx_results_model_created on inference_results
              (cost=0.43..1198.12 rows=1300 width=128) (actual time=0.123..43.450 rows=1300 loops=1)
              Index Cond: ((model_name = 'gpt-4') AND (created_at > (now() - '7 days'::interval)))
Planning Time: 0.5 ms
Execution Time: 45.3 ms
```

| 欄位 | 說明 | 注意點 |
|---|---|---|
| `cost=X..Y` | 估計成本（相對單位，X=第一筆，Y=全部） | 和 actual 差很多代表統計資料過舊，執行 `ANALYZE` |
| `actual time=X..Y` | 實際執行時間（ms，X=第一筆，Y=全部） | **這是最重要的數字** |
| `rows=N` | 實際回傳的行數 | 和 `cost` 裡的 rows 差很多 → index 統計不準 |
| `loops=N` | 這個節點執行幾次 | Nested Loop 裡 loops 很大 → 可能有 N+1 |

### 常見壞訊號

```
-- 壞：全表掃描，代表沒有用到 index
Seq Scan on inference_results  (cost=0.00..98765.43 rows=1000000 ...)

-- 壞：Nested Loop 內層 rows 很大，典型 N+1
Nested Loop  (... loops=10000)

-- 好：用了 Index
Index Scan using idx_results_model_created on inference_results
Bitmap Index Scan on idx_results_metadata  (用於 JSONB GIN index)
```

### 讓統計資料保持新鮮

```sql
-- 更新特定 table 的統計資料
ANALYZE inference_results;

-- 更新全部（通常由 autovacuum 自動做，但剛大量匯入資料後手動跑一次）
ANALYZE;
```

---

## Index 策略

推論服務最常用的兩種 index：**B-tree** 和 **GIN**。

> **Python 類比**：B-tree index 就像 Python `dict`（key 有序，點查詢和範圍查詢都快）；GIN index 就像 Python `set` 的 inverted index（適合「包含某元素」的查詢）。

### B-tree Index（預設，適合大多數場景）

```sql
-- 單欄 index
CREATE INDEX idx_results_model ON inference_results(model_name);

-- 複合 index（欄位順序很重要：最常用的篩選條件放前面）
CREATE INDEX idx_results_model_created
  ON inference_results(model_name, created_at DESC);

-- Partial index（只 index 部分資料，更小更快）
-- 只 index 未處理的任務，通常這類查詢最頻繁
CREATE INDEX idx_jobs_pending
  ON inference_jobs(created_at)
  WHERE status = 'pending';
```

**SQLAlchemy 定義 index**：

```python
from sqlalchemy import Index
from sqlalchemy.orm import Mapped, mapped_column

class InferenceResult(Base):
    __tablename__ = "inference_results"
    id: Mapped[int] = mapped_column(primary_key=True)
    model_name: Mapped[str] = mapped_column()
    created_at: Mapped[datetime] = mapped_column()
    score: Mapped[float] = mapped_column()

    __table_args__ = (
        # 複合 index
        Index("idx_results_model_created", "model_name", "created_at"),
        # Partial index（需要用 text 表達條件）
        Index(
            "idx_results_high_score",
            "model_name",
            "score",
            postgresql_where=text("score > 0.9")
        ),
    )
```

### GIN Index（JSONB 查詢必備）

```sql
-- 為 JSONB 欄位建 GIN index，支援 @>（containment）查詢
CREATE INDEX idx_results_metadata_gin
  ON inference_results USING GIN (metadata);

-- 查詢時自動使用 GIN index
SELECT * FROM inference_results
WHERE metadata @> '{"env": "production", "version": "v2"}';
```

**SQLAlchemy 定義 GIN index**：

```python
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy import Index

class InferenceResult(Base):
    __tablename__ = "inference_results"
    metadata_: Mapped[dict] = mapped_column("metadata", JSONB, default=dict)

    __table_args__ = (
        Index(
            "idx_results_metadata_gin",
            "metadata",
            postgresql_using="gin"
        ),
    )
```

### 何時用哪種 index

| 查詢類型 | 推薦 Index | 範例 |
|---|---|---|
| 等值查詢、範圍查詢、排序 | B-tree | `WHERE model_name = 'x'`, `WHERE score > 0.9` |
| JSONB `@>` containment | GIN | `WHERE metadata @> '{"env": "prod"}'` |
| JSONB 特定 key 查詢 | B-tree on expression | `CREATE INDEX ON t ((metadata->>'version'))` |
| 全文搜尋 | GIN with `tsvector` | `WHERE to_tsvector(description) @@ query` |
| LIKE '%keyword%' | GIN with `pg_trgm` | 需要 `CREATE EXTENSION pg_trgm` |

---

## JSONB 儲存推論結果與 Metadata

JSONB 是推論服務的利器，適合儲存：
- 模型的原始輸出（predictions、logits、embeddings）
- 推論的 metadata（model version、input hash、latency）
- 動態設定（hyperparameters、feature flags）

```python
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

class InferenceResult(Base):
    __tablename__ = "inference_results"
    id: Mapped[int] = mapped_column(primary_key=True)
    job_id: Mapped[str] = mapped_column(unique=True)

    # 推論輸出（動態結構，用 JSONB）
    predictions: Mapped[dict] = mapped_column(JSONB, default=dict)
    # 範例：{"labels": ["cat", "dog"], "scores": [0.95, 0.05], "top1": "cat"}

    # 執行 metadata
    run_metadata: Mapped[dict] = mapped_column(JSONB, default=dict)
    # 範例：{"model_version": "v2.1", "latency_ms": 45, "device": "cuda:0"}
```

### JSONB 查詢語法速查

```python
from sqlalchemy import select, cast, String
from sqlalchemy.dialects.postgresql import JSONB

# 取出 JSONB 中的值（返回 JSONB）
stmt = select(InferenceResult.predictions["top1"])

# 取出 JSONB 中的值（強制轉成 text）
stmt = select(InferenceResult.predictions["top1"].as_string())

# WHERE 條件：containment（需要 GIN index）
stmt = select(InferenceResult).where(
    InferenceResult.run_metadata.contains({"device": "cuda:0"})
)

# WHERE 條件：特定 key 的值
stmt = select(InferenceResult).where(
    InferenceResult.run_metadata["model_version"].as_string() == "v2.1"
)

# WHERE 條件：數值比較
stmt = select(InferenceResult).where(
    InferenceResult.run_metadata["latency_ms"].as_float() < 100.0
)
```

---

## Connection Pooling：為什麼需要 PgBouncer

推論服務通常有多個 worker（uvicorn、Celery、Gunicorn），每個 worker 都有自己的連線池。當 worker 數量增加時，PostgreSQL 的連線數會爆炸。

> **Python 類比**：PgBouncer 就像 Python 的 `asyncio.Semaphore`，限制同時存取資源的數量。沒有 PgBouncer 的多 worker 部署，就像沒有 Semaphore 的 async 爬蟲，會把目標打掛。

### 為什麼 PostgreSQL 原生連線很貴

每個 PostgreSQL 連線都是一個獨立的 OS process，消耗約 5-10 MB 記憶體。100 個連線 = 500 MB-1 GB 記憶體。

```
沒有 PgBouncer 的情況：
4 uvicorn workers × (pool_size=10 + max_overflow=20) = 120 連線
→ PostgreSQL 要承受 120 個 process
→ max_connections 預設是 100 → 連線被拒絕，服務崩潰

加了 PgBouncer 後：
所有 worker 的連線 → PgBouncer（維持少量真實連線到 PostgreSQL）
→ PostgreSQL 實際只有 10-20 個連線
→ 大量節省記憶體和 process 開銷
```

### PgBouncer 設定（pgbouncer.ini）

```ini
[databases]
inference_db = host=postgresql-host port=5432 dbname=inference_db

[pgbouncer]
listen_port = 6432
listen_addr = 0.0.0.0
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt

# Transaction mode（推薦推論服務）
# 每個 SQL 執行完就釋放連線，效率最高
# 注意：不支援 session-level features（如 SET LOCAL）
pool_mode = transaction

# 每個 database/user 組合最多幾個 PostgreSQL 連線
default_pool_size = 20

# 額外備用連線
reserve_pool_size = 5

# 連線池達上限時，client 最多等多久（秒）
server_connect_timeout = 15
```

### Kubernetes 部署 PgBouncer

```yaml
# pgbouncer-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgbouncer
spec:
  replicas: 2  # HA
  template:
    spec:
      containers:
        - name: pgbouncer
          image: pgbouncer/pgbouncer:latest
          ports:
            - containerPort: 6432
          env:
            - name: POSTGRESQL_HOST
              value: "postgresql-service"
            - name: PGBOUNCER_POOL_MODE
              value: "transaction"
            - name: PGBOUNCER_DEFAULT_POOL_SIZE
              value: "20"
```

應用程式連到 PgBouncer，不直接連 PostgreSQL：

```python
# database.py
DATABASE_URL = "postgresql+asyncpg://user:pass@pgbouncer-service:6432/inference_db"
```

### PgBouncer 的限制

使用 `transaction` mode 時，以下功能不可用（因為連線在 transaction 間會被換掉）：

- `SET` / `RESET` session-level variables
- `LISTEN` / `NOTIFY`
- Advisory locks（`pg_advisory_lock`）
- Prepared statements（asyncpg 預設會用，需要設定 `statement_cache_size=0`）

```python
# asyncpg + PgBouncer 必要設定
engine = create_async_engine(
    DATABASE_URL,
    connect_args={
        "statement_cache_size": 0,  # 關閉 prepared statement cache
    }
)
```

---

## 常用 psql 指令（除錯工具箱）

```bash
# 連線
psql -h localhost -U username -d inference_db

# 或用 URL
psql "postgresql://username:password@localhost/inference_db"
```

```sql
-- 列出所有 table
\dt

-- 查看 table 結構
\d inference_results

-- 查看所有 index
\di

-- 查看當前所有連線
SELECT pid, usename, application_name, state, query_start, query
FROM pg_stat_activity
WHERE datname = 'inference_db'
ORDER BY query_start;

-- 找出執行超過 30 秒的 query（找慢查詢）
SELECT pid, now() - query_start AS duration, query, state
FROM pg_stat_activity
WHERE state != 'idle'
  AND now() - query_start > INTERVAL '30 seconds'
ORDER BY duration DESC;

-- 強制終止某個 query（不影響連線）
SELECT pg_cancel_backend(pid);

-- 強制斷開某個連線
SELECT pg_terminate_backend(pid);

-- 查看 table 大小（含 index）
SELECT
    pg_size_pretty(pg_total_relation_size('inference_results')) AS total,
    pg_size_pretty(pg_relation_size('inference_results')) AS table_only,
    pg_size_pretty(pg_indexes_size('inference_results')) AS indexes;

-- 查看每個 index 的使用率（找沒用到的 index）
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan AS times_used,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
ORDER BY idx_scan ASC;

-- 查看 table 的統計資料（last_analyze 太舊 → 需要 ANALYZE）
SELECT
    relname,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze,
    n_live_tup,
    n_dead_tup
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;

-- 重置特定 sequence（serial 欄位衝突時用）
SELECT setval('inference_results_id_seq', (SELECT MAX(id) FROM inference_results));

-- 查看鎖定狀況（找 deadlock 或 lock wait）
SELECT
    pid,
    locktype,
    relation::regclass,
    mode,
    granted
FROM pg_locks
WHERE NOT granted;
```

---

## SQLite 效能參考

| 資料量 | 查詢時間 | 加 Index 後 |
|--------|----------|-------------|
| 30 萬 rows (6GB) | ~13s | ~6s |
| 65 萬 rows (12GB) | ~28s | ~12s |
| 130 萬 rows (24GB) | ~55s | ~25s |
| 200 萬 rows (36GB) | ~82s | ~38s |

加上 index 後速度提升超過一半。超過這個規模，或需要多 worker 並發寫入，就該換 PostgreSQL。

---

## Reference

- [PostgreSQL EXPLAIN 官方文件](https://www.postgresql.org/docs/current/sql-explain.html)
- [PostgreSQL Index Types](https://www.postgresql.org/docs/current/indexes-types.html)
- [PostgreSQL JSONB](https://www.postgresql.org/docs/current/datatype-json.html)
- [PgBouncer 官方文件](https://www.pgbouncer.org/config.html)
- [pganalyze: Understanding EXPLAIN](https://pganalyze.com/docs/explain)
