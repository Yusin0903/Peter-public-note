---
sidebar_position: 2
---

# DynamoDB Doesn't Need a Connection Pool

DynamoDB does not need a connection pool — it works completely differently from SQL databases.

> **Python analogy**:
> - SQL (PostgreSQL) = `requests.Session()` — establish once, keep alive, reuse
> - DynamoDB = `requests.get(url)` — every call is an independent HTTP request, no state to maintain

---

## SQL (SQLAlchemy)

```python
# SQL needs a connection pool
# TCP connection setup is expensive, so keep a pool of live connections to reuse

from sqlalchemy import create_engine

engine = create_engine(
    "postgresql://user:pass@host/db",
    pool_size=5,        # maintain 5 live TCP connections
    max_overflow=10,    # allow up to 10 extra
)
# Connections in the pool stay alive, avoiding repeated TCP handshakes
```

```
SQLAlchemy → establish TCP connection → keep alive → reuse
                ↓
         Connection Pool (e.g. pool_size=5)
         Maintains 5 live TCP connections to avoid reconnecting every time
```

---

## DynamoDB (NoSQL, AWS managed service)

```python
# DynamoDB doesn't need a connection pool
# Each operation is an HTTPS request, just like calling a REST API

import boto3

# Creating a client is lightweight — just sets region and credentials
# No TCP connection is established, no pool
dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
table = dynamodb.Table("my-table")

# Each operation = one independent HTTPS request
response = table.get_item(Key={"id": "123"})
# No close() needed, no connection to return to a pool
```

```
DynamoDBClient → each operation → one HTTPS request → done
                                   ↓
                          Just like calling a REST API
```

---

## Comparison

| | MySQL (SQLAlchemy) | DynamoDB (boto3) |
|---|---|---|
| Protocol | TCP long-lived connection | HTTPS (stateless) |
| Connection cost | High (handshake, auth) | Low (just an HTTP call) |
| Needs pool | Yes | No |
| Python analogy | `requests.Session()` | `requests.get()` |
| close() needed | Yes (or use context manager) | No |

---

## Practical Impact for Python Inference Systems

```python
# ❌ Unnecessary: treating DynamoDB client like a SQL connection
class InferenceService:
    def __init__(self):
        self._ddb = None  # thinking we need to manage connection lifecycle

    def get_config(self, key):
        if self._ddb is None:
            self._ddb = boto3.resource("dynamodb")
        ...

# ✅ Correct: module-level singleton, just use it
import boto3

_table = boto3.resource("dynamodb", region_name="us-east-1").Table("config")

def get_config(key: str) -> dict:
    response = _table.get_item(Key={"key": key})
    return response.get("Item", {})
# No pool, no close(), every call is just one HTTPS request
```
