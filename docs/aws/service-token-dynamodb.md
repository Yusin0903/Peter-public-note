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
> token = await token_provider.get_service_token()
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
serviceTokenProvider.get_service_token()
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

## Python 實作模式

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


# 使用方式
import os

env = os.environ.get("ENV", "dev")
provider = ServiceTokenProvider(
    table_name=f"my-service-{env}-config"
    #                  ↑
    #    env="prod" → "my-service-prod-config"
)

# inference worker 呼叫外部 API 時
token = provider.get_service_token()
headers = {"Authorization": f"Bearer {token}"}
response = httpx.post("https://external-api.com/infer", headers=headers, json=payload)
```

---

## Token Rotation 流程

```
1. 外部 API 發新 token
        ↓
2. 直接更新 DynamoDB：
   table.update_item(Key={"id": "service_token"}, ...)
        ↓
3. 下一次 worker 呼叫 get_service_token() 就拿到新 token
        ↓
4. 不需要重新部署、不需要重啟 Pod ✓
```

```python
# 對比：如果用環境變數
# 換 token 的流程會是：
# 1. 更新 K8s Secret
# 2. kubectl rollout restart deployment/my-worker  ← 要重啟！
# 3. Pod 重新啟動，讀取新的環境變數
# → 有 downtime 風險，而且要走一遍部署流程
```
