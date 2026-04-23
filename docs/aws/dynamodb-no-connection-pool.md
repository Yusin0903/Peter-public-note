---
sidebar_position: 2
---

# DynamoDB 深度指南

DynamoDB 不需要 connection pool，跟 SQL 資料庫的運作方式完全不同。但在理解這件事之前，先要知道 DynamoDB 的資料模型——它根本不像 SQL table。

---

## DynamoDB 資料模型

### 核心概念：Table、Item、Partition Key、Sort Key

```
DynamoDB Table
├── Item（就像一筆 dict，沒有固定 schema）
│   ├── Partition Key（必填，決定資料放在哪台機器）
│   ├── Sort Key（選填，同一 Partition 下的排序鍵）
│   └── 其他屬性（任意 key-value，每筆 Item 可以不一樣）
```

> **Python 類比**：DynamoDB Table 就像一個以 dict 組成的 dict，每筆 Item 是一個 Python dict，而 Partition Key 是外層 dict 的 key。
>
> ```python
> # DynamoDB Table 的心智模型
> table = {
>     # Partition Key = "job_123"（決定存在哪台機器）
>     "job_123": {
>         "job_id": "job_123",          # Partition Key
>         "status": "running",
>         "model": "resnet50",
>         "created_at": "2026-04-23",
>     },
>     "job_456": {
>         "job_id": "job_456",
>         "status": "done",
>         "result": {"score": 0.95},    # 這筆有 result，上面那筆沒有 → 完全合法
>     }
> }
> ```

### Partition Key + Sort Key 組合鍵

當你需要「一個 user 有多筆 job」的結構時，用複合鍵：

```python
# 用法：user_id 作 Partition Key，job_id 作 Sort Key
# 這樣可以一次查出某個 user 的所有 job

item = {
    "user_id": "user_abc",     # Partition Key
    "job_id": "job_001",       # Sort Key
    "status": "done",
    "latency_ms": 234,
}

# 查詢：user_abc 的所有 job
response = table.query(
    KeyConditionExpression=Key("user_id").eq("user_abc")
)
# 回傳所有 Partition Key = "user_abc" 的 Items，按 Sort Key 排序

# 更精確查詢：user_abc 在特定時間後的 job
response = table.query(
    KeyConditionExpression=(
        Key("user_id").eq("user_abc") &
        Key("job_id").begins_with("2026-04")
    )
)
```

---

## Connection Pool 的本質差異

> **Python 類比**：
> - SQL（PostgreSQL）= `requests.Session()`，建立一次連線，保持住，重複使用
> - DynamoDB = `requests.get(url)`，每次都是獨立的 HTTP call，不需要維持狀態

### SQL（SQLAlchemy）— 需要 Connection Pool

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

### DynamoDB（NoSQL，AWS 託管服務）— 不需要 Pool

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

---

## boto3 常用操作模式

### get_item vs query vs scan

```python
import boto3
from boto3.dynamodb.conditions import Key, Attr

dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
table = dynamodb.Table("inference-jobs")

# 1. get_item：用完整 primary key 精確查詢，O(1)，最快
response = table.get_item(
    Key={
        "user_id": "user_abc",   # Partition Key
        "job_id": "job_001",     # Sort Key
    }
)
item = response.get("Item")  # 沒找到時回傳 None，不會拋例外

# 2. query：在同一個 Partition 內查詢，走 index，高效
response = table.query(
    KeyConditionExpression=Key("user_id").eq("user_abc"),
    FilterExpression=Attr("status").eq("done"),  # 注意：FilterExpression 在 query 後再過濾
    Limit=50,
)
items = response["Items"]

# 3. scan：全表掃描，非常慢，費用高，盡量不用
# ❌ 不要在生產環境 hot path 用 scan
response = table.scan(
    FilterExpression=Attr("status").eq("running")
)
# scan 會讀取全部資料再過濾，100萬筆全部讀出來只是為了找幾筆 "running" 的
```

> **Python 類比**：
> - `get_item` = `dict[key]`，O(1) 直接存取
> - `query` = `[x for x in dict.values() if x["user_id"] == "abc"]`，但只掃指定 Partition
> - `scan` = `[x for x in all_data if x["status"] == "running"]`，掃全部資料

### batch_write_item — 批次寫入

