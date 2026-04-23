---
sidebar_position: 2
---

# SQLAlchemy 2.0 完整指南（推論服務版）

## 基本查詢

| SQLAlchemy 2.0 Async ORM           | Raw SQL                         |
| ---------------------------------- | ------------------------------- |
| `select(Station)`                  | `SELECT * FROM station`         |
| `select(Station.id, Station.name)` | `SELECT id, name FROM station`  |
| `select(func.count())`             | `SELECT COUNT(*) FROM station`  |
| `select(func.count(Station.id))`   | `SELECT COUNT(id) FROM station` |

## WHERE 條件

| SQLAlchemy 2.0 Async ORM                                    | Raw SQL                                                 |
| ----------------------------------------------------------- | ------------------------------------------------------- |
| `select(Station).where(Station.id == 1)`                    | `SELECT * FROM station WHERE id = 1`                    |
| `select(Station).where(Station.name == "test")`             | `SELECT * FROM station WHERE name = 'test'`             |
| `select(Station).where(Station.is_active.is_(True))`        | `SELECT * FROM station WHERE is_active IS TRUE`         |
| `select(Station).where(~Station.is_deleted)`                | `SELECT * FROM station WHERE NOT is_deleted`            |
| `select(Station).where(Station.id > 5)`                     | `SELECT * FROM station WHERE id > 5`                    |
| `select(Station).where(Station.id.in_([1, 2, 3]))`          | `SELECT * FROM station WHERE id IN (1, 2, 3)`           |
| `select(Station).where(Station.name.like("%test%"))`        | `SELECT * FROM station WHERE name LIKE '%test%'`        |
| `select(Station).where(Station.value.is_(None))`            | `SELECT * FROM station WHERE value IS NULL`             |
| `select(Station).where(Station.value.is_not(None))`         | `SELECT * FROM station WHERE value IS NOT NULL`         |

## 多條件查詢

| SQLAlchemy 2.0 Async ORM                                                                           | Raw SQL                                                             |
|------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------|
| `select(Station).where(Station.name == "test", Station.is_deleted.is_(False))`                      | `SELECT * FROM station WHERE name = 'test' AND is_deleted IS FALSE` |
| `select(Station).where(or_(Station.id == 1, Station.name == "test"))`                               | `SELECT * FROM station WHERE id = 1 OR name = 'test'`               |
| `select(Station).where(and_(Station.id > 5, Station.id < 10))`                                      | `SELECT * FROM station WHERE id > 5 AND id < 10`                    |

## 排序

| SQLAlchemy 2.0 Async ORM                                         | Raw SQL                                            |
|------------------------------------------------------------------|----------------------------------------------------|
| `select(Station).order_by(Station.id.asc())`                     | `SELECT * FROM station ORDER BY id ASC`            |
| `select(Station).order_by(Station.id.desc())`                    | `SELECT * FROM station ORDER BY id DESC`           |

## 分頁

| SQLAlchemy 2.0 Async ORM                   | Raw SQL                                    |
|--------------------------------------------|--------------------------------------------|
| `select(Station).limit(10)`                | `SELECT * FROM station LIMIT 10`           |
| `select(Station).offset(20)`               | `SELECT * FROM station OFFSET 20`          |
| `select(Station).limit(10).offset(20)`     | `SELECT * FROM station LIMIT 10 OFFSET 20` |

## 聚合

| SQLAlchemy 2.0 Async ORM                    | Raw SQL                            |
| ------------------------------------------- | ---------------------------------- |
| `select(func.count()).select_from(Station)` | `SELECT COUNT(*) FROM station`     |
| `select(func.sum(Station.value))`           | `SELECT SUM(value) FROM station`   |
| `select(func.avg(Station.value))`           | `SELECT AVG(value) FROM station`   |
| `select(func.max(Station.value))`           | `SELECT MAX(value) FROM station`   |
| `select(func.min(Station.value))`           | `SELECT MIN(value) FROM station`   |

## 連接查詢

