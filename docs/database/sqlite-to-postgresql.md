---
sidebar_position: 3
---

# SQLite 遷移到 PostgreSQL

## 先問：真的需要遷移嗎？

**SQLite 在這些推論服務場景是完全合理的選擇，不要為了遷移而遷移：**

| 場景 | 建議 |
|---|---|
| 本地開發環境的測試資料庫 | 繼續用 SQLite |
| 邊緣推論設備（無法連網的 IoT、移動設備） | 用 SQLite |
| 單一 Python 程序的本地快取（feature store cache、embedding cache） | 用 SQLite |
| 並發讀取多、寫入少的唯讀 lookup table | 用 SQLite |
| 需要多 worker 同時寫入 | 換 PostgreSQL |
| 需要真正的 ACID + 行鎖 | 換 PostgreSQL |
| 資料量超過 10GB 且有複雜查詢 | 換 PostgreSQL |
| 需要 JSONB、全文搜尋、向量搜尋 | 換 PostgreSQL |

> **Python 類比**：SQLite 就像 Python 的 `dict` + `pickle`，對單一程序完全夠用；PostgreSQL 就像 Redis 或 Kafka，是為了多個 worker/服務共享狀態而存在。不要因為「PostgreSQL 比較專業」就換，要因為「SQLite 解決不了我的問題」才換。

---

## 型別差異與常見陷阱

從 SQLite 遷移時，這些型別差異是最常見的坑，`pgloader` 會自動處理大部分，但你需要理解背後的邏輯。

### 1. AUTOINCREMENT vs SERIAL vs IDENTITY

```sql
-- SQLite
CREATE TABLE results (
    id INTEGER PRIMARY KEY AUTOINCREMENT
);

-- PostgreSQL（舊寫法，仍常見）
CREATE TABLE results (
    id SERIAL PRIMARY KEY
    -- SERIAL 是 SMALLINT/INT/BIGINT + SEQUENCE 的語法糖
);

-- PostgreSQL（新寫法，SQL 標準，推薦）
CREATE TABLE results (
    id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY
);
```

**SQLAlchemy 的寫法**（自動處理跨資料庫差異）：

```python
from sqlalchemy import Integer
from sqlalchemy.orm import Mapped, mapped_column

class InferenceResult(Base):
    __tablename__ = "inference_results"
    # SQLAlchemy 會根據資料庫自動選擇正確的 autoincrement 機制
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
```

**陷阱**：如果你在遷移時手動帶入 `id` 值（例如保留原始 SQLite 的 ID），PostgreSQL 的 sequence 不會更新，導致後續 INSERT 衝突：

```sql
-- 遷移後必須重置 sequence
SELECT setval('inference_results_id_seq', (SELECT MAX(id) FROM inference_results));
```

`pgloader` 的 `reset sequences` 選項會自動做這件事。

### 2. TEXT vs VARCHAR

```sql
-- SQLite：TEXT 就是 TEXT，無長度限制
CREATE TABLE models (name TEXT);

-- PostgreSQL：VARCHAR(n) 有長度限制，TEXT 無限制
-- 建議：PostgreSQL 裡直接用 TEXT，效能和 VARCHAR 一樣，但少了長度限制的麻煩
CREATE TABLE models (name TEXT);
```

> **Python 類比**：SQLite 的 TEXT 就像 Python `str`，PostgreSQL 的 `VARCHAR(100)` 就像 `str` 但加了 `assert len(s) <= 100`。推論服務存 model name、label、描述，建議都用 `TEXT`，不要設長度限制。

**SQLAlchemy 寫法**：

```python
from sqlalchemy import String, Text

# 推薦：Text（對應 PostgreSQL TEXT，無長度限制）
name: Mapped[str] = mapped_column(Text)

# 如果有長度需求（如 UUID、固定格式 token）
job_id: Mapped[str] = mapped_column(String(36))
```

### 3. Boolean 型別差異

```sql
-- SQLite：沒有真正的 BOOLEAN，用 0/1 的 INTEGER 模擬
CREATE TABLE jobs (is_active INTEGER DEFAULT 1);  -- 0 = False, 1 = True

-- PostgreSQL：有真正的 BOOLEAN 型別
CREATE TABLE jobs (is_active BOOLEAN DEFAULT TRUE);
```

**SQLAlchemy 陷阱**：

```python
# 如果你的 SQLite 資料庫存的是 0/1，遷移到 PostgreSQL 後
# SQLAlchemy 的 Boolean 型別會自動轉換，但直接下 raw SQL 要注意：

# 這在 PostgreSQL 會報錯（不能把 integer 和 boolean 比較）
await db.execute(text("SELECT * FROM jobs WHERE is_active = 1"))

# 正確寫法
await db.execute(text("SELECT * FROM jobs WHERE is_active = TRUE"))

# 用 SQLAlchemy ORM 沒問題，它會自動處理
select(Job).where(Job.is_active == True)
select(Job).where(Job.is_active.is_(True))  # 更明確，推薦
```

