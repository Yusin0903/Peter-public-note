---
sidebar_position: 1
---

# Kubernetes 核心概念筆記

## 請求進入 Pod 的三層架構

```
外部使用者
    │
    ▼
┌──────────┐
│  Ingress │  L7 路由規則（/api/v1/* → Service A, /dashboard/* → Service B）
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

- **本質**：L7 路由規則表，定義「什麼 path → 哪個 Service」
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

```bash
# 同 namespace → 直接用名稱
curl http://my-service:80

# 跨 namespace → 加 namespace
curl http://my-service.my-namespace:80

# 完整 FQDN
curl http://my-service.my-namespace.svc.cluster.local:80
```

---

## CronJob

```yaml
schedule: "10 */1 * * *"        # 每小時第 10 分鐘執行
concurrencyPolicy: Forbid       # 上一次沒跑完不啟動新的
successfulJobsHistoryLimit: 1   # 只保留 1 個成功紀錄
backoffLimit: 3                 # 失敗最多重試 3 次
```

---

## Pod Log 查詢

```bash
# 單一 Pod
kubectl logs -f <pod-name>

# 用 label 看所有 replica 的 log
kubectl logs -f -l app=my-app

# 所有 Pod 的 log 一起 grep
kubectl logs -l app=my-app --all-containers | grep "keyword"
```

多 replica 時每個 Pod 只有部分流量的 log，要查特定 request 建議用集中式 log（CloudWatch Logs Insights）或 trace ID。

---

## AWS 容器服務比較

| | EKS (Kubernetes) | Lambda |
|---|---|---|
| 運作方式 | 你管 Pod，持續運行 | 事件觸發，跑完消失 |
| 適合 | 長時間服務、複雜架構 | 短任務（≤15 min）、事件驅動 |
| 費用 | Node 開著就收錢 | 只收執行時間 |
| 管理成本 | 要管 node、scaling、部署 | 幾乎不用管 |

EKS = AWS 代管的 Kubernetes，幫你管 control plane，你只管 worker node 和部署。