| SQLAlchemy 2.0 Async ORM                                                 | Raw SQL                                                                              |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------ |
| `select(Station).join(Group, Station.group_id == Group.id)`              | `SELECT * FROM station JOIN group ON station.group_id = group.id`                    |
| `select(Station).outerjoin(Group, Station.group_id == Group.id)`         | `SELECT * FROM station LEFT OUTER JOIN group ON station.group_id = group.id`         |

## UPDATE

寫入操作建議用 Core API（可讀性高、效能好）：

| SQLAlchemy 2.0 Core                                                          | Raw SQL                                                   |
| ---------------------------------------------------------------------------- | --------------------------------------------------------- |
| `update(Station).where(Station.id == id).values(group_id=0)`                | `UPDATE station SET group_id = 0 WHERE id = :id`          |

---

## Async SQLAlchemy（FastAPI 推論服務必讀）

FastAPI 是 async-first 框架，推論服務通常需要高並發，**必須用 AsyncSession**，否則會阻塞 event loop，把 async 的優勢全部抵消。

> **Python 類比**：同步的 `session.execute()` 就像 `requests.get()`，會阻塞整個執行緒。非同步的 `await session.execute()` 就像 `await asyncio.gather()`，可以同時處理多個請求。

### 安裝

```bash
pip install sqlalchemy[asyncio] asyncpg
```

### Engine 與 Session 設定

```python
# database.py
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase

# 注意：asyncpg driver，URL 前綴是 postgresql+asyncpg://
DATABASE_URL = "postgresql+asyncpg://user:pass@localhost/dbname"

engine = create_async_engine(
    DATABASE_URL,
    # 推論服務關鍵設定（詳見下方連線池章節）
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True,
    echo=False,  # 生產環境關掉，避免 log 爆炸
)

AsyncSessionLocal = sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,  # 推論服務重要設定，見下方說明
)

class Base(DeclarativeBase):
    pass
```

### FastAPI Dependency Injection

```python
# deps.py
from typing import AsyncGenerator
from sqlalchemy.ext.asyncio import AsyncSession
from .database import AsyncSessionLocal

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
```

### 在 Route 中使用

```python
# routes/inference.py
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from .deps import get_db
from .models import InferenceResult

router = APIRouter()

@router.get("/results/{job_id}")
async def get_result(
    job_id: str,
    db: AsyncSession = Depends(get_db)
):
    result = await db.execute(
        select(InferenceResult).where(InferenceResult.job_id == job_id)
    )
    return result.scalar_one_or_none()
```

### `expire_on_commit=False` 的重要性

預設行為：commit 後，ORM 物件的屬性會被標記為 expired，下次存取會觸發 lazy load（再查一次 DB）。在 async context 裡，這可能在 session 已關閉後觸發，導致 `MissingGreenlet` 或 `DetachedInstanceError`。

```python
# 危險：expire_on_commit=True（預設）
async with AsyncSessionLocal() as session:
    result = InferenceResult(job_id="abc", score=0.95)
    session.add(result)
    await session.commit()
    # commit 後 result.id 是 expired 狀態
    # 存取 result.id 會觸發 lazy load → 可能在 session 外存取 → 爆炸

# 安全：expire_on_commit=False
# commit 後物件屬性保留在記憶體，不觸發 lazy load
```

---

## Relationship 載入策略（N+1 問題）

N+1 問題是 ORM 最常見的效能陷阱：查 1 筆主記錄，再為每筆主記錄各發 1 次查詢取關聯資料，總共 N+1 次查詢。

> **Python 類比**：想像你有一個 list of job IDs，然後在 for loop 裡對每個 ID 呼叫 `requests.get(f"/result/{id}")`。正確做法是一次傳所有 ID：`requests.post("/results/batch", json={"ids": ids})`。

### 定義 Model 時指定預設載入策略

```python
from sqlalchemy import ForeignKey, String, Float
from sqlalchemy.orm import relationship, Mapped, mapped_column
from sqlalchemy.orm import selectinload, lazy

class InferenceJob(Base):
    __tablename__ = "inference_jobs"

    id: Mapped[int] = mapped_column(primary_key=True)
    model_name: Mapped[str] = mapped_column(String(100))

    # lazy="select"（預設）：存取時才查，有 N+1 風險
    # lazy="selectin"：自動用 IN 子查詢，一次載入所有關聯
    # lazy="joined"：用 JOIN，適合一對一
    # lazy="raise"：禁止 lazy load，強制明確載入（最嚴格，推薦生產使用）
    results: Mapped[list["InferenceResult"]] = relationship(
        back_populates="job",
        lazy="raise",  # 強制開發者明確指定載入方式
    )
```

