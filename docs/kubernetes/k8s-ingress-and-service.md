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

---

## AWS ALB Target Type: Instance vs IP Mode

When using AWS ALB Controller with EKS, the ALB needs to know **where to send traffic**. There are two modes:

### Instance Mode (default)

```
Client → ALB → Node EC2:NodePort → kube-proxy (iptables NAT) → Pod:8427
               ↑                    ↑
               2 hops               Extra NAT layer
```

- ALB registers **Node EC2 instances** as targets
- Traffic hits Node's NodePort → kube-proxy forwards to correct Pod
- **Requires**: Service type must be `NodePort` (otherwise no NodePort → port=0 → error)
- No annotation needed (this is the default)

ALB 把流量送到 Node 的 NodePort，Node 上的 kube-proxy 再轉發到 Pod。Service 必須是 NodePort type。

### IP Mode

```
Client → ALB → Pod:8427
               ↑
               1 hop, direct
```

- ALB registers **Pod IPs** directly as targets
- Traffic goes straight to Pod, bypasses Node and kube-proxy
- **Works with any Service type** (ClusterIP or NodePort)
- Requires annotation: `alb.ingress.kubernetes.io/target-type: ip`

ALB 直接送流量到 Pod IP，不經過 Node、不經過 kube-proxy。ClusterIP service 就可以用。

### Setting in Ingress YAML

```yaml
# Instance mode (default, no annotation needed)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    alb.ingress.kubernetes.io/scheme: internal
    # No target-type annotation → defaults to instance mode
    # Service MUST be NodePort type

---
# IP mode (explicit annotation)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    alb.ingress.kubernetes.io/scheme: internal
    alb.ingress.kubernetes.io/target-type: ip    # ← This line
    # Service can be ClusterIP or NodePort
```

### Comparison / 比較

| | Instance Mode (NodePort) | IP Mode |
|---|---|---|
| Service type required / 要求 | Must be `NodePort` | `ClusterIP` or `NodePort` |
| ALB target / 註冊目標 | Node EC2 instance | Pod IP |
| Traffic hops / 流量跳數 | 2 (ALB→Node→Pod) | 1 (ALB→Pod) |
| Goes through kube-proxy / 經過 kube-proxy | Yes (iptables NAT) | No |
| Latency / 延遲 | Slightly higher | Lower |
| Opens port on Node / Node 開 port | Yes (30000-32767) | No |
| Pod scaling response / 擴縮反應 | Slower (update Node targets) | Faster (register/remove Pod IPs directly) |
| Health check accuracy / 健康檢查準確度 | Hits Node, may not reflect Pod state | Hits Pod directly |
| EKS support / EKS 支援 | All versions | Requires VPC CNI (installed by default on EKS) |

### When to use which / 什麼時候用哪個

| Scenario / 場景 | Recommendation / 建議 |
|---|---|
| Existing services with `NodePort` type | Instance mode (default), no change needed / 不用改 |
| New services with `ClusterIP` type (e.g. Helm charts, Operators) | IP mode — add `target-type: ip` / 加一行 annotation |
| Want lower latency / 要更低延遲 | IP mode |
| Mixed in same ALB group / 同一個 ALB group 混用 | OK — each Ingress can have different target-type / 可以，每個 Ingress 各自設 |

### Common error without correct setting / 常見錯誤

If your Service is `ClusterIP` but you don't set `target-type: ip`:

```
Warning  FailedDeployModel  ingress  Failed deploy model due to InvalidParameter:
  1 validation error(s) found.
  - minimum field value of 1, CreateTargetGroupInput.Port.
```

This means ALB Controller tried to register NodePort but got `port=0` because ClusterIP services don't have a NodePort.

如果 Service 是 ClusterIP 但沒設 `target-type: ip`，ALB Controller 拿到 port=0 → AWS 說 port 最小值是 1 → 失敗。

---

## Health Check：Liveness vs Readiness Probe

這是 inference system 最重要的設定之一。Model 載入可能需要 30-120 秒，如果沒設好，K8s 會在 model 還沒 ready 時就把流量打過來，造成 500 error。

### 兩種 Probe 的差異

| Probe | 問的問題 | 失敗的後果 |
|-------|---------|-----------|
| **Readiness** | 「這個 Pod 準備好接流量了嗎？」 | 從 Service 的 endpoint 移除（不殺，只是不送流量） |
| **Liveness** | 「這個 Pod 還活著嗎？」 | 殺掉並重啟 Pod |

```
Model 載入中（30s）：
  Readiness = NOT READY → Service 不把流量送來 ✓
  Liveness  = ALIVE     → Pod 不被殺 ✓

Model 載入完成：
  Readiness = READY     → Service 開始送流量 ✓

Model 掛掉（deadlock / OOM）：
  Liveness  = DEAD      → K8s 重啟 Pod ✓
```

