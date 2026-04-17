---
sidebar_position: 1
---

# Python Context Manager

## 基本用法

`@contextmanager` 讓你用 generator 寫 context manager，不需要實作 `__enter__` / `__exit__`：

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

# 使用
with db_context():
    result = db.execute(query)
```

## 巢狀 Context Manager

Context manager 可以巢狀使用，執行順序由外到內進入，由內到外離開：

```python
@contextmanager
def get_db_context():
    db_manager = init_db()
    with db_manager.connection_context():  # 內層
        yield                              # 控制權交給外層 with 區塊

# 使用
with get_db_context():           # 外層
    for item in items:
        process(item)
```

執行順序：
1. 進入外層 `get_db_context()` → 初始化 db_manager
2. 進入內層 `connection_context()` → 建立 DB 連線
3. `yield` → 執行 `with` 區塊內的程式碼
4. 離開內層 `connection_context()` → 關閉 DB 連線
5. 離開外層 `get_db_context()` → 清理資源

## DB Connection Context Manager

管理 DB 連線生命週期，確保連線正確關閉：

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

## 為什麼需要 Context Manager

不用 context manager 的問題：

```python
# ❌ 如果中間出現 exception，connection 不會被關閉
db.connect()
result = db.execute(risky_query())  # 可能 raise
db.close()  # 永遠執行不到

# ✅ 用 context manager 確保一定關閉
with db_context():
    result = db.execute(risky_query())  # 即使 raise，finally 還是會執行
```

## Python vs JS 比較

| | Python | JavaScript |
|---|---|---|
| 自動關閉 | `with` 語法 | `try/finally` |
| 資源管理 | Context Manager | 回傳 release 函式 |
| 語法糖 | `@contextmanager` | 無直接等價 |
