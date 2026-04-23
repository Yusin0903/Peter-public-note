---
sidebar_position: 1
---

# Keycloak 核心概念

## HttpOnly Cookie

HttpOnly Cookie 主要防止 JS 直接讀取 cookie，保護免於 XSS 攻擊。

```
瀏覽器收到 Set-Cookie: token=xxx; HttpOnly
  ↓
document.cookie 讀不到這個 cookie
  ↓
就算網頁被 XSS 注入惡意 JS，也無法竊取 token
```

---

## OAuth2 / OIDC 完整流程

### 三種 Token 的差異

| Token | 用途 | 存放位置 | 有效期 |
|-------|------|----------|--------|
| **Access Token** | 呼叫 API 時放在 `Authorization: Bearer` header | 記憶體（不存 localStorage） | 短（1~5 分鐘） |
| **Refresh Token** | 用來取得新的 Access Token，不直接呼叫 API | HttpOnly Cookie 或安全儲存 | 長（數小時~數天） |
| **ID Token** | 代表使用者身份（名字、email、roles），給前端顯示用 | 記憶體 | 短（同 Access Token） |

**何時用哪個：**
- 呼叫推論 API → 用 **Access Token**
- Access Token 過期 → 用 **Refresh Token** 換新的 Access Token
- 顯示使用者姓名/頭像 → 解析 **ID Token** 的 payload
- 永遠不要把 Refresh Token 放在 JS 可讀的地方

### Authorization Code Flow（使用者登入）

```
使用者                   前端                    Keycloak                 推論 API
  |                       |                         |                         |
  |-- 點擊登入 ---------->|                         |                         |
  |                       |-- redirect to Keycloak ->|                        |
  |                       |                         |                         |
  |<------------ Keycloak 登入頁面 ----------------|                         |
  |-- 輸入帳號密碼 -------------------------------->|                         |
  |                       |<-- code=xxx ------------|                         |
  |                       |-- POST /token           |                         |
  |                       |   code=xxx, client_id   |                         |
  |                       |<-- access_token         |                         |
  |                       |   refresh_token         |                         |
  |                       |   id_token  ------------|                         |
  |                       |                                                   |
  |                       |-- GET /infer, Authorization: Bearer <token> ----->|
  |                       |                                      驗證 JWT     |
  |                       |<------------------------------------- result ------|
```

### FastAPI 保護推論 API 端點

```python
# requirements: fastapi uvicorn python-jose[cryptography] httpx

from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import jwt, JWTError
import httpx
import os

app = FastAPI()

KEYCLOAK_URL = os.getenv("KEYCLOAK_URL", "http://keycloak:8080")
REALM = os.getenv("KEYCLOAK_REALM", "inference-platform")
CLIENT_ID = os.getenv("KEYCLOAK_CLIENT_ID", "inference-api")

# Keycloak 的 OIDC 設定端點（包含公鑰等資訊）
OIDC_CONFIG_URL = f"{KEYCLOAK_URL}/realms/{REALM}/.well-known/openid-configuration"

oauth2_scheme = OAuth2PasswordBearer(
    tokenUrl=f"{KEYCLOAK_URL}/realms/{REALM}/protocol/openid-connect/token"
)

# 啟動時取得 Keycloak 的公鑰（用來驗證 JWT 簽章）
_jwks_cache: dict = {}

async def get_jwks() -> dict:
    if not _jwks_cache:
        async with httpx.AsyncClient() as client:
            oidc_config = (await client.get(OIDC_CONFIG_URL)).json()
            jwks = (await client.get(oidc_config["jwks_uri"])).json()
            _jwks_cache.update(jwks)
    return _jwks_cache


async def get_current_user(token: str = Depends(oauth2_scheme)) -> dict:
    """FastAPI dependency：驗證 JWT 並回傳 payload"""
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="無效的 token",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        jwks = await get_jwks()
        # python-jose 會自動從 JWKS 找對應的公鑰驗簽
        payload = jwt.decode(
            token,
            jwks,
            algorithms=["RS256"],
            audience=CLIENT_ID,
        )
        return payload
    except JWTError as e:
        raise credentials_exception from e


@app.post("/infer")
async def infer(
    request: dict,
    current_user: dict = Depends(get_current_user),
):
    """受保護的推論端點：沒有有效 JWT 就回傳 401"""
    user_id = current_user.get("sub")
    print(f"使用者 {user_id} 呼叫推論")
    return {"result": "...", "user": user_id}
```

---

## JWT 驗證（python-jose vs PyJWT）

