---
sidebar_position: 3
---

# Dynamically Fetching Service Tokens from DynamoDB

## Concept

Store the token in DynamoDB so services read it dynamically at runtime, rather than hardcoding it in environment variables.

> **Python analogy**: Like storing sensitive config in a database instead of `.env` — query it dynamically each time, no service restart needed to rotate.
>
> ```python
> # ❌ Hardcoded in env var (rotating token requires redeploy)
> import os
> token = os.environ["SERVICE_TOKEN"]
>
> # ✅ Dynamically read from DynamoDB (rotating token only requires updating DB)
> token = token_provider.get_service_token()
> ```

---

## Why a Service Token Is Needed

When a worker sends data to an external API, it needs a token to prove its identity:

```
Worker wants to call external API
  │
  │ "Who are you? Show me a token"
  │
  ▼
token_provider.get_service_token()
  │
  │ Query DynamoDB for config
  │
  ▼
Get token → attach token to API call → send request
```

---

## Why Not Just Put the Token in an Environment Variable?

| Approach | Pros | Cons |
|----------|------|------|
| Environment variable | Simple | Rotating requires redeploying the Pod |
| DynamoDB | Dynamic reads | Rotating only requires updating the DB, no redeploy |

Tokens may be rotated periodically. Storing in DynamoDB means the token can be swapped without restarting the service.

---

## Python Implementation

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
        """Reads the latest value from DynamoDB each call — token rotation takes effect immediately"""
        response = self._table.get_item(Key={"id": "service_token"})
        item = response.get("Item")
        if not item:
            raise ValueError("service_token not found in DynamoDB")
        return item["token"]


# Usage
import os

env = os.environ.get("ENV", "dev")
provider = ServiceTokenProvider(
    table_name=f"my-service-{env}-config"
    #                  ↑
    #    env="prod" → "my-service-prod-config"
)

# When inference worker calls external API
token = provider.get_service_token()
headers = {"Authorization": f"Bearer {token}"}
response = httpx.post("https://external-api.com/infer", headers=headers, json=payload)
```

---

## Token Rotation Flow

```
1. External API issues new token
        ↓
2. Update DynamoDB directly:
   table.update_item(Key={"id": "service_token"}, ...)
        ↓
3. Next call to get_service_token() picks up the new token
        ↓
4. No redeploy needed, no Pod restart required ✓
```

```python
# Contrast: with environment variables, rotation looks like:
# 1. Update the K8s Secret
# 2. kubectl rollout restart deployment/my-worker  ← restart required!
# 3. Pod restarts and reads the new env var
# → Downtime risk + full deployment cycle
```
