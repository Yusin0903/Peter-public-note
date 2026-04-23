---
sidebar_position: 1
---

# Python Context Manager

Context Manager 是 Python 資源管理的核心機制，保證資源（GPU 記憶體、DB 連線、檔案、HTTP session）在進入與離開程式區塊時被正確初始化與釋放，即使中途拋出例外也不例外。

## `__enter__` / `__exit__` 深入解析

用 class 實作 context manager 是最底層、最完整的做法：

```python
class ManagedResource:
    def __enter__(self):
        # 初始化資源，回傳值會被 as 子句接收
        print("取得資源")
        return self  # with ManagedResource() as r: r 就是 self

    def __exit__(self, exc_type, exc_val, exc_tb):
        # exc_type, exc_val, exc_tb：若 with 區塊內有例外，這三個就有值；否則全為 None
        print(f"釋放資源，例外類型：{exc_type}")

        # 回傳 True  → 吞掉例外，程式繼續執行
        # 回傳 False 或 None → 重新拋出例外（絕大多數情況應該這樣）
        if exc_type is ValueError:
            print("ValueError 被吞掉了，程式繼續")
            return True   # suppress
        return False      # re-raise 其他例外
```

**`__exit__` 的例外處理策略：**

```python
class DatabaseConnection:
    def __init__(self, dsn: str):
        self.dsn = dsn
        self.conn = None

    def __enter__(self):
        self.conn = connect(self.dsn)
        return self.conn

    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type is not None:
            # 有例外 → rollback，然後讓例外繼續往上傳播
            self.conn.rollback()
            print(f"Transaction rolled back due to: {exc_val}")
        else:
            # 正常結束 → commit
            self.conn.commit()

        self.conn.close()
        return False  # 不吞例外，讓呼叫者知道發生了什麼事
```

| `__exit__` 回傳值 | 行為 |
|---|---|
| `True` | 例外被吞掉，`with` 之後的程式碼繼續執行 |
| `False` 或 `None` | 例外繼續往外拋出 |

---

## `@contextmanager` 裝飾器模式

用 generator 寫 context manager，比 class 寫法更簡潔：

```python
from contextlib import contextmanager

@contextmanager
def db_context(dsn: str):
    conn = connect(dsn)
    try:
        yield conn          # yield 前 = __enter__；yield 的值 = as 的值
    except Exception as e:
        conn.rollback()
        raise               # 一定要 re-raise，否則例外會被吞掉
    else:
        conn.commit()       # 正常結束才 commit
    finally:
        conn.close()        # 不論如何都關閉

# 使用
with db_context("postgresql://localhost/mydb") as conn:
    conn.execute("INSERT INTO orders VALUES (1, 'item_a')")
```

**`@contextmanager` 的例外處理規則：**

```python
@contextmanager
def risky_context():
    resource = acquire()
    try:
        yield resource
    except SpecificError:
        # 只攔截特定例外，處理後可選擇是否 re-raise
        handle_specific_error()
        # 不 raise → 相當於 __exit__ 回傳 True（吞掉例外）
    except Exception:
        # 其他例外一定要 re-raise
        release_with_error(resource)
        raise
    finally:
        release(resource)   # 永遠執行
```

---

## `@asynccontextmanager` 用於非同步推論服務

FastAPI / asyncio 環境下，async context manager 是標配：

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI
import httpx

# ---- 管理 HTTP client 生命週期 ----
@asynccontextmanager
async def lifespan(app: FastAPI):
    """FastAPI lifespan：啟動時初始化，關閉時清理"""
    # startup
    app.state.http_client = httpx.AsyncClient(timeout=30.0)
    app.state.model = await load_model_async()
    print("服務啟動完成")

    yield  # 服務運行中

    # shutdown
    await app.state.http_client.aclose()
    await unload_model_async(app.state.model)
    print("服務關閉，資源已釋放")

app = FastAPI(lifespan=lifespan)

