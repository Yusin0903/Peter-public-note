---
sidebar_position: 2
---

# Singleton vs 多實例 設計模式

## Singleton（單例）

整個 app 只有一個 instance，適合共享資源。

---

## 實作方式一：`__new__` 覆寫（基本版）

```python
class AppConfig:
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance.load_config()
        return cls._instance

    def load_config(self):
        self.debug = True
        self.model_path = "/models/llm"

config = AppConfig()  # 整個 app 共用這一個
assert AppConfig() is config  # True
```

**缺點**：多執行緒下有 race condition，兩個執行緒可能同時通過 `if _instance is None` 的判斷，建立兩個 instance。

---

## 實作方式二：Thread-Safe Singleton（生產環境推薦）

使用 `threading.Lock` 搭配 **Double-Checked Locking** 模式：

```python
import threading

class ModelRegistry:
    _instance = None
    _lock: threading.Lock = threading.Lock()

    def __new__(cls):
        # 第一次檢查（無鎖，效能優先）
        if cls._instance is None:
            with cls._lock:
                # 第二次檢查（有鎖，正確性保證）
                # 防止兩個執行緒同時通過第一次檢查後重複建立
                if cls._instance is None:
                    instance = super().__new__(cls)
                    instance._initialized = False
                    cls._instance = instance
        return cls._instance

    def __init__(self):
        # 防止 __init__ 被多次呼叫重複初始化
        if self._initialized:
            return
        self._initialized = True
        self._models: dict = {}
        self._model_lock = threading.Lock()

    def load_model(self, name: str, path: str):
        with self._model_lock:
            if name not in self._models:
                print(f"載入模型: {name}")
                self._models[name] = load_from_disk(path)  # 只載入一次
        return self._models[name]

    def get_model(self, name: str):
        return self._models.get(name)

# 多執行緒安全：不論哪個 thread 先呼叫，都只會建立一個 instance
registry = ModelRegistry()
```

**Double-Checked Locking 為何需要兩次判斷：**

```
Thread A                    Thread B
----                        ----
if _instance is None        if _instance is None
  → True，準備進入鎖             → True，等待鎖
acquire lock
  if _instance is None      （等待中）
    → True，建立 instance
release lock                acquire lock
                              if _instance is None
                                → False，不重複建立
                            release lock
```

---

## 實作方式三：Module-Level Singleton（最 Pythonic）

Python 模組本身就是 singleton：同一個模組在整個 process 生命週期只被 import 一次，`sys.modules` 會快取它。

```python
# config.py — 這個檔案本身就是 singleton
import os
from dataclasses import dataclass

@dataclass
class _Config:
    model_path: str = os.getenv("MODEL_PATH", "/models/default")
    device: str = os.getenv("DEVICE", "cuda")
    max_batch_size: int = int(os.getenv("MAX_BATCH_SIZE", "32"))
    debug: bool = os.getenv("DEBUG", "false").lower() == "true"

# 模組層級變數 — import 時自動建立，整個 app 共用
config = _Config()
```

```python
# 在其他任何地方使用
from config import config  # 永遠是同一個 instance

print(config.model_path)   # "/models/default"
print(config.device)       # "cuda"
```

**為什麼這是最 Pythonic 的做法：**
- 不需要任何鎖（Python import 機制本身是 thread-safe 的）
- 不需要特殊的 `__new__` 邏輯
- 可以直接被 `unittest.mock.patch` 替換，測試友善

---

## 實作方式四：Metaclass 方式（進階）

```python
class SingletonMeta(type):
    """可重複用於任何 class 的 singleton metaclass"""
    _instances: dict = {}
    _lock: threading.Lock = threading.Lock()

    def __call__(cls, *args, **kwargs):
        if cls not in cls._instances:
            with cls._lock:
                if cls not in cls._instances:
                    instance = super().__call__(*args, **kwargs)
                    cls._instances[cls] = instance
        return cls._instances[cls]

class DatabasePool(metaclass=SingletonMeta):
    def __init__(self, dsn: str):
        self.pool = create_pool(dsn)

class CacheClient(metaclass=SingletonMeta):
    def __init__(self, url: str):
        self.client = Redis(url)

# 兩個不同的 class，各自只有一個 instance
db = DatabasePool("postgresql://...")
cache = CacheClient("redis://...")
```

