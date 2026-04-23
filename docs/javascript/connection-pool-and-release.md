---
sidebar_position: 7
---

# 連線池共用 & Release 資源管理

## 連線池是什麼

資料庫連線建立有成本（TCP handshake、認證），連線池預先建立一批連線，需要時借用、用完還回去，不用每次重新建立。

```
連線池（pool_size=10）
┌──────────────────────────────────┐
│  conn1  conn2  conn3  ...  conn10 │
└──────────────────────────────────┘
       ↓借出           ↑還回
  request 使用     request 完成
```

> **Python 類比（SQLAlchemy）**：
> ```python
> from sqlalchemy import create_engine
>
> # 建立連線池（pool_size=10 表示最多 10 條同時存在的連線）
> engine = create_engine(
>     "mysql+pymysql://user:pass@host/db",
>     pool_size=10,
>     max_overflow=5,    # 超過 pool_size 時最多再多開 5 條
>     pool_timeout=30,   # 等待連線的超時時間（秒）
> )
> ```

## 為什麼需要手動 release

Node.js 的連線池如果不手動關閉，process 會掛在那邊不會結束：

```
main() 結束了
  ↓
但 knex 連線池還活著（背景維持 TCP 連線到 MySQL）
  ↓
Node.js 覺得「還有事情在跑」→ process 不會退出 → 服務卡住
```

所以用 `try/finally` 確保一定會清理：

```js
try {
  await worker.run();         // 跑到 SIGTERM 才會結束
} finally {
  await release();            // Redis disconnect + MySQL destroy
  await brokerClient.close(); // Message queue client 關閉
}
```

> **Python 類比**：Python 慣用 `with` 語法（context manager）自動處理，但底層邏輯相同：
> ```python
> # Python — with 自動關閉（等同 try/finally）
> async with engine.connect() as conn:
>     await conn.execute(...)
> # 離開 with，__aexit__ 自動呼叫 conn.close()，連線還回池
>
> # 或手動清理（等同 knex.destroy()）
> engine.dispose()   # 關閉連線池，等所有連線都還回來後釋放
> ```

## Acquire / Release 模式與 Pool Exhaustion

連線池有固定上限，沒有 release 會導致 pool exhaustion（連線池耗盡）：

```
pool_size = 10

request1 借走 conn1   → 沒有 release
request2 借走 conn2   → 沒有 release
...
request10 借走 conn10 → 沒有 release

request11 來了 → 池子空了 → 等待 timeout → 報錯！
```

```js
// ❌ 沒有 release — pool exhaustion 風險
async function getUser(id) {
    const conn = await pool.acquire();
    const user = await conn.query("SELECT * FROM users WHERE id = ?", [id]);
    return user;
    // conn 沒有還回去！
}

// ✅ try/finally 確保一定 release
async function getUser(id) {
    const conn = await pool.acquire();
    try {
        return await conn.query("SELECT * FROM users WHERE id = ?", [id]);
    } finally {
        pool.release(conn);  // 不管成功或失敗，一定執行
    }
}
```

> **Python 類比**：SQLAlchemy 的 `with` 語法就是在幫你做 `try/finally`：
> ```python
> # ❌ 沒有 release
> async def get_user(id):
>     conn = await engine.connect()
>     user = await conn.execute(select(User).where(User.id == id))
>     return user
>     # conn 沒有 close！
>
> # ✅ with 自動 release
> async def get_user(id):
>     async with engine.connect() as conn:
>         return await conn.execute(select(User).where(User.id == id))
>     # 離開 with 自動 close，連線還回池
>
> # ✅ 等同手動 try/finally
> async def get_user(id):
>     conn = await engine.connect()
>     try:
>         return await conn.execute(select(User).where(User.id == id))
>     finally:
>         await conn.close()   # 一定執行，還回池
> ```

## Node.js vs Python 連線池比較

| | Node.js (Knex) | Python (SQLAlchemy) |
|---|---|---|
| 建立連線池 | `knex({ pool: { min: 2, max: 10 } })` | `create_engine(..., pool_size=10)` |
| 關閉連線池 | `knex.destroy()` | `engine.dispose()` |
| 自動管理連線 | 無原生語法，用 try/finally | `with engine.connect() as conn:` |
| 不關會怎樣 | process 不會退出 | process 不會退出 |
| Pool exhaustion | 等待 acquireTimeoutMillis 後報錯 | 等待 pool_timeout 後報錯 |

## 連線池共用：一個池給多個 Repo

```
createRepos()
  │
  ├── knex（主資料庫連線池）─── 一個池，多個 repo 共用
  │     │
  │     ├── userRepo         → 寫入用這個
  │     ├── orderRepo        → 讀寫都用這個
  │     └── productRepo      → 讀寫都用這個
  │
  └── readonlyKnex（唯讀連線池）─── 只有讀取 repo 用
        │
        └── userRepo         → 讀取用這個（唯讀副本）
```

> **Python 類比**：
> ```python
> # 一個 engine = 一個連線池
> primary_engine = create_engine("mysql://primary/db", pool_size=10)
> readonly_engine = create_engine("mysql://replica/db", pool_size=10)
>
> # 多個 repo 共用同一個 primary_engine 的連線池
> user_repo = UserRepo(write=primary_engine, read=readonly_engine)
> order_repo = OrderRepo(primary_engine)     # 共用同一個池
> product_repo = ProductRepo(primary_engine) # 共用同一個池
> ```

### 共用連線池的好處

```
如果每個 repo 各自建連線池：
  userRepo    → 10 條連線
  orderRepo   → 10 條連線
  productRepo → 10 條連線
  總共 30 條 ← 浪費，大部分時間閒置

共用一個連線池：
  三個 repo 共用  → 10 條連線
  誰需要就拿，用完就還 ← 更高效
```

## JS 沒有 `with` 語法的替代方案

JS/TS 沒有像 Python `with` 那麼方便的語法來管理連線池生命週期，常見的替代模式：

```ts
// 模式 1：回傳 release 函式 + try/finally（最常見）
const { repos, release } = await createRepos(config);
try {
    await runWorker(repos);
} finally {
    await release();
}

// 模式 2：callback 風格（類似 Python with 的感覺）
await withConnection(pool, async (conn) => {
    // conn 在這個 callback 裡使用
    return await conn.query(...);
    // callback 結束後自動 release
});

// 模式 3：Symbol.asyncDispose（TypeScript 5.2+ 的新語法，類似 Python with）
await using conn = await pool.acquire();
// 離開作用域自動呼叫 conn[Symbol.asyncDispose]()
```

> **Python 類比**：模式 2 的 callback 風格等同於 Python 手刻 context manager：
> ```python
> from contextlib import asynccontextmanager
>
> @asynccontextmanager
> async def get_connection(pool):
>     conn = await pool.acquire()
>     try:
>         yield conn
>     finally:
>         await pool.release(conn)
>
> # 使用
> async with get_connection(pool) as conn:
>     await conn.execute(...)
> ```
