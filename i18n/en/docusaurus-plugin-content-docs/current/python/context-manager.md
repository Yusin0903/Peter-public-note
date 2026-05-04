---
sidebar_position: 1
---

# Python Context Manager

## Basic Usage

`@contextmanager` lets you write a context manager using a generator — no need to implement `__enter__` / `__exit__`:

```python
from contextlib import contextmanager

@contextmanager
def db_context():
    db.connect(reuse_if_open=True)
    try:
        yield
    finally:
        if not db.is_closed():
            db.close()

# Usage
with db_context():
    result = db.execute(query)
```

## Nested Context Managers

Context managers can be nested. Execution goes from outer to inner when entering, and inner to outer when exiting:

```python
@contextmanager
def get_db_context():
    db_manager = init_db()
    with db_manager.connection_context():  # inner
        yield                              # control returns to outer with block

# Usage
with get_db_context():           # outer
    for item in items:
        process(item)
```

Execution order:
1. Enter outer `get_db_context()` → initialize db_manager
2. Enter inner `connection_context()` → establish DB connection
3. `yield` → execute code inside the `with` block
4. Exit inner `connection_context()` → close DB connection
5. Exit outer `get_db_context()` → clean up resources

## DB Connection Context Manager

Manages the DB connection lifecycle to ensure connections are properly closed:

```python
@contextmanager
def connection_context(self):
    if self.db.is_closed():
        self.db.connect()
    try:
        yield
    except Exception:
        if not self.db.is_closed():
            self.db.rollback()
        raise
    finally:
        if not self.db.is_closed():
            self.db.close()
```

## Why Use Context Managers

Without a context manager, an exception can leave the connection open:

```python
# If an exception occurs, connection won't be closed
db.connect()
result = db.execute(risky_query())  # might raise
db.close()  # never reached

# With context manager, finally always runs
with db_context():
    result = db.execute(risky_query())  # even if it raises, finally executes
```

## Python vs JS Comparison

| | Python | JavaScript |
|---|---|---|
| Auto-close | `with` syntax | `try/finally` |
| Resource management | Context Manager | Return a release function |
| Syntactic sugar | `@contextmanager` | No direct equivalent |
