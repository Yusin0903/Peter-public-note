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

## Refresh Token 策略

呼叫 API 前先檢查 token 的 `exp`（expiration），如果過期就先重新取得再呼叫：

```python
def get_valid_token():
    if time.time() >= token_expiration:
        refresh_token()
    return access_token
```

## SSO Session 參數

| 參數 | 說明 | 效果 |
|------|------|------|
| SSO Session Idle | 使用者「沒有任何操作」超過這個時間，會話失效 | 控制長時間未操作自動登出 |
| SSO Session Max | 不論有沒有操作，從登入起超過這個時長強制失效 | 控制單次登入最長可用多久 |

## 權限生效延遲

更改使用者權限後不一定立即生效，各系統的延遲：

| 系統 | 延遲時間 |
|------|----------|
| Google Cloud IAM | 通常 2~7 分鐘，群組異動可能數小時 |
| Azure AD / Office 365 | 幾分鐘~1 小時，最長 24 小時 |
| SAP | 需重新登入才生效 |
| Keycloak（自訂） | 可設定 access token 過期時間控制，通常 2 分鐘內生效 |

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
@require_roles(["home_read", "admin_read"])
async def get_dashboard():
    ...
```

呼叫 API 時驗證 JWT 內是否包含所需 role。

**權限更新後的兩種方式：**
1. 等待 access token 過期自動刷新（設 2 分鐘過期，最長等 2 分鐘）
2. 請使用者登出再登入

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
