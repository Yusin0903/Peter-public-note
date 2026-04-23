---
sidebar_position: 3
---

# 從 DynamoDB 動態取得 Service Token

## 概念

把 token 存在 DynamoDB，讓服務在 runtime 動態讀取，而不是寫死在環境變數裡。

> **Python 類比**：就像把敏感設定放進資料庫而不是 `.env`，每次需要時動態查詢，不用重啟服務就能換掉。
>
> ```python
> # ❌ 寫死在環境變數（換 token 要重新部署）
> import os
> token = os.environ["SERVICE_TOKEN"]
>
> # ✅ 從 DynamoDB 動態讀取（換 token 只要改 DB）
> token = provider.get_service_token()
> ```

---

## 為什麼需要 Service Token

Worker 送資料到外部 API 時，需要一個 token 證明身份：

```
Worker 要呼叫外部 API
  │
  │ 「你是誰？給我看 token」
  │
  ▼
ServiceTokenProvider.get_service_token()
  │
  │ 去 DynamoDB 查 config 設定
  │
  ▼
拿到 token → 帶著 token 呼叫 API → 送出請求
```

---

## 為什麼不直接把 token 放環境變數？

| 方式 | 優點 | 缺點 |
|---|---|---|
| 環境變數 | 簡單 | 換 token 要重新部署 Pod |
| DynamoDB | 動態讀取 | 換 token 只要改 DB，不用重新部署 |

Token 可能會定期輪換（rotate），放 DynamoDB 就能不重啟服務的情況下換掉 token。

---

## 基礎實作

```python
import boto3
from dataclasses import dataclass

@dataclass
class ServiceTokenProvider:
    table_name: str
    region: str = "us-east-1"

    def __post_init__(self):
        dynamodb = boto3.resource("dynamodb", region_name=self.region)
        self._table = dynamodb.Table(self.table_name)

    def get_service_token(self) -> str:
        """每次呼叫都從 DynamoDB 讀最新值，token rotate 後自動生效"""
        response = self._table.get_item(Key={"id": "service_token"})
        item = response.get("Item")
        if not item:
            raise ValueError("service_token not found in DynamoDB")
        return item["token"]
```

**問題：每次請求都打一次 DynamoDB**

如果你的 inference worker 每秒處理 100 個請求，每個請求都呼叫 `get_service_token()`，就是每秒 100 次 DynamoDB read。Token 通常幾小時甚至幾天才換一次，這些讀取大部分都是浪費的。

---

## 加入 TTL 快取（正確做法）

> **Python 類比**：就像用 `functools.lru_cache` 快取昂貴的函式呼叫，但 lru_cache 沒有時間過期，需要自己實作 TTL。
>
> ```python
> import functools
> import time
>
> # lru_cache 沒有 TTL，這樣不行：
> @functools.lru_cache(maxsize=1)
> def get_token():
>     return fetch_from_dynamodb()  # 永遠不會重新讀取
>
> # 需要帶時間的快取
> ```

```python
import boto3
import threading
import time
from dataclasses import dataclass, field

@dataclass
class ServiceTokenProvider:
    table_name: str
    region: str = "us-east-1"
    cache_ttl_seconds: int = 300  # 5 分鐘 TTL

    def __post_init__(self):
        dynamodb = boto3.resource("dynamodb", region_name=self.region)
        self._table = dynamodb.Table(self.table_name)
        self._cached_token: str | None = None
        self._cache_expires_at: float = 0.0
        self._lock = threading.Lock()  # 執行緒安全

    def get_service_token(self) -> str:
        """
        從快取讀取 token，過期才重新查 DynamoDB。
        快取 TTL = 5 分鐘，token rotate 後最多 5 分鐘生效。
        """
        # 先不加鎖快速檢查（大多數情況快取是有效的）
        if self._cached_token and time.monotonic() < self._cache_expires_at:
            return self._cached_token

        # 快取失效，加鎖重新讀取
        with self._lock:
            # double-checked locking：拿到鎖後再確認一次，避免重複打 DynamoDB
            if self._cached_token and time.monotonic() < self._cache_expires_at:
                return self._cached_token

            token = self._fetch_from_dynamodb()
            self._cached_token = token
            self._cache_expires_at = time.monotonic() + self.cache_ttl_seconds
            return token

    def _fetch_from_dynamodb(self) -> str:
        """直接從 DynamoDB 讀取最新 token"""
        response = self._table.get_item(Key={"id": "service_token"})
        item = response.get("Item")
        if not item:
            raise ValueError("service_token not found in DynamoDB")
        return item["token"]

    def invalidate_cache(self) -> None:
        """強制清除快取，下次呼叫會重新讀 DynamoDB"""
        with self._lock:
            self._cached_token = None
            self._cache_expires_at = 0.0
```