# ---- 單次請求的 async context manager ----
@asynccontextmanager
async def async_db_session(pool):
    async with pool.acquire() as conn:
        async with conn.transaction():
            try:
                yield conn
            except Exception:
                # transaction 會自動 rollback（asyncpg 行為）
                raise

# 在 route handler 中使用
@app.post("/infer")
async def infer(request: InferRequest):
    async with async_db_session(app.state.pool) as session:
        result = await session.fetchrow("SELECT * FROM jobs WHERE id=$1", request.job_id)
    return result
```

---

## 實戰推論場景

### GPU 記憶體管理 Context Manager

```python
import torch
from contextlib import contextmanager

@contextmanager
def gpu_memory_guard(device: str = "cuda", empty_cache_on_exit: bool = True):
    """
    進入時記錄 GPU 記憶體，離開時釋放並報告使用量。
    在高頻推論服務中防止記憶體洩漏。
    """
    if not torch.cuda.is_available():
        yield
        return

    torch.cuda.synchronize(device)
    mem_before = torch.cuda.memory_allocated(device)

    try:
        yield
    finally:
        torch.cuda.synchronize(device)
        mem_after = torch.cuda.memory_allocated(device)
        delta_mb = (mem_after - mem_before) / 1024 ** 2
        print(f"GPU 記憶體變化: {delta_mb:+.1f} MB")

        if empty_cache_on_exit:
            torch.cuda.empty_cache()

# 使用
with gpu_memory_guard():
    output = model(input_tensor)
    result = postprocess(output)
# 離開 with 區塊後，GPU cache 自動清除
```

### 模型載入 Context Manager

```python
import torch
from contextlib import contextmanager
from pathlib import Path

@contextmanager
def temporary_model(model_path: str, device: str = "cuda"):
    """
    臨時載入一個模型，用完立即從 GPU 卸載。
    適合偶爾才用的大型模型（避免佔用 GPU 記憶體）。
    """
    model = None
    try:
        print(f"載入模型: {model_path}")
        model = torch.load(model_path, map_location=device)
        model.eval()
        yield model
    except FileNotFoundError:
        print(f"找不到模型: {model_path}")
        raise
    finally:
        if model is not None:
            del model
            if device == "cuda":
                torch.cuda.empty_cache()
            print(f"模型已卸載: {model_path}")

# 使用：只在這個區塊內持有模型
with temporary_model("/models/large_llm.pt") as model:
    with torch.no_grad():
        output = model(input_ids)
# 出了 with，模型立即從 GPU 記憶體消失
```

### 資料庫 Transaction Context Manager

```python
from contextlib import contextmanager
from typing import Generator
import psycopg2

class DatabaseManager:
    def __init__(self, dsn: str):
        self.dsn = dsn

    @contextmanager
    def transaction(self) -> Generator:
        """提供 ACID transaction，失敗自動 rollback"""
        conn = psycopg2.connect(self.dsn)
        cur = conn.cursor()
        try:
            yield cur
            conn.commit()
        except Exception as e:
            conn.rollback()
            print(f"Transaction 失敗，已 rollback: {e}")
            raise
        finally:
            cur.close()
            conn.close()

db = DatabaseManager("postgresql://user:pass@localhost/inference_db")

# 使用：異常自動 rollback
with db.transaction() as cur:
    cur.execute("INSERT INTO inference_logs VALUES (%s, %s, %s)",
                (job_id, model_name, result_json))
    cur.execute("UPDATE job_queue SET status='done' WHERE id=%s", (job_id,))
# 兩個 SQL 要嘛都成功，要嘛都 rollback
```

### HTTP Client Session Context Manager

```python
import httpx
from contextlib import asynccontextmanager

@asynccontextmanager
async def inference_client(base_url: str, timeout: float = 30.0):
    """
    管理推論服務之間的 HTTP client，確保連線正確關閉。
    使用 httpx 的 AsyncClient 而非每次建立新連線。
    """
    async with httpx.AsyncClient(
        base_url=base_url,
        timeout=timeout,
        headers={"Content-Type": "application/json"},
        limits=httpx.Limits(max_connections=100, max_keepalive_connections=20),
    ) as client:
        try:
            yield client
        except httpx.TimeoutException:
            print(f"呼叫 {base_url} 逾時")
            raise
        except httpx.HTTPStatusError as e:
            print(f"HTTP 錯誤 {e.response.status_code}: {e.response.text}")
            raise