### python-jose（支援 JWKS，推薦用於 Keycloak）

```python
from jose import jwt, JWTError
from jose.exceptions import ExpiredSignatureError

def validate_token(token: str, jwks: dict, audience: str) -> dict:
    """
    驗證 Keycloak 簽發的 JWT。
    jwks：從 Keycloak 的 /protocol/openid-connect/certs 取得的公鑰集合。
    """
    try:
        payload = jwt.decode(
            token,
            jwks,
            algorithms=["RS256"],   # Keycloak 預設用 RS256
            audience=audience,       # 必須符合 token 的 aud claim
        )
        return payload
    except ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token 已過期")
    except JWTError as e:
        raise HTTPException(status_code=401, detail=f"Token 無效: {e}")
```

### PyJWT（輕量，需自行取得公鑰）

```python
import jwt as pyjwt
import httpx

async def get_public_key(token: str) -> str:
    """從 JWT header 的 kid 找到對應的公鑰"""
    header = pyjwt.get_unverified_header(token)
    kid = header["kid"]

    async with httpx.AsyncClient() as client:
        jwks = (await client.get(
            f"{KEYCLOAK_URL}/realms/{REALM}/protocol/openid-connect/certs"
        )).json()

    for key in jwks["keys"]:
        if key["kid"] == kid:
            return pyjwt.algorithms.RSAAlgorithm.from_jwk(key)

    raise ValueError(f"找不到 kid={kid} 的公鑰")


async def validate_with_pyjwt(token: str) -> dict:
    public_key = await get_public_key(token)
    payload = pyjwt.decode(
        token,
        public_key,
        algorithms=["RS256"],
        audience=CLIENT_ID,
    )
    return payload
```

### JWT Payload 的重要欄位

```python
# decode 後的 payload 範例
{
    "sub": "a1b2c3d4-...",          # 使用者唯一 ID
    "preferred_username": "alice",  # 使用者名稱
    "email": "alice@example.com",
    "realm_access": {
        "roles": ["inference_user", "admin"]  # Realm 層級的 roles
    },
    "resource_access": {
        "inference-api": {
            "roles": ["model_llm_access"]     # 特定 client 的 roles
        }
    },
    "exp": 1700000000,              # 過期時間（Unix timestamp）
    "iat": 1699999700,              # 簽發時間
    "iss": "http://keycloak:8080/realms/inference-platform",
    "aud": "inference-api",
}
```

---

## RBAC：從 JWT 檢查 Roles

### FastAPI Dependency 實作

```python
from fastapi import Depends, HTTPException, status
from functools import wraps

def require_roles(*required_roles: str):
    """
    FastAPI dependency factory：檢查 JWT 內是否包含所需 roles。

    用法：
        @app.post("/admin")
        async def admin_only(user=Depends(require_roles("admin"))):
            ...
    """
    async def dependency(current_user: dict = Depends(get_current_user)) -> dict:
        # Keycloak 的 roles 有兩個層級：
        # 1. realm_access.roles  → 整個 realm 的 roles
        # 2. resource_access.<client_id>.roles → 特定 client 的 roles
        realm_roles: list[str] = (
            current_user.get("realm_access", {}).get("roles", [])
        )
        client_roles: list[str] = (
            current_user
            .get("resource_access", {})
            .get(CLIENT_ID, {})
            .get("roles", [])
        )
        user_roles = set(realm_roles + client_roles)

        missing = set(required_roles) - user_roles
        if missing:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"權限不足，缺少 roles: {missing}",
            )
        return current_user

    return dependency


# 使用範例
@app.post("/infer/llm")
async def infer_llm(
    request: dict,
    user: dict = Depends(require_roles("inference_user", "model_llm_access")),
):
    """只有同時擁有 inference_user 和 model_llm_access roles 才能呼叫"""
    return {"result": "..."}


@app.delete("/models/{model_name}")
async def unload_model(
    model_name: str,
    user: dict = Depends(require_roles("admin")),
):
    """只有 admin 才能卸載模型"""
    registry.unload(model_name)
    return {"message": f"模型 {model_name} 已卸載"}
```

### 以頁面/功能為粒度設計 Role

```
Realm Roles（整個平台）：
  inference_user  → 可以呼叫推論 API
  model_manager   → 可以管理模型載入/卸載
  admin           → 完整管理權限

Client Roles（針對 inference-api 這個 client）：
  model_llm_access      → 可以使用 LLM 模型
  model_vision_access   → 可以使用視覺模型
  priority_queue        → 使用優先佇列
```

