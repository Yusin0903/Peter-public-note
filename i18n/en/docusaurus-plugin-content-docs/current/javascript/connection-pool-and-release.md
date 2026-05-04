---
sidebar_position: 7
---

# Connection Pool Sharing & Release

## Why Manual Release Is Needed

If you don't close a Node.js connection pool, the process won't exit:

```
main() finishes
  ↓
But knex connection pool is still alive (maintaining TCP connections to MySQL in the background)
  ↓
Node.js thinks "something is still running" → process doesn't exit → service hangs
```

Use `try/finally` to guarantee cleanup:

```js
try {
  await worker.run();         // runs until SIGTERM
} finally {
  await release();            // Redis disconnect + MySQL destroy
  await brokerClient.close(); // message queue client close
}
```

## Comparison with Python

|            | Node.js (Knex)    | Python (SQLAlchemy) |
|------------|-------------------|---------------------|
| Close method | knex.destroy()  | engine.dispose()    |
| Without closing | process won't exit | process won't exit |
| Auto-close? | No              | No                  |

Python's context manager handles this automatically:

```python
# Python — with auto-closes
async with engine.connect() as conn:
    ...
# leaving the with block auto-closes

# or manually
engine.dispose()  # ← equivalent to knex.destroy()
```

JS/TS doesn't have a syntax as convenient as Python's `with` for managing connection pool lifetimes, so the "return a release function + try/finally" pattern achieves the same effect.

## Sharing a Pool: One Pool for Multiple Repos

```
createRepos()
  │
  ├── knex (primary DB connection pool) ─── one pool, shared by multiple repos
  │     │
  │     ├── userRepo         → writes use this
  │     ├── orderRepo        → reads and writes use this
  │     └── productRepo      → reads and writes use this
  │
  └── readonlyKnex (read-only pool) ─── only used by userRepo
        │
        └── userRepo         → reads use this (read replica)
```

### Python Equivalent

```python
# one engine = one connection pool
primary_engine = create_engine("mysql://primary/db", pool_size=10)
readonly_engine = create_engine("mysql://replica/db", pool_size=10)

# multiple repos share the same primary_engine pool
user_repo = UserRepo(write=primary_engine, read=readonly_engine)
order_repo = OrderRepo(primary_engine)    # shares same pool
product_repo = ProductRepo(primary_engine) # shares same pool
```

### Benefits of Sharing a Pool

```
If each repo had its own pool:
  userRepo    → 10 connections
  orderRepo   → 10 connections
  productRepo → 10 connections
  Total: 30 ← wasteful, mostly idle

Sharing one pool:
  Three repos share  → 10 connections
  whoever needs one takes it, returns it when done ← more efficient
```
