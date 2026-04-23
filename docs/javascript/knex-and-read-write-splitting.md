---
sidebar_position: 8
---

# Knex（JS 版的 SQLAlchemy）& 讀寫分離

## Knex 基本概念

Knex 是 Node.js 的 SQL query builder，定位類似 Python 的 SQLAlchemy Core（不是 ORM）。

| | Knex (Node.js) | SQLAlchemy (Python) |
|---|---|---|
| 定位 | SQL query builder | Core = query builder；ORM = 物件映射 |
| 連線池 | 內建（基於 `tarn`） | 內建（基於 `QueuePool`） |
| Migration | `knex migrate` | `alembic` |
| Transaction | `knex.transaction()` | `with session.begin():` |
| Raw SQL | `knex.raw("SELECT ...")` | `text("SELECT ...")` |

> **Python 類比**：Knex 的 query builder 風格對應 SQLAlchemy Core：
> ```python
> # SQLAlchemy Core（類似 Knex 的寫法）
> from sqlalchemy import select, insert, update, delete
>
> # Knex: knex("users").where("id", id).first()
> stmt = select(users_table).where(users_table.c.id == id)
> result = await conn.execute(stmt)
>
> # Knex: knex("users").insert({ name: "Alice" })
> stmt = insert(users_table).values(name="Alice")
> await conn.execute(stmt)
> ```

## Knex 基本查詢語法

```js
// SELECT
const user = await knex("users").where({ id: userId }).first();
const users = await knex("users").where("age", ">", 18).orderBy("name");

// INSERT
const [id] = await knex("users").insert({ name: "Alice", email: "alice@example.com" });

// UPDATE
await knex("users").where({ id: userId }).update({ name: "Bob" });

// DELETE
await knex("users").where({ id: userId }).delete();

// Raw SQL
const result = await knex.raw("SELECT * FROM users WHERE id = ?", [userId]);

// Transaction
await knex.transaction(async (trx) => {
    await trx("accounts").where({ id: fromId }).decrement("balance", amount);
    await trx("accounts").where({ id: toId }).increment("balance", amount);
    // 如果任何一個 throw，整個 transaction rollback
});
```

> **Python 類比**：
> ```python
> # SELECT
> result = await conn.execute(select(User).where(User.id == user_id))
> user = result.first()
>
> # INSERT
> await conn.execute(insert(User).values(name="Alice", email="alice@example.com"))
>
> # Transaction
> async with session.begin():
>     await session.execute(
>         update(Account).where(Account.id == from_id).values(balance=Account.balance - amount)
>     )
>     await session.execute(
>         update(Account).where(Account.id == to_id).values(balance=Account.balance + amount)
>     )
> # 離開 with，自動 commit；有例外則 rollback
> ```

## 讀寫分離 (Read-Write Splitting)

寫入操作 → knex（主資料庫）
讀取操作 → readonlyKnex（唯讀副本，分散負載）

### 為什麼要分主資料庫和唯讀副本

只有一台 MySQL 的情況：

```
所有操作都打同一台
  │
  ├── 寫入（INSERT/UPDATE/DELETE）──→ MySQL 主資料庫
  ├── 讀取（SELECT）────────────────→ MySQL 主資料庫  ← 全部擠在一起
  │
  └── 當讀取量很大時 → CPU/IO 被讀取佔滿 → 寫入變慢 → 整體效能下降
```

加上 Read Replica（唯讀副本）：

```
MySQL 主資料庫 (Primary)
  │
  │  自動同步資料（AWS RDS 幫你做）
  ▼
MySQL 唯讀副本 (Read Replica)

寫入 → 主資料庫       （只有這台能寫）
讀取 → 唯讀副本       （分散到這台，減輕主資料庫壓力）
```

### 對應到 code

```js
// repo 同時接收兩個連線
userRepo: createUserRepo(
  knex,                    // 第一個參數：寫入用（主資料庫）
  readonlyKnex ?? knex,    // 第二個參數：讀取用（唯讀副本，沒有的話就用主資料庫）
)

userRepo.create(...)   → 用 knex         → 打主資料庫
userRepo.findById(...) → 用 readonlyKnex → 打唯讀副本
```

