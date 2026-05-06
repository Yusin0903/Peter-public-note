---
sidebar_position: 5
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

### port vs targetPort

```yaml
ports:
  - port: 80          # Service 對外暴露的 port（cluster 內用這個）
    targetPort: 8081   # Pod 實際 listen 的 port（= containerPort）
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

### 注意事項

- GPU Pod 用 HPA 要小心：GPU 機器很貴，scale out 慢（spot instance warm-up）
- HPA 和 resource requests 搭配才有意義：沒設 requests 的 Pod HPA 算不出利用率
- `minReplicas: 0` 可以節省成本，但會有 cold start（model 重新載入的時間）

---

## AWS EKS: Ingress 與 ALB 的關係

Ingress 本身**不是**網路入口，它只是一份 YAML 規則文件。真正建立 Load Balancer 的是 Ingress Controller。

### 建立 ALB 的前提條件

Ingress 建立後**不一定**會自動建立 ALB，需要同時滿足：

1. 叢集中已安裝 **AWS Load Balancer Controller**
2. Ingress 的 `ingressClassName: alb`（或 annotation `kubernetes.io/ingress.class: alb`）
3. Controller 有正確的 **IAM 權限**（如 CreateLoadBalancer、AddTags 等）
4. VPC subnet 有正確的 **tags**（`kubernetes.io/role/internal-elb` 或 `kubernetes.io/role/elb`）

### 不會建立新 ALB 的情況

| 情況 | 結果 |
|------|------|
| 沒裝 AWS LB Controller | Ingress 卡住，沒有 address，不會有任何動作 |
| 用其他 IngressClass（nginx、traefik） | 建立對應的 LB（NGINX 通常搭配 NLB/CLB） |
| 多個 Ingress 共用 `group.name` | 掛到既有 ALB 上，不會建新的 |

### 流程（條件都滿足時）

```
你寫 Ingress YAML（規則, ingressClassName: alb）
  → AWS LB Controller 偵測到新的 Ingress
    → 檢查有沒有同 group.name 的 ALB
      → 有 → 掛到既有 ALB（新增 listener rule）
      → 沒有 → 建立新 ALB
    → ALB 根據 Ingress 裡的 host/path 規則轉發到 Pod
```

刪除 Ingress → 如果是該 ALB group 的最後一個 Ingress，ALB 也會自動被刪除。

### 為什麼 Pod 不能直接對外

```
外部流量 → ??? → Pod
```

Pod IP 是 cluster 內部的（VPC CNI 分配），外部網路連不到。一定需要一個 Load Balancer 作為入口：

- **Ingress + ALB** — L7 入口，適合 HTTP/HTTPS 服務
- **Service LoadBalancer + NLB** — L4 入口，適合 TCP/UDP 服務

---

## ALB vs NLB 完整比較

### 基本差異

| | ALB (Application LB) | NLB (Network LB) |
|---|---|---|
| **OSI 層級** | L7 (HTTP/HTTPS) | L4 (TCP/UDP) |
| **理解的東西** | HTTP header、host、path、method | 只看 IP + port |
| **TLS** | ALB 做 TLS termination（需要 ACM cert） | TCP passthrough（不管 TLS） |
| **路由能力** | host-based、path-based、header-based | 無，一個 port 對應一個 target group |
| **延遲** | 較高（要解析 HTTP） | 超低（純 TCP 轉發） |
| **費用** | 按 LCU（規則數+連線數+頻寬） | 按 NLCU（連線數+頻寬），通常較便宜 |
| **靜態 IP** | 不支援 | 支援（可綁 Elastic IP） |

### NLB 「是 Service 嗎」——兩層觀念

K8s 裡的 `Service` ≠ AWS 的 `NLB`，是兩個層次的物件，靠 **AWS Load Balancer Controller** 串起來。

```
K8s 層              AWS 層
──────────         ──────────────
Service            Network Load Balancer (NLB)
type=LoadBalancer  
   │                   │
   │  ←── AWS LB Controller 把這兩個綁起來 ──→ │
   │                   │
   ↓                   ↓
   把 traffic 從 NLB 導到 Pod
```

流程：

```
1. terragrunt apply / kubectl apply
   → 建出 K8s Service (type: LoadBalancer)
   → 此時 Service status.loadBalancer.ingress 還空著

2. AWS Load Balancer Controller (cluster 內 Pod) watch K8s API
   → 看到 type=LoadBalancer 的 Service
   → 呼叫 AWS API 建一顆真實 NLB
   → AWS 隨機產生 DNS：k8s-monitori-vmauthnl-XXXX-YYYY.elb.us-east-1.amazonaws.com
                                              ↑↑↑↑  ↑↑↑↑
                                              hash（每次重建都會變）
   → DNS 寫回 Service 的 status.loadBalancer.ingress.hostname