### 執行緒安全說明

```python
# 為什麼需要 threading.Lock()？
# 假設 10 個 inference worker thread 同時發現快取過期：
# 沒有 lock → 10 個 thread 同時打 DynamoDB → "thundering herd"
# 有 lock  → 第一個 thread 拿鎖、讀 DynamoDB、更新快取
#            其他 9 個 thread 排隊等鎖
#            拿到鎖後發現快取已更新（double-check）→ 直接回傳快取

# 使用 threading.Lock 的代價極小（nanoseconds），
# 但避免了在快取過期瞬間的 N 倍 DynamoDB 請求
```

---

## Token 過期中途處理（請求途中 Token 失效）

Token rotation 有時是強制性的（立即失效），而不是等 TTL 到期。如果 token 在 inference 請求途中被換掉，外部 API 會回傳 401。

> **Python 類比**：就像 `requests` 的 retry 邏輯，遇到 401 就重新取得 token 再試一次。
>
> ```python
> import requests
> from requests.auth import AuthBase
>
> class DynamicTokenAuth(AuthBase):
>     def __call__(self, r):
>         r.headers["Authorization"] = f"Bearer {get_fresh_token()}"
>         return r
> ```

```python
import httpx
from botocore.exceptions import ClientError

class InferenceAPIClient:
    def __init__(self, base_url: str, token_provider: ServiceTokenProvider):
        self._base_url = base_url
        self._token_provider = token_provider

    def call_with_token_retry(self, endpoint: str, payload: dict) -> dict:
        """
        呼叫外部 API，遇到 401（token 過期）時自動重試一次。
        只重試一次：避免 token 本身有問題導致無限循環。
        """
        for attempt in range(2):  # 最多嘗試 2 次
            token = self._token_provider.get_service_token()
            try:
                response = httpx.post(
                    f"{self._base_url}/{endpoint}",
                    headers={"Authorization": f"Bearer {token}"},
                    json=payload,
                    timeout=30.0,
                )

                if response.status_code == 401 and attempt == 0:
                    # Token 可能已被 rotate，清快取後重試
                    print(f"[WARNING] 401 Unauthorized，清除 token 快取後重試")
                    self._token_provider.invalidate_cache()
                    continue  # 重試

                response.raise_for_status()
                return response.json()

            except httpx.HTTPStatusError as e:
                if e.response.status_code == 401 and attempt == 0:
                    self._token_provider.invalidate_cache()
                    continue
                raise

        raise RuntimeError("Token 重試後仍然 401，請確認 DynamoDB 中的 token 是否有效")
```

---

## Token Rotation 流程

```
1. 外部 API 發新 token
        ↓
2. 直接更新 DynamoDB：
   table.update_item(Key={"id": "service_token"}, ...)
        ↓
3. 各 worker 的快取還是舊 token（最多 5 分鐘）
        ↓
4a. 快取 TTL 到期後，下一次呼叫自動拿新 token
4b. 或外部 API 回 401 → 立即清快取 → 下一次拿新 token
        ↓
5. 不需要重新部署、不需要重啟 Pod ✓
```

```python
# 對比：如果用環境變數
# 換 token 的流程會是：
# 1. 更新 K8s Secret
# 2. kubectl rollout restart deployment/my-worker  ← 要重啟！
# 3. Pod 重新啟動，讀取新的環境變數
# → 有 downtime 風險，而且要走一遍部署流程
```

---

## 完整使用範例

```python
import os
import httpx

env = os.environ.get("ENV", "dev")

# 全局 singleton，整個程序共用一個快取
_token_provider = ServiceTokenProvider(
    table_name=f"my-service-{env}-config",
    cache_ttl_seconds=300,  # 5 分鐘快取
)

_api_client = InferenceAPIClient(
    base_url="https://external-api.com",
    token_provider=_token_provider,
)

def run_inference(payload: dict) -> dict:
    """Inference worker 的主要入口"""
    return _api_client.call_with_token_retry("infer", payload)

# 預期行為：
# - 每 5 分鐘才打一次 DynamoDB，其餘 9999 次用快取
# - token 被強制輪換時，最多多一次 401 後自動恢復
# - 多執行緒安全，100 個 worker thread 共用同一個快取
```