### 查詢時明確指定載入策略

```python
from sqlalchemy.orm import selectinload, joinedload

# selectinload：發 2 次查詢（推薦，一對多）
# SELECT * FROM inference_jobs WHERE ...
# SELECT * FROM inference_results WHERE job_id IN (1, 2, 3, ...)
stmt = (
    select(InferenceJob)
    .where(InferenceJob.model_name == "gpt-4")
    .options(selectinload(InferenceJob.results))
)
jobs = (await db.execute(stmt)).scalars().all()

# joinedload：JOIN 一次查完（推薦，一對一或多對一）
# 注意：一對多用 joinedload 會有重複列的問題，用 selectinload 更安全
stmt = (
    select(InferenceResult)
    .options(joinedload(InferenceResult.job))
)
results = (await db.execute(stmt)).unique().scalars().all()
```

**推論服務的選擇**：
- 一對多（Job → Results）：用 **`selectinload`**
- 多對一（Result → Job）：用 **`joinedload`**
- 生產環境 model 定義：設 `lazy="raise"` 強制開發者明確載入，避免意外的 N+1

---

## 批量操作（推論結果大量寫入）

推論服務常需要一次寫入數百到數千筆結果，一筆一筆 `session.add()` 效能極差。

> **Python 類比**：一筆一筆 insert 就像用 `for` loop 呼叫 API，應該改成 batch API。`bulk_insert_mappings` 就是那個 batch API。

### 方法一：`insert().values()`（推薦，最快）

```python
from sqlalchemy import insert

async def store_batch_results(
    db: AsyncSession,
    results: list[dict]
) -> None:
    """
    results = [
        {"job_id": "abc", "score": 0.95, "label": "cat"},
        {"job_id": "def", "score": 0.72, "label": "dog"},
        ...
    ]
    """
    if not results:
        return

    await db.execute(
        insert(InferenceResult),
        results  # SQLAlchemy 會自動產生 executemany
    )
    await db.commit()
```

### 方法二：`bulk_insert_mappings`（SQLAlchemy 1.x 風格，仍可用）

```python
async def store_batch_results_v1(
    db: AsyncSession,
    results: list[dict]
) -> None:
    db.add_all([InferenceResult(**r) for r in results])
    await db.flush()
    await db.commit()
```

### 方法三：COPY（最終武器，百萬級資料）

直接用 PostgreSQL COPY 協定，比 INSERT 快 5-10 倍：

```python
import io
import csv
from sqlalchemy import text

async def bulk_copy_results(
    db: AsyncSession,
    results: list[dict]
) -> None:
    # 轉成 CSV buffer
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=["job_id", "score", "label"])
    writer.writerows(results)
    buf.seek(0)

    # asyncpg 原生 COPY
    conn = await db.connection()
    raw_conn = await conn.get_raw_connection()
    await raw_conn.driver_connection.copy_to_table(
        "inference_results",
        source=buf,
        columns=["job_id", "score", "label"],
        format="csv",
    )
```

**效能比較**（10,000 筆）：

| 方法 | 約略時間 |
|---|---|
| 一筆一筆 `session.add()` | ~5s |
| `insert().values()` with executemany | ~0.3s |
| PostgreSQL COPY | ~0.05s |

---

## Connection Pool 調優（推論服務）

推論服務通常有多個 worker（uvicorn workers 或 Celery workers），每個 worker 都需要連線池。**設錯連線池是推論服務最常見的線上故障原因之一。**

> **Python 類比**：連線池就像 `ThreadPoolExecutor` 的 `max_workers`，設太小請求排隊，設太大 PostgreSQL 撐不住。