> **Python 類比**：
> ```python
> # Readiness = 你的 FastAPI startup event 還沒跑完
> @app.on_event("startup")
> async def load_model():
>     app.state.model = load_big_model()  # 這段跑完前 readiness = False
>     app.state.ready = True
>
> @app.get("/health/ready")
> async def readiness():
>     if not app.state.ready:
>         raise HTTPException(503)  # 還沒 ready
>     return {"status": "ready"}
>
> # Liveness = 心跳檢測，確認程式沒卡死
> @app.get("/health/live")
> async def liveness():
>     return {"status": "alive"}  # 只要程式能回應就好
> ```

### 完整 Probe 設定範例（推理服務）

```yaml
containers:
  - name: inference-server
    image: my-model-server:latest
    ports:
      - containerPort: 8080

    # Readiness Probe：model 載入完才接流量
    readinessProbe:
      httpGet:
        path: /health/ready
        port: 8080
      initialDelaySeconds: 30   # 等 30s 再開始檢查（model 需要時間載入）
      periodSeconds: 10          # 每 10s 檢查一次
      failureThreshold: 6        # 連續 6 次失敗才標記 not ready（60s 緩衝）
      successThreshold: 1        # 1 次成功就標記 ready

    # Liveness Probe：確認程式沒有掛死
    livenessProbe:
      httpGet:
        path: /health/live
        port: 8080
      initialDelaySeconds: 60   # 比 readiness 更晚開始（等 model 載入完）
      periodSeconds: 30          # 每 30s 檢查一次
      failureThreshold: 3        # 連續 3 次失敗才重啟（90s 容忍）
      timeoutSeconds: 5          # 5s 沒回應算一次失敗
```

**inference system 的設定建議**：
- `initialDelaySeconds` 設為你 model 載入時間 × 1.5（留緩衝）
- Readiness 的 `failureThreshold` 要比 Liveness 寬鬆（不要輕易殺 Pod）
- 如果 model 每次重啟都要重新下載（幾分鐘），設錯 Liveness 會陷入無窮重啟地獄

---

## Resource Requests & Limits

K8s 排程器靠 `requests` 決定把 Pod 放哪台機器，靠 `limits` 防止一個 Pod 吃光整台機器資源。

### CPU / Memory 設定

```yaml
resources:
  requests:
    cpu: "2"           # 保證有 2 顆 CPU core
    memory: "8Gi"      # 保證有 8GB RAM
  limits:
    cpu: "4"           # 最多用到 4 顆 CPU（可以 burst）
    memory: "16Gi"     # 超過 16GB 就被 OOMKilled
```

> **Python 類比**：
> ```python
> # requests = 你跟 AWS 說「我的 EC2 至少要 8GB RAM」→ 排機器用
> # limits   = 你設了 ulimit，超過就被 kill
>
> import resource
> # 類似 limits.memory
> resource.setrlimit(resource.RLIMIT_AS, (16 * 1024**3, 16 * 1024**3))
> ```

### GPU 設定（inference system 必看）

GPU 在 K8s 裡是 **extended resource**，跟 CPU/Memory 不同的是：**requests 必須等於 limits**，不能 burst。

```yaml
resources:
  requests:
    nvidia.com/gpu: "1"   # 申請 1 張 GPU
  limits:
    nvidia.com/gpu: "1"   # 必須跟 requests 一樣
  # CPU/Memory 一樣要設，不然會被排到沒 GPU 的機器
  requests:
    nvidia.com/gpu: "1"
    cpu: "4"
    memory: "16Gi"
  limits:
    nvidia.com/gpu: "1"
    cpu: "8"
    memory: "32Gi"
```

**常見錯誤**：只設 GPU 忘了設 CPU/Memory，導致 Pod 被排到沒有 GPU 的機器後卡住。

完整的 GPU inference Pod 設定見 [Workload 類型](./k8s-workloads) 的 YAML 範例。

---

## HPA — Horizontal Pod Autoscaler

HPA 根據 metrics 自動增減 Pod 數量。對 inference system 來說，用 GPU 利用率或 request queue 深度來 scale 比 CPU 更準確。

```
流量上升 → CPU 使用率升高 → HPA 增加 replica
流量下降 → CPU 使用率下降 → HPA 減少 replica
（有 cooldown 防止震盪）
```

### 基礎 CPU HPA

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: inference-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: inference-server
  minReplicas: 2      # 最少 2 個（保持基本可用性）
  maxReplicas: 10     # 最多 10 個（防止爆炸性 scale）
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70  # CPU 平均超過 70% 就 scale out
```

> **Python 類比**：
> ```python
> # HPA 就像自動調整 Celery worker 數量
> from celery.signals import worker_ready
>
> # 手動版 HPA 概念：
> current_workers = len(celery_app.control.inspect().active())
> queue_depth = redis.llen("celery")
>
> if queue_depth / current_workers > 10:  # 每個 worker 超過 10 個 task
>     scale_out(workers=current_workers + 2)
> elif queue_depth / current_workers < 2:
>     scale_in(workers=max(2, current_workers - 1))
> ```

### 注意事項

- GPU Pod 用 HPA 要小心：GPU 機器很貴，scale out 慢（spot instance warm-up）
- HPA 和 resource requests 搭配才有意義：沒設 requests 的 Pod HPA 算不出利用率
- `minReplicas: 0` 可以節省成本，但會有 cold start（model 重新載入的時間）
