---
sidebar_position: 2
---

# DynamoDB 不需要 Connection Pool

DynamoDB 不需要 connection pool，跟 SQL 資料庫的運作方式完全不同。

## SQL（SQLAlchemy）

```
SQLAlchemy → 建立 TCP 連線 → 保持住 → 重複使用
                ↓
         Connection Pool（例如 pool_size=5）
         維持 5 條活著的 TCP 連線，避免每次都重新建立
```

因為 SQL 資料庫（MySQL/PostgreSQL）是有狀態的 TCP 長連線，建立連線的成本高，所以需要 pool。

## DynamoDB（NoSQL，AWS 託管服務）

```
DynamoDBClient → 每次操作 → 發一個 HTTPS request → 結束
                              ↓
                     就像呼叫 REST API 一樣
```

DynamoDB 是透過 HTTPS API 溝通的，每次操作就是一個 HTTP request，無狀態、不需要維持連線。所以：

- 不需要 connection pool
- 不需要 close()
- 建立 `new DynamoDBClient()` 很輕量，只是設定好 region、credentials 等

## 類比

|             | MySQL (SQLAlchemy) | DynamoDB |
|---|---|---|
| 協定 | TCP 長連線 | HTTPS（無狀態） |
| 連線成本 | 高（握手、認證） | 低（就是 HTTP call） |
| 需要 Pool | 是 | 否 |
| Client 角色 | 管理連線池 | 只是一個 HTTP client 設定 |

## 範例

```ts
// 建立 DynamoDB client — 只是設定，不佔連線資源
const ddbClient = new DynamoDBClient({ region: 'us-east-1' });

// 每次操作都是獨立的 HTTPS request
const result = await ddbClient.send(new GetItemCommand({ ... }));
```

不需要像 MySQL 一樣管理 pool，用完也不用 `close()`。
