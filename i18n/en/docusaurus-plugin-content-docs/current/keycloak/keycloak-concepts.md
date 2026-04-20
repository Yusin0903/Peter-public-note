---
sidebar_position: 1
---

# Keycloak Core Concepts

## HttpOnly Cookie

HttpOnly Cookie prevents JavaScript from directly reading cookies, protecting against XSS attacks.

```
Browser receives Set-Cookie: token=xxx; HttpOnly
  ↓
document.cookie cannot read this cookie
  ↓
Even if malicious JS is injected via XSS, it cannot steal the token
```

## Refresh Token Strategy

Before calling an API, check the token's `exp` (expiration). If expired, refresh first then proceed:

```python
def get_valid_token():
    if time.time() >= token_expiration:
        refresh_token()
    return access_token
```

## SSO Session Parameters

| Parameter | Description | Effect |
|-----------|-------------|--------|
| SSO Session Idle | If the user has no activity beyond this time, the session expires | Controls auto-logout after inactivity |
| SSO Session Max | Regardless of activity, the session expires after this duration from login | Controls maximum single-session duration |

## Permission Propagation Delay

After changing user permissions, they don't always take effect immediately:

| System | Delay |
|--------|-------|
| Google Cloud IAM | Usually 2–7 min, group changes may take hours |
| Azure AD / Office 365 | Minutes to 1 hour, up to 24 hours |
| SAP | Requires re-login |
| Keycloak (custom) | Controlled by access token expiry, usually within 2 minutes |

## RBAC Design Pattern

Design roles at the page/feature level:

```
home_read   → can view the Home page
home_write  → can perform actions on the Home page

admin_read  → can view the Admin page
admin_write → can perform actions on the Admin page
```

Use a decorator for API permission checking:

```python
@require_roles(["home_read", "admin_read"])
async def get_dashboard():
    ...
```

Validates that the JWT in the request contains the required role.

**Two ways to handle permission changes:**
1. Wait for the access token to expire and refresh automatically (set 2-minute expiry — wait at most 2 minutes)
2. Ask the user to log out and log back in

## Singleton Pattern for Token Management

Share one token across the whole app, using Singleton to manage auto-refresh:

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
        self.token_expiration = time.time() + expires_in - 60  # refresh 60 seconds early


# Whole app shares one instance
oauth_client = OAuthClient(
    host=settings.OAUTH_HOST,
    realm=settings.OAUTH_REALM,
    client_id=settings.CLIENT_ID,
    client_secret=settings.CLIENT_SECRET,
)
```