```python
engine = create_async_engine(
    DATABASE_URL,

    # pool_size：維持的常駐連線數
    # 推論服務建議：CPU 核心數 * 2，或者直接設 10
    pool_size=10,

    # max_overflow：pool_size 不夠時額外允許的連線數
    # 短暫高峰可用，超過後新請求會等待
    # 建議：pool_size 的 2 倍
    max_overflow=20,

    # pool_timeout：等待可用連線的最長秒數
    # 超過就拋 TimeoutError，推論服務建議 30s
    pool_timeout=30,

    # pool_recycle：連線最長存活秒數
    # 防止 PostgreSQL server 端超時斷線導致的 stale connection
    # 建議比 PostgreSQL 的 idle timeout 短（通常設 1800）
    pool_recycle=1800,

    # pool_pre_ping：每次取出連線前，先發 SELECT 1 確認連線存活
    # 有輕微效能開銷，但能避免 stale connection 錯誤
    # 生產環境必開
    pool_pre_ping=True,
)
```

### 多 Worker 下的連線數計算

```
總連線數 = uvicorn_workers * (pool_size + max_overflow)

範例：4 workers * (10 + 20) = 最多 120 個連線
PostgreSQL 預設 max_connections = 100 → 會爆！

解法：
1. 調高 PostgreSQL max_connections（有記憶體代價）
2. 調小每個 worker 的 pool_size
3. 加 PgBouncer（見 postgresql-notes.md）
```

---

## Repository Pattern（推論服務的標準架構）

直接在 route 裡寫 SQLAlchemy 查詢，時間久了難以維護和測試。Repository Pattern 把資料庫操作封裝起來，讓 route 只關心業務邏輯。

> **Python 類比**：Repository 就像 Python 的 `dataclass` + method，把「如何存取資料」和「業務邏輯用資料做什麼」分離開來。

```python
# repositories/inference_result.py
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, insert, func
from ..models import InferenceResult

class InferenceResultRepository:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def get_by_job_id(self, job_id: str) -> Optional[InferenceResult]:
        result = await self.session.execute(
            select(InferenceResult)
            .where(InferenceResult.job_id == job_id)
        )
        return result.scalar_one_or_none()

    async def get_latest_by_model(
        self,
        model_name: str,
        limit: int = 100
    ) -> list[InferenceResult]:
        result = await self.session.execute(
            select(InferenceResult)
            .where(InferenceResult.model_name == model_name)
            .order_by(InferenceResult.created_at.desc())
            .limit(limit)
        )
        return result.scalars().all()

    async def bulk_create(self, results: list[dict]) -> None:
        await self.session.execute(
            insert(InferenceResult),
            results
        )

    async def count_by_model(self, model_name: str) -> int:
        result = await self.session.execute(
            select(func.count())
            .select_from(InferenceResult)
            .where(InferenceResult.model_name == model_name)
        )
        return result.scalar_one()
```

在 route 中使用：

```python
# routes/inference.py
@router.post("/results/batch")
async def store_batch(
    payload: BatchResultPayload,
    db: AsyncSession = Depends(get_db)
):
    repo = InferenceResultRepository(db)
    await repo.bulk_create(payload.results)
    return {"stored": len(payload.results)}
```

**優點**：
- Unit test 只需 mock `InferenceResultRepository`，不需要真實 DB
- 換 ORM 或換資料庫只改 repository，route 不動
- 查詢邏輯集中管理，容易 review

---

## 使用建議

- **讀取操作**（特別是複雜關聯查詢）→ 用 ORM + `selectinload`/`joinedload`
- **批量寫入**（推論結果入庫）→ 用 `insert().values()` with executemany
- **超大量寫入**（百萬級）→ 用 PostgreSQL COPY
- **效能關鍵路徑** → 用 Core API 或 raw SQL
- **推論服務架構** → 一定要 AsyncSession + Repository Pattern

---

## Reference

- [SQLAlchemy 2.0 官方 Expressions 文檔](https://docs.sqlalchemy.org/en/20/core/sqlelement.html)
- [SQLAlchemy 2.0 官方 Query Guide](https://docs.sqlalchemy.org/en/20/orm/queryguide/select.html)
- [SQLAlchemy Async ORM](https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html)
- [Relationship Loading Techniques](https://docs.sqlalchemy.org/en/20/orm/queryguide/relationships.html)