---

## Service-to-Service Auth：Client Credentials Flow

推論服務之間互相呼叫時，不會有使用者，改用 **機器帳號** 取得 token：

```
Service A                         Keycloak                    Service B
   |                                  |                            |
   |-- POST /token                    |                            |
   |   grant_type=client_credentials  |                            |
   |   client_id=service-a            |                            |
   |   client_secret=xxx  ----------->|                            |
   |<-- access_token ------------------|                            |
   |                                                               |
   |-- POST /embed                                                 |
   |   Authorization: Bearer <token> ----------------------------->|
   |                                              驗證 JWT，       |
   |                                              確認是 service-a |
   |<--------------------------------------------- embeddings -----|
```

### Python 實作（OAuthClient）

```python
import threading
import time
import httpx

class OAuthClient:
    """
    Machine-to-machine token 管理器。
    使用 client_credentials flow，自動在 token 過期前刷新。
    """

    def __init__(self, host: str, realm: str, client_id: str, client_secret: str):
        self.token_url = f"{host}/realms/{realm}/protocol/openid-connect/token"
        self.client_id = client_id
        self.client_secret = client_secret
        self._access_token: str | None = None
        self._token_expiration: float = 0
        self._lock = threading.Lock()  # thread-safe token refresh

    def get_token(self) -> str:
        with self._lock:
            if self._access_token is None or time.time() >= self._token_expiration:
                self._refresh_token()
            return self._access_token

    def _refresh_token(self) -> None:
        response = httpx.post(
            self.token_url,
            data={
                "grant_type": "client_credentials",
                "client_id": self.client_id,
                "client_secret": self.client_secret,
            },
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            timeout=10,
        )
        response.raise_for_status()
        token_data = response.json()
        self._access_token = token_data["access_token"]
        expires_in = token_data.get("expires_in", 60)
        # 提前 30 秒刷新，避免 token 在傳輸途中過期
        self._token_expiration = time.time() + expires_in - 30

    def get_auth_header(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.get_token()}"}


# settings.py 中建立 singleton
from settings import settings

oauth_client = OAuthClient(
    host=settings.KEYCLOAK_URL,
    realm=settings.KEYCLOAK_REALM,
    client_id=settings.CLIENT_ID,
    client_secret=settings.CLIENT_SECRET,
)
```

### 呼叫其他推論服務

```python
import httpx
from oauth_client import oauth_client  # 上面建立的 singleton

async def call_embedding_service(texts: list[str]) -> list[list[float]]:
    """呼叫 embedding 服務，自動帶入 machine token"""
    async with httpx.AsyncClient() as client:
        response = await client.post(
            "http://embedding-service:8080/embed",
            json={"texts": texts},
            headers=oauth_client.get_auth_header(),  # 自動刷新 token
            timeout=30.0,
        )
        response.raise_for_status()
        return response.json()["embeddings"]
```

---

## 常見陷阱：長時間推論任務的 Token 過期

**問題情境**：

```
使用者發送推論請求（token 有效期 5 分鐘）
  ↓
推論任務開始（LLM 生成需要 10 分鐘）
  ↓
任務執行到第 5 分鐘 → token 過期
  ↓
任務結束後想記錄結果到 DB / 呼叫 callback API
  ↓
所有後續 API 呼叫都回傳 401！
```

### 解決方案一：任務開始時就把必要資訊存到 DB

```python
@app.post("/infer/async")
async def start_async_inference(
    request: InferRequest,
    user: dict = Depends(get_current_user),
):
    """
    接受請求後立即把必要資訊存到 DB，
    後續任務執行不依賴原始 token。
    """
    job_id = str(uuid.uuid4())
    user_id = user["sub"]
    callback_url = request.callback_url

    # token 有效時立即把所有需要的資訊存下來
    await db.insert_job({
        "id": job_id,
        "user_id": user_id,
        "input": request.input,
        "callback_url": callback_url,
        "status": "pending",
    })

    # 把 job 丟到 queue，背景執行
    await task_queue.enqueue(job_id)

    return {"job_id": job_id, "status": "pending"}


async def background_inference_worker(job_id: str):
    """
    背景 worker：使用 service 本身的 machine token，
    不依賴使用者的 access token。
    """
    job = await db.get_job(job_id)

    result = await run_inference(job["input"])  # 可能很久

    # 更新 DB 用 service 自己的 DB 連線，不需要使用者 token
    await db.update_job(job_id, {"status": "done", "result": result})

    # 呼叫 callback 用 service 的 machine token
    if job["callback_url"]:
        async with httpx.AsyncClient() as client:
            await client.post(
                job["callback_url"],
                json={"job_id": job_id, "result": result},
                headers=oauth_client.get_auth_header(),  # machine token，不會過期
            )
```

