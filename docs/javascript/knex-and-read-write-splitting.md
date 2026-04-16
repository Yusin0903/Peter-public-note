---
sidebar_position: 8
---

# Knex（JS 版的 SQLAlchemy）& 讀寫分離

## Knex 基本概念

Knex 是 Node.js 的 SQL query builder，定位類似 Python 的 SQLAlchemy。

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

### 適合場景

| 場景 | 讀寫比例 | 適合讀寫分離？ |
|---|---|---|
| 電商瀏覽商品 | 讀 95% / 寫 5% | 非常適合 |
| 社群媒體看貼文 | 讀 90% / 寫 10% | 適合 |
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

## Python 等價做法

```python
# 同樣的概念
primary_engine = create_engine("mysql://primary-host/db")    # 寫入
readonly_engine = create_engine("mysql://replica-host/db")   # 讀取

class UserRepo:
    def create(self, user):
        with primary_engine.connect() as conn:   # 寫 → 主資料庫
            conn.execute(insert(...))

    def find_by_id(self, id):
        with readonly_engine.connect() as conn:  # 讀 → 唯讀副本
            return conn.execute(select(...))
```
