---
sidebar_position: 15
---

# ALB（Application Load Balancer）

HTTP/HTTPS 流量入口，根據 path 或 header 分流到不同後端。

---

## 架構

```
Internet
   │
   ▼
ALB（port 443，SSL termination 在這裡）
   ├── Listener Rule: /api/*     → Target Group A（EKS Pod）
   ├── Listener Rule: /admin/*   → Target Group B（EKS Pod）
   └── Listener Rule: /*         → Target Group C（Frontend）
```

---

## 三個核心概念

| 概念 | 說明 |
|---|---|
| Listener | ALB 監聽哪個 port（80 / 443）及 protocol |
| Target Group | 一組後端（EC2 / Pod / IP），ALB 把流量打進去 |
| Health Check | ALB 定期打 target 確認還活著，不健康的自動排除 |

---

## 配合 K8s Ingress

在 EKS 上，`aws-load-balancer-controller` 會把 `Ingress` 物件自動轉換成 ALB 設定：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  rules:
    - http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: my-api
                port:
                  number: 8080
```

---

## ALB vs NLB

```
ALB → Layer 7，看 HTTP header/path，適合 web 服務
NLB → Layer 4，看 TCP/UDP，適合低延遲、非 HTTP 協定
```

---

## 一句話總結

| 情境 | 選擇 |
|---|---|
| HTTP/HTTPS 服務對外 | ALB |
| 需要 path-based routing | ALB |
| TCP/UDP 低延遲（gRPC、遊戲）| NLB |
| K8s Ingress | ALB + aws-load-balancer-controller |
