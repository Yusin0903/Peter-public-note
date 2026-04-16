---
sidebar_position: 7
---

# 連線池共用 & Release 資源管理

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

## 跟 Python 的比較

|            | Node.js (Knex)   | Python (SQLAlchemy) |
|------------|------------------|---------------------|
| 關閉方式   | knex.destroy()   | engine.dispose()    |
| 不關會怎樣 | process 不會退出 | process 不會退出    |
| 自動關閉？ | 不會             | 不會                |

Python 你可能習慣用 context manager 自動處理：

```python
# Python — with 自動關閉
async with engine.connect() as conn:
    ...
# 離開 with 自動 close

# 或手動
engine.dispose()  # ← 等於 knex.destroy()
```

JS/TS 沒有像 Python `with` 那麼方便的語法來管理連線池生命週期，所以用「回傳 release 函式 + try/finally」的模式來達到一樣的效果。

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
  └── readonlyKnex（唯讀連線池）─── 只有 userRepo 用
        │
        └── userRepo         → 讀取用這個（唯讀副本）
```

### Python 等價

```python
# 一個 engine = 一個連線池
primary_engine = create_engine("mysql://primary/db", pool_size=10)
readonly_engine = create_engine("mysql://replica/db", pool_size=10)

# 多個 repo 共用同一個 primary_engine 的連線池
user_repo = UserRepo(write=primary_engine, read=readonly_engine)
order_repo = OrderRepo(primary_engine)    # 共用同一個池
product_repo = ProductRepo(primary_engine) # 共用同一個池
```

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