> **Python 類比**：
> ```python
> # 同樣的概念
> primary_engine = create_engine("mysql://primary-host/db")    # 寫入
> readonly_engine = create_engine("mysql://replica-host/db")   # 讀取
>
> class UserRepo:
>     def __init__(self, write_engine, read_engine):
>         self.write_engine = write_engine
>         self.read_engine = read_engine
>
>     async def create(self, user):
>         async with self.write_engine.connect() as conn:   # 寫 → 主資料庫
>             await conn.execute(insert(User).values(**user))
>
>     async def find_by_id(self, id):
>         async with self.read_engine.connect() as conn:    # 讀 → 唯讀副本
>             result = await conn.execute(select(User).where(User.id == id))
>             return result.first()
> ```

### 適合場景

| 場景 | 讀寫比例 | 適合讀寫分離？ |
|---|---|---|
| 電商瀏覽商品 | 讀 95% / 寫 5% | 非常適合 |
| 社群媒體看貼文 | 讀 90% / 寫 10% | 適合 |
| 推論系統結果查詢 | 讀 80% / 寫 20% | 適合 |
| 狀態追蹤（頻繁寫完馬上讀） | 讀寫相近 | 幫助有限 |
| 即時聊天（大量寫入訊息） | 讀 50% / 寫 50% | 幫助有限 |

### 同步延遲要注意

```
主資料庫寫入 → 0.1 秒後 → 唯讀副本才同步到

如果寫完馬上讀：
  寫入主資料庫：status = "Success"     ← 已更新
  馬上從副本讀：status = "Pending"     ← 還沒同步到！（舊資料）
```

這就是為什麼頻繁寫完立即讀的 repo 不適合用讀寫分離：

```js
// 讀取量大的 repo — 有用讀寫分離（設定很少改，讀取多）
userRepo: createUserRepo(knex, readonlyKnex ?? knex)

// 狀態 repo — 沒有用，讀寫都用主資料庫（因為寫完常常馬上要讀最新狀態）
jobRepo: new MySqlJobRepo(knex)
```

> **Python 類比**：推論系統中同樣的問題
> ```python
> # 推論結果寫入後立刻查狀態 → 不適合讀寫分離
> await inference_repo.save_result(job_id, result)        # 寫主庫
> status = await inference_repo.get_status(job_id)        # 如果讀副本，可能還是 "running"！
>
> # 解法：寫完之後的讀，強制走主庫
> status = await inference_repo.get_status(job_id, use_primary=True)
> ```

## Knex Migration（資料庫版本控制）

```js
// 建立 migration 檔案
// migrations/20240101_create_users.js
exports.up = async (knex) => {
    await knex.schema.createTable("users", (table) => {
        table.increments("id").primary();
        table.string("name").notNullable();
        table.string("email").unique();
        table.timestamps(true, true);
    });
};

exports.down = async (knex) => {
    await knex.schema.dropTable("users");
};
```

> **Python 類比**：Alembic migration
> ```python
> # alembic/versions/xxxx_create_users.py
> def upgrade():
>     op.create_table(
>         "users",
>         sa.Column("id", sa.Integer, primary_key=True),
>         sa.Column("name", sa.String(255), nullable=False),
>         sa.Column("email", sa.String(255), unique=True),
>     )
>
> def downgrade():
>     op.drop_table("users")
> ```

## Python 等價做法總覽

```python
# 讀寫分離完整範例
primary_engine = create_engine("mysql://primary-host/db", pool_size=10)
readonly_engine = create_engine("mysql://replica-host/db", pool_size=10)

class UserRepo:
    def create(self, user):
        with primary_engine.connect() as conn:   # 寫 → 主資料庫
            conn.execute(insert(...))

    def find_by_id(self, id):
        with readonly_engine.connect() as conn:  # 讀 → 唯讀副本
            return conn.execute(select(...))
```
