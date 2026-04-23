---
sidebar_position: 2
---

# DynamoDB 不需要 Connection Pool

DynamoDB 不需要 connection pool，跟 SQL 資料庫的運作方式完全不同。

> **Python 類比**：
> - SQL（PostgreSQL）= `requests.Session()`，建立一次連線，保持住，重複使用
> - DynamoDB = `requests.get(url)`，每次都是獨立的 HTTP call，不需要維持狀態

---

## SQL（SQLAlchemy）

```python
# SQL 需要 connection pool
# 建立 TCP 連線成本高，所以預先建好一批連線放著重複使用

from sqlalchemy import create_engine

engine = create_engine(
    "postgresql://user:pass@host/db",
    pool_size=5,        # 維持 5 條活著的 TCP 連線
    max_overflow=10,    # 最多再借 10 條
)
# pool 裡的連線一直活著，避免每次都重新 TCP handshake
```

```
SQLAlchemy → 建立 TCP 連線 → 保持住 → 重複使用
                ↓
         Connection Pool（例如 pool_size=5）
         維持 5 條活著的 TCP 連線，避免每次都重新建立
```

---

## DynamoDB（NoSQL，AWS 託管服務）

```python
# DynamoDB 不需要 connection pool
# 每次操作就是一個 HTTPS request，跟呼叫 REST API 一樣

import boto3

# 建立 client 很輕量，只是設定 region、credentials
# 不會建立 TCP 連線，也不會有 pool
dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
table = dynamodb.Table("my-table")

# 每次操作 = 一個獨立的 HTTPS request
response = table.get_item(Key={"id": "123"})
# 用完不需要 close()，也沒有連線要歸還到 pool
```

```
DynamoDBClient → 每次操作 → 發一個 HTTPS request → 結束
                              ↓
                     就像呼叫 REST API 一樣
```

---

## 對比表

| | MySQL (SQLAlchemy) | DynamoDB (boto3) |
|---|---|---|
| 協定 | TCP 長連線 | HTTPS（無狀態） |
| 連線成本 | 高（握手、認證） | 低（就是 HTTP call） |
| 需要 Pool | 是 | 否 |
| Python 類比 | `requests.Session()` | `requests.get()` |
| close() | 需要（或用 context manager） | 不需要 |

---

## Python inference system 的實際影響

```python
# ❌ 不必要的做法：把 DynamoDB client 當 SQL connection 管理
class InferenceService:
    def __init__(self):
        self._ddb = None  # 以為需要管理連線生命週期

    def get_config(self, key):
        if self._ddb is None:
            self._ddb = boto3.resource("dynamodb")
        ...

# ✅ 正確做法：module-level singleton，直接用就好
import boto3

_table = boto3.resource("dynamodb", region_name="us-east-1").Table("config")

def get_config(key: str) -> dict:
    response = _table.get_item(Key={"key": key})
    return response.get("Item", {})
# 不需要 pool，不需要 close，每次呼叫就是一個 HTTPS request
```