---

## 推論服務實戰場景

### ModelRegistry：每個模型只載入一次

```python
import threading
from pathlib import Path
import torch

class ModelRegistry:
    """
    推論服務的核心 singleton：
    - 避免相同模型被重複載入到 GPU（浪費記憶體）
    - 多個 request worker 共用同一份模型權重
    """
    _instance = None
    _lock = threading.Lock()

    def __new__(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    inst = super().__new__(cls)
                    inst._models: dict[str, torch.nn.Module] = {}
                    inst._model_lock = threading.Lock()
                    cls._instance = inst
        return cls._instance

    def get_or_load(self, model_name: str, model_path: str, device: str = "cuda") -> torch.nn.Module:
        if model_name not in self._models:
            with self._model_lock:
                if model_name not in self._models:  # double-check
                    print(f"[ModelRegistry] 載入 {model_name} 到 {device}...")
                    model = torch.load(model_path, map_location=device)
                    model.eval()
                    self._models[model_name] = model
        return self._models[model_name]

    def unload(self, model_name: str) -> None:
        with self._model_lock:
            if model_name in self._models:
                del self._models[model_name]
                torch.cuda.empty_cache()
                print(f"[ModelRegistry] 已卸載 {model_name}")

    @property
    def loaded_models(self) -> list[str]:
        return list(self._models.keys())


# 全域共用
registry = ModelRegistry()

# 在 FastAPI route handler 中使用
# 即使有 100 個 concurrent request，模型也只被載入一次
@app.post("/infer")
async def infer(request: InferRequest):
    model = registry.get_or_load("llm-7b", "/models/llm-7b.pt")
    with torch.no_grad():
        output = model(request.input_ids)
    return {"output": output.tolist()}
```

### 資料庫連線池 Singleton

```python
import threading
from contextlib import contextmanager
import psycopg2.pool

class DatabasePool:
    _instance = None
    _lock = threading.Lock()

    def __new__(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    inst = super().__new__(cls)
                    inst._pool = None
                    cls._instance = inst
        return cls._instance

    def initialize(self, dsn: str, minconn: int = 2, maxconn: int = 20):
        if self._pool is None:
            self._pool = psycopg2.pool.ThreadedConnectionPool(
                minconn=minconn,
                maxconn=maxconn,
                dsn=dsn,
            )
            print(f"連線池已建立（{minconn}~{maxconn} 個連線）")

    @contextmanager
    def connection(self):
        conn = self._pool.getconn()
        try:
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            self._pool.putconn(conn)

# 啟動時初始化一次
db_pool = DatabasePool()
db_pool.initialize("postgresql://user:pass@localhost/inference_db")

# 任何地方使用，都是同一個連線池
with db_pool.connection() as conn:
    cur = conn.cursor()
    cur.execute("SELECT * FROM jobs WHERE status='pending'")
```

### Config Singleton（最簡潔做法）

```python
# settings.py
import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    model_path: str = "/models/llm"
    device: str = "cuda"
    max_batch_size: int = 32
    db_dsn: str = "postgresql://localhost/inference"
    redis_url: str = "redis://localhost:6379"
    keycloak_url: str = "http://keycloak:8080"

    class Config:
        env_file = ".env"

# 模組層級 singleton — Python import 機制保證唯一性
settings = Settings()
```

```python
# 在任何模組中使用
from settings import settings

print(settings.model_path)
print(settings.device)
```

---

## 何時用 Singleton

| 場景 | 原因 |
|------|------|
| ModelRegistry | 避免相同模型佔用多份 GPU 記憶體 |
| DB Connection Pool | 連線數有上限，必須集中管理 |
| Config / Settings | 設定只需從環境變數讀取一次 |
| 認證 Token 管理 | 所有請求共用同一個 token，集中管理刷新 |
| Logger | 集中管理 log 輸出，避免多個 handler |

