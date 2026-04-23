---
sidebar_position: 2
---

# Ingress & Service

## 請求進入 Pod 的三層架構

```
外部使用者
    │
    ▼
┌──────────┐
│  Ingress │  L7 路由規則（/api/* → Service A, /dashboard/* → Service B）
└──────────┘
    │
    ▼
┌──────────┐
│  Service │  穩定的內部入口，用 label selector 找到 Pod 做 load balancing
└──────────┘
    │
    ▼
┌──────────┐
│   Pod    │  實際跑程式的容器
└──────────┘
```

> **Python 類比**：就像 FastAPI 的 router 架構 — Ingress 是 `app.include_router()` 的路由表，Service 是 `APIRouter`，Pod 是實際的 handler function。

---

## Ingress

- **本質**：L7 路由規則表，定義「什麼 host/path → 哪個 Service」
- **不是 endpoint**，真正開出 endpoint 的是 Ingress Controller
- 需要搭配 Ingress Controller 才能運作（AWS ALB Controller, NGINX 等）

### pathType 三種

| pathType | 說明 |
|----------|------|
| `Exact` | 完全一致（`/foo` 只匹配 `/foo`） |
| `Prefix` | 前綴匹配，以 `/` 為邊界 |
| `ImplementationSpecific` | 交給 Ingress Controller 決定（可支援 wildcard `*`） |

### Ingress NGINX 退役（2026/03）

- 退役的是 **Ingress NGINX Controller**，不是 Ingress API 本身
- Ingress API 是 GA，frozen 但不會 deprecate
- 官方推薦遷移到 **Gateway API**（v1.5, 2026/02 發布）
- AWS ALB Controller 不受影響（AWS 自己維護）

---

## Service

### 三種 type

| type | 對外暴露方式 | 用途 |
|------|------------|------|
| **ClusterIP** | 只有 cluster 內部可連（預設） | 內部服務互相呼叫 |
| **NodePort** | 每個 Node 開固定 port（30000-32767） | 搭配 ALB 等外部 LB |
| **LoadBalancer** | 自動建雲端 LB | 正式對外服務 |

> **Python 類比**：
> - `ClusterIP` = `localhost:8000`，只有自己電腦能連
> - `NodePort` = 把 port 綁到固定號碼對外開放，像 `uvicorn --port 30080`
> - `LoadBalancer` = 前面有 nginx 幫你做反向代理，自動分流

### port vs targetPort

```yaml
ports:
  - port: 80          # Service 對外暴露的 port（cluster 內用這個）
    targetPort: 8081   # Pod 實際 listen 的 port（= containerPort）
```

```python
# Python 類比：
# port=80 是外部打進來的端口
# targetPort=8081 是 uvicorn 實際 bind 的端口
# 就像 nginx proxy_pass http://127.0.0.1:8081 但對外開 80
```

### 內部 DNS 解析

K8s 自動為每個 Service 建立 DNS record，Pod 之間可以直接用名稱互連：

```bash
# 同 namespace → 直接用 Service 名稱
curl http://my-service:80

# 跨 namespace → 加 namespace 名稱
curl http://my-service.other-namespace:80

# 完整 FQDN（較少用，但最明確）
curl http://my-service.other-namespace.svc.cluster.local:80
```

```python
# Python 類比：就像 /etc/hosts 裡面幫你加了一行
# my-service  10.96.0.1
# httpx.get("http://my-service:80/health") 就能直接通

import httpx
# 在 K8s Pod 裡，這樣就能連到同 namespace 的另一個服務
response = httpx.get("http://inference-service:8081/predict")
```