### 解決方案二：使用 Refresh Token 在任務中刷新（適合同步場景）

```python
class TokenManager:
    """
    持有 access token + refresh token，
    在長時間任務中自動刷新。
    """

    def __init__(self, access_token: str, refresh_token: str,
                 expires_in: int, token_url: str, client_id: str):
        self.token_url = token_url
        self.client_id = client_id
        self._access_token = access_token
        self._refresh_token = refresh_token
        self._expiration = time.time() + expires_in - 30

    def get_valid_token(self) -> str:
        if time.time() >= self._expiration:
            self._do_refresh()
        return self._access_token

    def _do_refresh(self) -> None:
        response = httpx.post(
            self.token_url,
            data={
                "grant_type": "refresh_token",
                "refresh_token": self._refresh_token,
                "client_id": self.client_id,
            },
        )
        response.raise_for_status()
        data = response.json()
        self._access_token = data["access_token"]
        self._refresh_token = data.get("refresh_token", self._refresh_token)
        self._expiration = time.time() + data.get("expires_in", 60) - 30
```

---

## Refresh Token 策略

呼叫 API 前先檢查 token 的 `exp`（expiration），如果過期就先重新取得再呼叫：

```python
def get_valid_token():
    if time.time() >= token_expiration:
        refresh_token()
    return access_token
```

---

## SSO Session 參數

| 參數 | 說明 | 效果 |
|------|------|------|
| SSO Session Idle | 使用者「沒有任何操作」超過這個時間，會話失效 | 控制長時間未操作自動登出 |
| SSO Session Max | 不論有沒有操作，從登入起超過這個時長強制失效 | 控制單次登入最長可用多久 |

---

## 權限生效延遲

更改使用者權限後不一定立即生效，各系統的延遲：

| 系統 | 延遲時間 |
|------|----------|
| Google Cloud IAM | 通常 2~7 分鐘，群組異動可能數小時 |
| Azure AD / Office 365 | 幾分鐘~1 小時，最長 24 小時 |
| SAP | 需重新登入才生效 |
| Keycloak（自訂） | 可設定 access token 過期時間控制，通常 2 分鐘內生效 |

---

## RBAC 設計模式

以頁面/功能為粒度設計 Role：

```
home_read   → 可以看 Home 頁面
home_write  → 可以在 Home 頁面操作

admin_read  → 可以看 Admin 頁面
admin_write → 可以在 Admin 頁面操作
```

用 decorator 做 API 權限驗證：

```python
@require_roles("home_read", "admin_read")
async def get_dashboard():
    ...
```

呼叫 API 時驗證 JWT 內是否包含所需 role。

**權限更新後的兩種方式：**
1. 等待 access token 過期自動刷新（設 2 分鐘過期，最長等 2 分鐘）
2. 請使用者登出再登入

---

## Singleton 模式管理 Token

整個 app 共用同一個 token，用 Singleton 管理自動刷新：

```python
class OAuthClient:
    def __init__(self, host: str, realm: str, client_id: str, client_secret: str):
        self.host = host
        self.realm = realm
        self.client_id = client_id
        self.client_secret = client_secret
        self.access_token = None
        self.token_expiration = 0

    def get_header(self):
        return {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {self._get_access_token()}",
        }

    def _get_access_token(self):
        if self.access_token is None or time.time() >= self.token_expiration:
            self._refresh_token()
        return self.access_token

    def _refresh_token(self):
        response = requests.post(
            f"{self.host}/realms/{self.realm}/protocol/openid-connect/token",
            data={
                "grant_type": "client_credentials",
                "client_id": self.client_id,
                "client_secret": self.client_secret,
            },
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            timeout=10,
        )
        response.raise_for_status()
        token_data = response.json()
        self.access_token = token_data.get("access_token")
        expires_in = token_data.get("expires_in", 60)
        self.token_expiration = time.time() + expires_in - 60  # 提前 60 秒刷新


# 整個 app 共用一個 instance
oauth_client = OAuthClient(
    host=settings.OAUTH_HOST,
    realm=settings.OAUTH_REALM,
    client_id=settings.CLIENT_ID,
    client_secret=settings.CLIENT_SECRET,
)
```