3. kubectl get svc 才看得到 EXTERNAL-IP
```

**生命週期是綁在一起的**：

| 動作 | K8s Service | AWS NLB |
|---|---|---|
| `kubectl delete svc xxx` | ❌ 砍 | 跟著被砍（Controller 會 deregister） |
| AWS Console 手動砍 NLB | 還在 | ❌ 砍 → Controller 30 秒後重建一顆新的（DNS 變） |
| `terraform destroy` 砍 `kubectl_manifest` | ❌ 砍 | 跟著被砍 |
| Pod / Endpoint 變動 | 不變 | 不變（NLB 自己更新 target group） |

**NLB DNS hash 不可控**——AWS 隨機產生。你只能控制 NLB **name**（用 `service.beta.kubernetes.io/aws-load-balancer-name` annotation），但 DNS 還是會含 hash。

→ 想要「DNS 永遠不變」=** Route 53 alias** 指向 NLB DNS，下游用 Route 53 hostname 而不是直接用 NLB DNS。NLB 重建後 alias 跟著 reconcile（Terraform `aws_route53_record` + `data.aws_lb` 自動 query 新 DNS）。

---

### K8s 裡怎麼建

| | ALB | NLB |
|---|---|---|
| **K8s 資源** | Ingress | Service (type: LoadBalancer) |
| **觸發方式** | `ingressClassName: alb` | Service annotations |
| **誰建 LB** | AWS LB Controller | AWS LB Controller |

```yaml
# ALB — 透過 Ingress 建立
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    alb.ingress.kubernetes.io/scheme: internal
    alb.ingress.kubernetes.io/target-type: ip
spec:
  ingressClassName: alb
  rules:
  - host: grafana.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 80
```

```yaml
# NLB — 透過 Service 建立
apiVersion: v1
kind: Service
metadata:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "external"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internal"
spec:
  type: LoadBalancer
  selector:
    app: vmauth
  ports:
    - port: 8427
      targetPort: 8427
      protocol: TCP
```

### 什麼時候用哪個

| 場景 | 選擇 | 原因 |
|------|------|------|
| HTTP 網頁服務（Grafana、Web App） | **ALB** | 需要 HTTPS、host/path routing、redirect |
| Metrics 寫入（Prometheus remote_write） | **NLB** | 只需要 TCP 轉發，不需要 TLS termination |
| gRPC 服務 | **ALB** 或 **NLB** | ALB 支援 gRPC（L7），NLB 也行（L4 TCP） |
| 需要固定 IP | **NLB** | ALB 不支援靜態 IP |
| 多個服務共用一個 LB | **ALB** | 用 Ingress group 共用，靠 host/path 分流 |

### ALB Ingress Group（共用 ALB）

多個 Ingress 可以共用同一個 ALB，靠 `group.name` 綁定，`group.order` 決定規則優先順序：

```
ALB (group: monitor-ingress-controller)
  ├── order 1: host=vmauth.xxx    → vmauth Pods
  ├── order 2: host=grafana.xxx   → grafana-central Pods
  └── order 10: wildcard *         → legacy grafana Pods
```

每個 Ingress 獨立設定自己的 host、path、target-type，但流量都走同一個 ALB，省錢也省 DNS 設定。

### Route53 DNS 指向 LB

LB 建立後 AWS 會自動分配一個很長的 DNS name，你無法自訂。要用好記的域名需要 Route53：

| 方式 | 適用場景 |
|------|---------|
| **A record + Alias → ALB** | 推薦。免費、少一次 DNS lookup、支援 zone apex |
| **CNAME → LB DNS name** | 可用但不推薦。多一次 lookup、要收費、不能用在 zone apex |

Alias 是 Route53 專屬功能，告訴 Route53「這個域名 = 那個 ALB」，Route53 自動追蹤 ALB IP 變化回給查詢者。

### 實際案例：監控架構的 LB 分配

```
Central Grafana（HTTP 網頁）
  → ALB (Ingress, L7)
    → HTTPS TLS termination (ACM cert)
    → host-based routing
    → grafana-central Pod :80

vmauth（Prometheus remote_write 接收端）
  → NLB (Service LoadBalancer, L4)
    → TCP passthrough, 不需要 TLS
    → vmauth Pod :8427
```

Grafana 用 ALB 因為需要 HTTPS + host routing；vmauth 用 NLB 因為只需要 TCP 轉發。