## 何時用多實例

| 場景 | 原因 |
|------|------|
| 並行資料處理器 | 每個處理器處理自己的資料，不共用狀態 |
| 多個不同 DB 連線 | 連接不同資料庫（主從、不同服務） |
| 多個 API Client | 連接不同服務或不同帳號 |
| Request-scoped 物件 | 每個 HTTP request 有自己的 context |

```python
# 多實例 — 每個處理器獨立
class DataProcessor:
    def __init__(self, data):
        self.data = data

    def process(self):
        return f"Processing {self.data}"

processor1 = DataProcessor("dataset_A")
processor2 = DataProcessor("dataset_B")
```

---

## 何時不該用 Singleton

**測試困難**：

```python
# ❌ Singleton 讓測試變得很難
def test_inference():
    registry = ModelRegistry()  # 拿到全域 instance
    # 如何 mock 掉 registry 內的模型？很麻煩

# ✅ 依賴注入讓測試容易
def test_inference():
    mock_registry = MockModelRegistry()
    mock_registry.get_or_load.return_value = DummyModel()
    result = infer(request, registry=mock_registry)  # 注入 mock
```

**全域狀態是危險的**：

```python
# ❌ Singleton 持有可變狀態，多個地方修改很難追蹤
registry = ModelRegistry()
registry._models["llm"] = broken_model  # 哪裡改的？難以追蹤

# ❌ 測試之間互相污染
def test_a():
    registry.load_model("test_model", ...)  # 影響其他測試！

def test_b():
    # registry 還有 test_a 留下的 test_model
```

**進程隔離問題**：

```python
# ❌ 多進程環境中，每個 worker process 有自己的記憶體空間
# Singleton 在 process 1 和 process 2 是不同 instance！
# 在 gunicorn multi-worker 或 multiprocessing 中要特別注意

# ✅ 跨進程的「singleton」應該用外部儲存
# Redis、資料庫、共享記憶體 → 才能真正跨進程共用
```

---

## 現代替代方案：依賴注入（Dependency Injection）

Singleton 的核心問題是「隱藏依賴」。DI 讓依賴變得顯式：

```python
# ❌ 隱藏依賴：函式內部悄悄使用全域 singleton
def process_request(input_data: str) -> str:
    model = ModelRegistry().get_or_load("llm", "/models/llm.pt")  # 隱藏依賴
    return model.generate(input_data)

# ✅ 顯式依賴注入：依賴從外部傳入
def process_request(input_data: str, model: torch.nn.Module) -> str:
    return model.generate(input_data)

# FastAPI 的依賴注入系統
from fastapi import Depends

def get_model_registry() -> ModelRegistry:
    return ModelRegistry()  # 可以在測試中替換這個 dependency

@app.post("/infer")
async def infer(
    request: InferRequest,
    registry: ModelRegistry = Depends(get_model_registry),
):
    model = registry.get_or_load("llm", settings.model_path)
    return {"output": model.generate(request.text)}
```

```python
# 測試中替換 dependency
from fastapi.testclient import TestClient

def mock_registry():
    registry = MagicMock(spec=ModelRegistry)
    registry.get_or_load.return_value = DummyModel()
    return registry

app.dependency_overrides[get_model_registry] = mock_registry

client = TestClient(app)
response = client.post("/infer", json={"text": "hello"})
# DummyModel 被用來推論，不需要真實的 GPU 或模型檔案
```

---

## 總結

| 做法 | 適用場景 | 執行緒安全 | 測試友善 |
|------|----------|-----------|---------|
| Module-level 變數 | Config、簡單共用物件 | 是 | 是（可 mock） |
| `__new__` + Lock | 需要 lazy init 的重資源 | 是 | 普通 |
| Metaclass | 需要套用多個 class | 是 | 普通 |
| 依賴注入 | 生產推論服務、需要測試 | 是 | 最佳 |

- **Singleton**：共享資源、全局狀態、配置管理
- **多實例**：並行處理、資源隔離、不同配置
- **依賴注入**：需要可測試性和可替換性的場景