# 使用
async def call_embedding_service(texts: list[str]) -> list[list[float]]:
    async with inference_client("http://embedding-service:8080") as client:
        response = await client.post("/embed", json={"texts": texts})
        response.raise_for_status()
        return response.json()["embeddings"]
```

---

## 巢狀 Context Manager

### 寫法一：多個 `with` 語句

```python
with open("input.txt") as fin:
    with open("output.txt", "w") as fout:
        fout.write(fin.read())
```

### 寫法二：單行多個（Python 3.10+ 可換行，更清晰）

```python
# Python 3.10+ 推薦寫法
with (
    gpu_memory_guard() as _,
    temporary_model("/models/llm.pt") as model,
    db.transaction() as cursor,
):
    output = model(input_tensor)
    cursor.execute("INSERT INTO logs VALUES (%s)", (str(output),))
```

**執行順序：**

```
進入順序（由左到右 / 由上到下）：
  1. gpu_memory_guard().__enter__()
  2. temporary_model().__enter__()  → model
  3. db.transaction().__enter__()  → cursor

離開順序（反向）：
  3. db.transaction().__exit__()   ← 先 commit/rollback
  2. temporary_model().__exit__()  ← 再卸載模型
  1. gpu_memory_guard().__exit__() ← 最後清 GPU cache
```

若其中一個 `__enter__` 拋出例外，已成功進入的 context manager 會依反向順序執行 `__exit__`。

---

## Context Manager vs try/finally：常見陷阱

### 陷阱 1：誤以為 try/finally 和 context manager 完全等價

```python
# try/finally 寫法 — 有個隱患
resource = acquire()
try:
    use(resource)
finally:
    release(resource)

# 問題：如果 acquire() 本身就拋出例外，
# finally 還是會執行，但 resource 根本沒被賦值！
# 這會導致 NameError: name 'resource' is not defined

# Context manager 的 __enter__ 拋出例外時，__exit__ 不會被呼叫
# 行為更直覺、更安全
```

### 陷阱 2：在 `@contextmanager` 中忘記 re-raise

```python
# ❌ 錯誤：例外被吞掉了
@contextmanager
def bad_context():
    resource = acquire()
    try:
        yield resource
    except Exception:
        release(resource)
        # 沒有 raise！例外消失了，呼叫者不知道出錯

# ✅ 正確：一定要 re-raise
@contextmanager
def good_context():
    resource = acquire()
    try:
        yield resource
    except Exception:
        release_with_error(resource)
        raise  # 讓例外繼續傳播
    else:
        release_normally(resource)
```

### 陷阱 3：context manager 不是萬能的資源隔離

```python
# ❌ 這樣無法隔離 GPU 記憶體
with gpu_memory_guard():
    # 如果這裡把 tensor 存到外部變數，離開 with 後記憶體不會釋放
    global_cache["result"] = model(input)  # tensor 仍被 global_cache 持有！

# ✅ 確保不把 tensor 洩漏到外部
with gpu_memory_guard():
    raw_output = model(input)
    result = raw_output.cpu().numpy().tolist()  # 轉成 Python 物件再傳出去
# 離開 with 後，raw_output 無人持有，torch.cuda.empty_cache() 才有效
```

---

## Python vs JS 比較

| | Python | JavaScript |
|---|---|---|
| 自動關閉 | `with` 語法 | `try/finally` |
| 資源管理 | Context Manager (`__enter__`/`__exit__`) | 回傳 release 函式 |
| 語法糖 | `@contextmanager` / `@asynccontextmanager` | 無直接等價 |
| 非同步支援 | `async with` + `@asynccontextmanager` | `await resource.open()` + `try/finally` |
| 多資源 | `with A() as a, B() as b:` | 巢狀 `try/finally` |
