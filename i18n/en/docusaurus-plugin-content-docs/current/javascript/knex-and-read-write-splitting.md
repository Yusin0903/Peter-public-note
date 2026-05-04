---
sidebar_position: 8
---

# Knex (JS's SQLAlchemy) & Read-Write Splitting

## What Is Knex

Knex is a SQL query builder for Node.js, similar in role to Python's SQLAlchemy.

## Read-Write Splitting

Write operations → knex (primary database)
Read operations → readonlyKnex (read-only replica, distributes load)

### Why Have a Primary and a Read Replica

With only one MySQL instance:

```
All operations hit the same server
  │
  ├── Writes (INSERT/UPDATE/DELETE) ──→ MySQL primary
  ├── Reads (SELECT) ────────────────→ MySQL primary  ← everything piles up
  │
  └── When read volume is high → CPU/IO saturated by reads → writes slow down → overall performance drops
```

Adding a Read Replica:

```
MySQL primary
  │
  │  Auto sync data (AWS RDS does this for you)
  ▼
MySQL read replica

Writes → primary       (only this one can write)
Reads  → read replica  (offloaded here, relieves primary)
```

### In Code

```js
// repo accepts two connections
userRepo: createUserRepo(
  knex,                    // first param: writes (primary)
  readonlyKnex ?? knex,    // second param: reads (replica, falls back to primary if none)
)

userRepo.create(...)   → uses knex         → hits primary
userRepo.findById(...) → uses readonlyKnex → hits read replica
```

### When It Makes Sense

| Scenario | Read/Write Ratio | Good for Read-Write Splitting? |
|----------|:---:|:---:|
| E-commerce browsing products | Read 95% / Write 5% | Highly suitable |
| Social media viewing posts | Read 90% / Write 10% | Suitable |
| State tracking (frequent write then immediate read) | Close to 50/50 | Limited benefit |
| Real-time chat (heavy writes) | Read 50% / Write 50% | Limited benefit |

### Watch Out for Replication Lag

```
Primary writes → 0.1 seconds later → read replica syncs

If you read immediately after writing:
  Write to primary: status = "Success"     ← updated
  Immediately read from replica: status = "Pending"  ← not synced yet! (stale data)
```

This is why repos that frequently read right after writing aren't suited for read-write splitting:

```js
// High-read repo — uses read-write splitting (config rarely changes, lots of reads)
userRepo: createUserRepo(knex, readonlyKnex ?? knex)

// State repo — doesn't use it, both reads and writes hit primary
// (writes are often followed immediately by reading the latest state)
jobRepo: new MySqlJobRepo(knex)
```

## Python Equivalent

```python
primary_engine = create_engine("mysql://primary-host/db")    # writes
readonly_engine = create_engine("mysql://replica-host/db")   # reads

class UserRepo:
    def create(self, user):
        with primary_engine.connect() as conn:   # write → primary
            conn.execute(insert(...))

    def find_by_id(self, id):
        with readonly_engine.connect() as conn:  # read → read replica
            return conn.execute(select(...))
```