### 4. JSON vs JSONB（PostgreSQL 獨有優勢）

SQLite 沒有原生 JSON 型別，通常用 TEXT 存 JSON string。PostgreSQL 有 `JSON` 和 `JSONB` 兩種：

| 型別 | 特性 | 推薦場景 |
|---|---|---|
| `JSON` | 保留原始文字格式（含空格、key 順序） | 需要精確重現原始輸入 |
| `JSONB` | 二進制儲存，可索引，查詢快 | **推論服務推薦**，存 metadata、模型輸出 |

```python
# SQLAlchemy 使用 JSONB
from sqlalchemy.dialects.postgresql import JSONB

class InferenceResult(Base):
    __tablename__ = "inference_results"
    id: Mapped[int] = mapped_column(primary_key=True)
    # 存推論的原始輸出、metadata、超參數等
    metadata_: Mapped[dict] = mapped_column(JSONB, default=dict)
    predictions: Mapped[list] = mapped_column(JSONB, default=list)
```

JSONB 查詢範例：

```python
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy import cast

# 查詢 JSONB 欄位內的值（PostgreSQL 特有語法）
# 找所有 metadata 中 model_version = "v2.0" 的結果
stmt = select(InferenceResult).where(
    InferenceResult.metadata_["model_version"].as_string() == "v2.0"
)

# 用 @> 運算子做 containment 查詢（需要 GIN index）
stmt = select(InferenceResult).where(
    InferenceResult.metadata_.contains({"env": "production"})
)
```

---

## pgloader 遷移工具

### 安裝

```bash
# Ubuntu/Debian
sudo apt-get install pgloader

# macOS
brew install pgloader
```

### 基本設定檔

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

### 執行

```bash
pgloader migrate.load
```

### 進階：型別轉換

```
LOAD DATABASE
  FROM sqlite:///inference.db
  INTO postgresql://user:pass@localhost/inference_pg
WITH
  include no drop,
  create tables,
  create indexes,
  reset sequences

CAST
  -- SQLite INTEGER 的 boolean 欄位 → PostgreSQL BOOLEAN
  column inference_jobs.is_active to boolean using (if (= 1 value) 't' 'f'),
  -- SQLite TEXT 存的 JSON → PostgreSQL JSONB
  column inference_results.metadata to jsonb using pgloader.transforms::json-to-jsonb
;
```

### 參數說明

| 參數 | 說明 |
|------|------|
| `include no drop` | 不刪除目標資料庫既有的 table |
| `create tables` | 在目標資料庫建立 table |
| `create indexes` | 在目標資料庫建立 index |
| `reset sequences` | 重置 auto-increment sequence，避免衝突 |
| `data only` | 只遷移資料，不遷移 schema（已有 Alembic 管理 schema 時使用）|
| `maintenance_work_mem` | 分配給維護工作（如建 index）的記憶體 |
| `work_mem` | 分配給查詢操作（排序、join）的記憶體 |
| `search_path to 'public'` | 設定 PostgreSQL schema 為 public |

### 遷移後驗證

```bash
# 確認行數一致
psql -c "SELECT COUNT(*) FROM inference_results;" inference_pg
sqlite3 inference.db "SELECT COUNT(*) FROM inference_results;"

# 確認 sequence 正確
psql -c "SELECT last_value FROM inference_results_id_seq;" inference_pg
psql -c "SELECT MAX(id) FROM inference_results;" inference_pg
# 兩個數字應該相同
```

---

## 推薦遷移流程（含 Alembic）

如果你的服務已在用 Alembic 管理 schema：

```bash
# 1. 先讓 Alembic 在 PostgreSQL 上建好 schema
alembic upgrade head

# 2. 用 pgloader 只遷移資料（不遷移 schema）
# 修改設定檔加上 data only

# 3. 重置所有 sequence
psql -c "
SELECT 'SELECT setval(''' || sequence_name || ''', (SELECT MAX(id) FROM '
       || replace(sequence_name, '_id_seq', '') || '));'
FROM information_schema.sequences
WHERE sequence_schema = 'public';
" | psql

# 4. 驗證資料
python scripts/verify_migration.py
```

---

## 遷移後的狀態

- **SQLite** 保持不變，pgloader 只讀取不修改
- **PostgreSQL** 會有從 SQLite schema 建立的新 table，以及遷移過來的所有資料

---

## Reference

- [pgloader SQLite 文檔](https://pgloader.readthedocs.io/en/latest/ref/sqlite.html)
- [PostgreSQL Data Types](https://www.postgresql.org/docs/current/datatype.html)
- [SQLAlchemy PostgreSQL Dialect](https://docs.sqlalchemy.org/en/20/dialects/postgresql.html)
