---
sidebar_position: 2
---

# DynamoDB Doesn't Need a Connection Pool

DynamoDB does not need a connection pool — it works completely differently from SQL databases.

## SQL (SQLAlchemy)

```
SQLAlchemy → establish TCP connection → keep it alive → reuse it
                ↓
         Connection Pool (e.g. pool_size=5)
         Maintains 5 live TCP connections to avoid reconnecting every time
```

SQL databases (MySQL/PostgreSQL) use stateful long-lived TCP connections. Establishing a connection is expensive, so a pool is needed.

## DynamoDB (NoSQL, AWS managed service)

```
DynamoDBClient → each operation → send one HTTPS request → done
                                   ↓
                          Just like calling a REST API
```

DynamoDB communicates over HTTPS. Every operation is a single HTTP request — stateless, no connection to maintain. So:

- No connection pool needed
- No `close()` needed
- Creating `new DynamoDBClient()` is lightweight — just sets region, credentials, etc.

## Comparison

|             | MySQL (SQLAlchemy) | DynamoDB |
|---|---|---|
| Protocol | TCP long-lived connection | HTTPS (stateless) |
| Connection cost | High (handshake, auth) | Low (just an HTTP call) |
| Needs pool | Yes | No |
| Client role | Manages connection pool | Just an HTTP client config |

## Example

```ts
// Creating a DynamoDB client — just config, no connection overhead
const ddbClient = new DynamoDBClient({ region: 'us-east-1' });

// Each operation is an independent HTTPS request
const result = await ddbClient.send(new GetItemCommand({ ... }));
```

No need to manage a pool like MySQL. No `close()` needed after use.