```python
# 一次 API call 寫入多筆，最多 25 筆
# 比逐筆寫便宜且快

with table.batch_writer() as batch:
    for job in jobs_to_insert:
        batch.put_item(Item={
            "job_id": job.id,
            "status": "pending",
            "model": job.model_name,
            "payload_s3": f"s3://bucket/inputs/{job.id}.json",
        })
# boto3 的 batch_writer 會自動處理 25 筆的限制和 retry

# 對比：逐筆寫
for job in jobs_to_insert:
    table.put_item(Item={...})  # 每次都是一個 HTTPS request，100 筆 = 100 個 request
```

### conditional_write — 防止競態條件

```python
from botocore.exceptions import ClientError

# 只有當 job 不存在時才寫入（防止重複建立）
try:
    table.put_item(
        Item={"job_id": "job_001", "status": "pending"},
        ConditionExpression="attribute_not_exists(job_id)",
    )
    print("建立成功")
except ClientError as e:
    if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
        print("job 已存在，跳過")
    else:
        raise

# 原子性地更新狀態（只有 status = "running" 才能改為 "done"）
try:
    table.update_item(
        Key={"job_id": "job_001"},
        UpdateExpression="SET #s = :done, finished_at = :ts",
        ConditionExpression="#s = :running",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={
            ":done": "done",
            ":running": "running",
            ":ts": "2026-04-23T10:30:00Z",
        },
    )
except ClientError as e:
    if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
        print("狀態不對，有人已經改過了")
```

---

## DynamoDB 什麼時候是壞選擇

**以下情況不要用 DynamoDB，改用 RDS：**

```python
# ❌ 需要跨 table JOIN
SELECT j.job_id, u.email
FROM inference_jobs j
JOIN users u ON j.user_id = u.id
WHERE j.status = 'done'
# DynamoDB 完全不支援 JOIN

# ❌ 需要聚合查詢
SELECT model_version, AVG(latency_ms), PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY latency_ms)
FROM inference_jobs
GROUP BY model_version
# DynamoDB 沒有 GROUP BY、AVG、percentile

# ❌ 查詢模式不固定（ad-hoc analytics）
# 每次都 scan 全表 → 費用爆炸、速度極慢

# ❌ 需要強一致的跨 item 事務
# DynamoDB 有 TransactWrite，但最多 100 個 item，且費用是普通寫的 2x
```

---

## 熱分區問題（Hot Partition）

**這是 DynamoDB 最常見的效能陷阱。**

DynamoDB 根據 Partition Key 將資料分散到不同機器。如果所有請求都打到同一個 Partition Key，那台機器就會被打爆。

```python
# ❌ 糟糕的設計：所有 inference job 用同一個 partition key
item = {
    "tenant_id": "company_a",   # Partition Key → 所有 company_a 的請求都到同一台機器
    "job_id": "job_001",        # Sort Key
    "status": "running",
}
# company_a 有 1000 個 worker 同時讀寫 → 熱分區 → 限速錯誤

# ✅ 好的設計方案一：讓 job_id 本身當 Partition Key（UUID，天然分散）
item = {
    "job_id": "550e8400-e29b-41d4-a716-446655440000",  # Partition Key（UUID）
    "tenant_id": "company_a",   # 普通屬性，用 GSI 查詢
    "status": "running",
}

# ✅ 好的設計方案二：Partition Key 加入隨機後綴分散
import random
shard = random.randint(0, 9)
partition_key = f"company_a#{shard}"  # 分成 10 個分區

# 查詢時要掃 10 個分區然後合併結果
# 麻煩一點，但避免熱分區
```

> **Python 類比**：就像 Python 的 `dict` 用 hash 分桶，如果所有 key 的 hash 值一樣，就全部堆在同一個 bucket，O(1) 退化成 O(n)。

---

## Python Inference System 的正確模式

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

_table = boto3.resource("dynamodb", region_name="us-east-1").Table("inference-jobs")

def get_job(job_id: str) -> dict | None:
    response = _table.get_item(Key={"job_id": job_id})
    return response.get("Item")  # 沒找到回傳 None

def update_job_status(job_id: str, status: str) -> None:
    _table.update_item(
        Key={"job_id": job_id},
        UpdateExpression="SET #s = :status",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":status": status},
    )
# 不需要 pool，不需要 close，每次呼叫就是一個 HTTPS request
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
| Join | 支援 | 不支援 |
| 聚合查詢 | 支援 | 不支援 |
| 最佳查詢模式 | 任意 SQL | 已知 primary key |
