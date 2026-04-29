---
sidebar_position: 14
---

# 多 Region 監控架構（完整網路細節）

> 這份筆記記錄集中式監控架構的網路層細節，包含 VPC、ALB、Ingress、DNS、ACM、Secrets Manager 的完整設定細節。
> **環境：** Central 跑在 `us-east-1` EKS，各 Region Prometheus 推資料進來。

---

## 整體架構圖

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│  各 Region（每個 Region 都有這個結構）                                   │
│                                                                                  │
│  Region: SG (ap-southeast-1)          Region: EU (eu-central-1)   ...            │
│  ┌───────────────────────────┐         ┌───────────────────────────┐             │
│  │  EKS Cluster              │         │  EKS Cluster              │             │
│  │  namespace: monitoring    │         │  namespace: monitoring    │             │
│  │                           │         │                           │             │
│  │  Prometheus               │         │  Prometheus               │             │
│  │  ├── scrape pods          │         │  ├── scrape pods          │             │
│  │  ├── external_labels:     │         │  ├── external_labels:     │             │
│  │  │   region: sg           │         │  │   region: eu           │             │
│  │  │   cluster: <your-cluster>         │         │  │   cluster: <your-cluster>    │             │
│  │  │   environment: <your-env>     │         │  │   environment: <your-env>    │             │
│  │  └── remote_write ────────┼──┐      │  └── remote_write ────────┼──┐          │
│  └───────────────────────────┘  │      └───────────────────────────┘  │          │
└─────────────────────────────────┼────────────────────────────────────┼──────────┘
                                   │ HTTPS :443                          │ HTTPS :443
                                   │ bearer_token（從 K8s Secret 讀）    │
                                   │                                     │
                       ┌───────────▼──────────────────────────▼──────────────────────┐
                       │           AWS Transit Gateway（TGW 內網傳輸）                │
                       │           跨 Region 流量不走公開網路，$0.02/GB               │
                       └────────────────────────────┬────────────────────────────────┘
                                                    │
                                                    ▼
┌──────────────────────────────────────────────────────────────────────────────────┐
│  Central（us-east-1，Central EKS Cluster）                                           │
│  VPC CIDR: 10.0.0.0/22 （示意）                                                         │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │  AWS Route53 Private Hosted Zone（PHZ）                                      │ │
│  │  Zone: monitoring.example.internal                                                    │ │
│  │                                                                              │ │
│  │  vmauth.monitoring.example.internal        → internal ALB (CNAME/A record)           │ │
│  │  grafana-central.monitoring.example.internal → internal ALB (CNAME/A record)         │ │
│  └─────────────────────────┬────────────────────────────────────────────────────┘│
│                             │ DNS 解析（VPC 內部可達）                            │
│                             ▼                                                    │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  Internal ALB（AWS Application Load Balancer）                           │   │
│  │  scheme: internal（不暴露到公網）                                        │   │
│  │  group.name: monitor-ingress-controller                                  │   │
│  │                                                                          │   │
│  │  Listener: HTTPS :443                                                    │   │
│  │  ├── SSL Policy: ELBSecurityPolicy-TLS13-1-2-Res-2021-06                 │   │
│  │  ├── Certificate: ACM arn:aws:acm:us-east-1:...:certificate/057c8b92... │   │
│  │  │                                                                       │   │
│  │  │  Listener Rules（依 Host header 分流）：                              │   │
│  │  ├── vmauth.monitoring.example.internal     → vmauth Service :8427               │   │
│  │  │   (group.order: 2)                                                    │   │
│  │  └── grafana-central.monitoring.example.internal → grafana-central Service :80   │   │
│  │      (group.order: 3)                                                    │   │
│  └──────────────────────────┬─────────────────────────────────────────────────┘│
│                target-type: ip（直接到 pod IP，不經 NodePort）                   │
│                             │                                                    │
│                             ▼                                                    │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  EKS namespace: monitoring                                               │   │
│  │                                                                          │   │
│  │  ┌───────────────────────────────────────────────────────────────────┐   │   │
│  │  │  vmauth (Deployment, 2 replicas)                                  │   │   │
│  │  │  - 驗證 bearer token（per-region VMUser CRD）                     │   │   │
│  │  │  - 路由 /insert → vminsert                                        │   │   │
│  │  │  - 路由 /select → vmselect（Grafana 讀取）                        │   │   │
│  │  │  Service: vmauth-vmauth-central :8427                             │   │   │
│  │  └──────────────────┬────────────────────────────────────────────────┘   │   │
│  │                     │ 寫入路由                       讀取路由              │   │
│  │           ┌─────────▼─────────┐               ┌──────────────────┐      │   │
│  │           │  vminsert × 2     │               │  vmselect × 2    │      │   │
│  │           │  (stateless)      │               │  (stateless)     │      │   │
│  │           │  consistent hash  │               │  fan-out query   │      │   │
│  │           └─────────┬─────────┘               └──────────────────┘      │   │
│  │         replication │ Factor=2                        ▲                  │   │
│  │    ┌────────────────┼────────────────┐                │                  │   │
│  │    ▼                ▼                ▼                │                  │   │
│  │ vmstorage-0    vmstorage-1    vmstorage-2             │                  │   │
│  │ (500Gi EBS)    (500Gi EBS)    (500Gi EBS)             │                  │   │
│  │ gp3 StorageClass              每筆資料寫到            │                  │   │
│  │                               2 個節點                │                  │   │
│  │                                                       │                  │   │
│  │  ┌────────────────────────────────────────────────────┘                  │   │
│  │  │  grafana-central (StatefulSet, 1 replica)                             │   │
│  │  │  - 讀取 vmselect（直連，不經 vmauth）                                 │   │
│  │  │    url: http://vmselect-vmcluster-central.monitoring.svc:8481         │   │
│  │  │  - datasource UID: victoriametrics-ds（確定性 UID）                   │   │
│  │  │  - 20Gi EBS 持久化（dashboard state、user sessions）                  │   │
│  │  │  Service: grafana-central :80 (NodePort)                              │   │
│  │  └────────────────────────────────────────────────────────────────────── │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

## 各層細節說明

### 1. 各 Region：Prometheus remote_write 設定

每個 Region 的 Prometheus 只需加這個設定（只改 config，不重啟 pod）：

```yaml
# prometheus.yml 加的部分
global:
  external_labels:
    region: sg          # 每個 Region 不同（sg / us / eu / jp / in / au / za）
    cluster: <your-cluster>        # 環境名稱
    environment: <your-env>

remote_write:
  - url: "https://vmauth.monitoring.example.internal/insert/0/prometheus/api/v1/write"
    bearer_token_file: /etc/secrets/vmauth/token   # 從 K8s Secret 掛載
    queue_config:
      max_samples_per_send: 10000
      batch_send_deadline: 5s
    tls_config:
      insecure_skip_verify: false   # 走 TLS，驗證 ACM 憑證
```

**K8s Secret（由 Terraform 從 Secrets Manager 讀取後建立）：**

```hcl
# infra/aws/terraform/eks/modules/monitor/prometheus.tf
resource "kubernetes_secret" "vmauth_remote_write_token" {
  metadata {
    name      = "vmauth-remote-write-token"
    namespace = "monitoring"
  }
  data = {
    token = data.aws_secretsmanager_secret_version.vmauth_remote_write_token.secret_string
  }
}
```

---

### 2. Transit Gateway — 跨 Region 流量路徑

```
SG Region                           Central (us-east-1)
┌─────────────────┐                 ┌──────────────────────────┐
│ EKS pod         │                 │ VPC: 10.0.0.0/22 （示意）        │
│ 10.x.x.x        │                 │                          │
└────────┬────────┘                 └──────────────┬───────────┘
         │                                         │
         │  Private Subnet                         │ Private Subnet
         ▼                                         ▼
┌─────────────────┐                 ┌──────────────────────────┐
│ TGW Attachment  │                 │ TGW Attachment           │
│ (SG VPC)        │                 │ (US VPC)                 │
└────────┬────────┘                 └──────────────┬───────────┘
         │                                         │
         └──────────── AWS TGW 骨幹網路 ───────────┘
                       （不走公網 NAT）
                       ~$0.02/GB
```

**為什麼走 TGW 不走公網：**
- 不需要 NAT Gateway（省 $0.045/GB）
- 不需要 public IP（安全）
- 延遲更低（AWS 骨幹 vs 公網）
- remote_write 是 async + WAL 緩衝，50-200ms 延遲完全可接受

---

### 3. Internal ALB + Ingress 設定細節

ALB 由 **AWS Load Balancer Controller**（跑在 EKS 上）根據 Kubernetes Ingress resource 自動建立。

**vmauth Ingress（group.order: 2）：**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vmauth-ingress-alb
  namespace: monitoring
  annotations:
    # 使用已存在的 ALB（group.name 相同 = 共用同一個 ALB，不建新的）
    alb.ingress.kubernetes.io/group.name: monitor-ingress-controller
    alb.ingress.kubernetes.io/group.order: "2"
    
    # internal = 不暴露到公網（只有 VPC 內 + TGW peering 的 VPC 可達）
    alb.ingress.kubernetes.io/scheme: internal
    
    # ACM 憑證（wildcard 或精確 CN = vmauth.monitoring.example.internal）
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:<ACCOUNT_ID>:certificate/<CERT_ID>
    
    # TLS 1.3 only policy（不允許 TLS 1.2 以下）
    alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-Res-2021-06
    
    # 只監聽 HTTPS 443
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    
    # target-type: ip = ALB 直接轉發到 pod IP，不走 NodePort
    # 需要 VPC CNI（pod 有 VPC IP），不需要 kube-proxy DNAT
    alb.ingress.kubernetes.io/target-type: ip
spec:
  ingressClassName: alb
  rules:
  - host: vmauth.monitoring.example.internal
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: vmauth-vmauth-central
            port:
              number: 8427
```

**Grafana Ingress（group.order: 3）：**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-central-ingress-alb
  namespace: monitoring
  annotations:
    alb.ingress.kubernetes.io/group.name: monitor-ingress-controller   # 同一個 ALB
    alb.ingress.kubernetes.io/group.order: "3"
    alb.ingress.kubernetes.io/scheme: internal
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:...
    alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-Res-2021-06
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/target-type: ip
spec:
  ingressClassName: alb
  rules:
  - host: grafana-central.monitoring.example.internal
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana-central
            port:
              number: 80
```

**group.name 的意義：** 兩個 Ingress 用同一個 `group.name`，AWS LBC 把它們合併成 **同一個 ALB** 的兩個 listener rule，不會建立兩個 ALB。省費用也省維運。

**target-type: ip 的意義：** 

```
target-type: instance（舊方式）：
  ALB → NodePort → kube-proxy DNAT → Pod
  需要 NodePort range (30000-32767)，多跳一次

target-type: ip（新方式，需要 VPC CNI）：
  ALB → Pod IP 直接
  Pod IP 就是 VPC IP（因為 VPC CNI），ALB 可以直接轉發
  少一跳，延遲更低
```

---

### 4. ACM 憑證

```
Certificate ARN: arn:aws:acm:us-east-1:<ACCOUNT_ID>:certificate/<CERT_ID>
Region: us-east-1（必須與 ALB 同 Region）
Domain: *.monitoring.example.internal（Private CA 簽發，不是 public trust）

涵蓋：
  vmauth.monitoring.example.internal
  grafana-central.monitoring.example.internal
  （其他 *.monitoring.example.internal 域名）
```

**為什麼是 Private CA：**
- `*.monitoring.example.internal` 是 internal domain，不存在於公網 DNS
- Let's Encrypt / ACM Public 無法驗證這個 domain（DNS-01 challenge 需要公網 DNS）
- 用 AWS Private CA 或 self-signed certificate + ACM import

---

### 5. Route53 Private Hosted Zone（PHZ）

```
Zone: monitoring.example.internal
Type: Private（只在 VPC 內有效）
Associated VPCs:
  - us-east-1 VPC（Central EKS 所在）
  - 其他透過 TGW 連接的 VPC（需要 PHZ associte）

Records:
  vmauth.monitoring.example.internal          → CNAME → internal ALB DNS name
  grafana-central.monitoring.example.internal → CNAME → internal ALB DNS name

Internal ALB DNS name 格式：
  internal-k8s-xxx-yyy.us-east-1.elb.amazonaws.com
```

**PHZ 與 TGW 的搭配（重要陷阱）：**

⚠️ **TGW 連通 ≠ DNS 解析連通**。Route53 PHZ 預設只在「明確關聯的 VPC」內有效，透過 TGW 連進來的 VPC **不會自動繼承 DNS 解析**。

這是新 Region 接入時最常見的靜默失敗：網路封包走得通，但 pod 解析不了 `vmauth.monitoring.example.internal`，remote_write 一直報 DNS lookup failed。

**解法（三選一）：**

1. **PHZ 跨帳號/跨 VPC 關聯**（推薦）
   - 在 Route53 console 把每個 Region 的 VPC 明確加入 PHZ 的 Associated VPCs
   - 跨帳號需要先用 CLI 建立 authorization，再 associate
   ```bash
   # 在 PHZ 所在帳號建立授權
   aws route53 create-vpc-association-authorization \
     --hosted-zone-id <PHZ_ID> \
     --vpc VPCRegion=ap-southeast-1,VPCId=<SG_VPC_ID>
   
   # 在遠端帳號執行 associate
   aws route53 associate-vpc-with-hosted-zone \
     --hosted-zone-id <PHZ_ID> \
     --vpc VPCRegion=ap-southeast-1,VPCId=<SG_VPC_ID>
   ```

2. **Route53 Resolver Forwarding Rules**
   - 在各 Region VPC 建立 Inbound/Outbound Resolver endpoint
   - 建立 Forwarding Rule：`*.monitoring.example.internal` → Central VPC 的 Resolver IP
   - 費用：~$0.125/endpoint-hour + $0.40/1M queries

3. **不用 PHZ，直接用 ALB DNS name**（最簡單）
   - Prometheus remote_write URL 直接填 ALB 的 DNS name（`internal-k8s-xxx.us-east-1.elb.amazonaws.com`）
   - 但 ALB DNS 會在 ALB 重建時變更，不如 PHZ 穩定
   - 短期可用，長期建議用方法 1

---

### 6. Secrets Manager — Token 管理

```
Token 結構（每個 Region 一個獨立 token）：

/monitoring/vmauth-token-<env>  → 環境 1 Prometheus 的 write token
/monitoring/vmauth-token-<env>  → 環境 2 Prometheus 的 write token
/monitoring/grafana-reader-token → Grafana read-only token
/monitoring/grafana-admin-password → Grafana admin 密碼

Terraform 讀取方式：
  data "aws_secretsmanager_secret_version" "vmauth_token" {
    for_each  = var.region_tokens  # map: {prod = "/path/...", staging = "/path/..."}
    secret_id = each.value
  }

→ 在 VMUser CRD 裡 inline bearerToken（不存在 K8s Secret，直接 apply time 讀取）
→ 各 Region Prometheus 的 token 存在該 Region 的 K8s Secret 裡（由 terraform 建立）
```

**安全隔離設計：**
- 每個 Region 有獨立 token — 一個 token 洩漏不影響其他 Region
- Write token 只能 `/insert/...`（vmauth VMUser CRD 限制）
- Read token（Grafana 用）只能 `/select/...`，無法寫入
- Admin 密碼不在 Terraform 明文 — 只在 Secrets Manager

---

### 7. VictoriaMetrics Operator — VMAuth 路由規則

```
VMAuth CRD（namespace selector: 所有 namespace 的 VMUser）
    │
    ├── VMUser: vmagent-region-<env>
    │   bearerToken: <env-token>
    │   targetRefs: vminsert, paths: ["/insert/0/prometheus/.*"]
    │
    ├── VMUser: vmagent-region-<env2>
    │   bearerToken: <env2-token>
    │   targetRefs: vminsert, paths: ["/insert/0/prometheus/.*"]
    │
    └── VMUser: grafana-reader
        bearerToken: <grafana-reader-token>
        targetRefs: vmselect, paths: ["/select/0/prometheus/.*"]

Prometheus remote_write URL 格式：
  https://vmauth.monitoring.example.internal/insert/0/prometheus/api/v1/write

vmauth 內部轉發：
  /insert/0/prometheus/... → http://vminsert-vmcluster-central.monitoring.svc:8480/insert/0/prometheus/...

Grafana datasource URL（直連，不過 vmauth）：
  http://vmselect-vmcluster-central.monitoring.svc:8481/select/0/prometheus
```

---

## 請求完整流程（寫入）

```
1. 各 Region Prometheus（例如 SG）每 5s batch 打包 remote_write 請求
   POST https://vmauth.monitoring.example.internal/insert/0/prometheus/api/v1/write
   Authorization: Bearer <sg-token>

2. DNS 解析：
   vmauth.monitoring.example.internal
   → Route53 PHZ CNAME
   → internal ALB DNS（internal-k8s-xxx.us-east-1.elb.amazonaws.com）
   → ALB IP

3. TGW 路由：
   SG VPC → TGW → US VPC（10.0.0.0/22）（示意）

4. ALB 收到請求：
   - Host: vmauth.monitoring.example.internal → 對應 group.order: 2 的 listener rule
   - SSL terminate（TLS 1.3，ACM cert）
   - Forward to vmauth pod IP :8427（target-type: ip）

5. vmauth 處理：
   - 驗證 Bearer token → 對應到 VMUser: vmagent-region-sg
   - 路由規則：/insert/... → vminsert
   - HTTP forward to http://vminsert-vmcluster-central.monitoring.svc:8480/...

6. vminsert 處理：
   - Consistent hash（by metric labels）
   - 每筆資料寫到 2 個 vmstorage（replicationFactor=2）

7. vmstorage：
   - 寫入本地 EBS gp3（/vm-data/）
   - ack 回 vminsert → vmauth → ALB → Prometheus
```

## 請求完整流程（查詢）

```
1. 工程師開瀏覽器：https://grafana-central.monitoring.example.internal

2. DNS → ALB → Grafana pod IP（target-type: ip，直接到 pod，不走 NodePort）

3. Grafana 載入 dashboard，執行 PromQL：
   GET http://vmselect-vmcluster-central.monitoring.svc:8481/select/0/prometheus/api/v1/query_range
   （Grafana 直接走 K8s 內部 DNS，不過 vmauth，不過 ALB）

4. vmselect fan-out 到所有 vmstorage 節點（3 個）

5. 合併 + 去重（replication 產生的重複） → 回傳給 Grafana

6. Grafana 渲染 panel
```

---

## VPC & Subnet 設計

```
Central EKS（us-east-1）：
  VPC CIDR: 10.0.0.0/22 （示意）

  Public Subnets（ALB 不在這，但 NAT GW 在）：
    10.0.0.0/26  (us-east-1a)
    10.0.0.64/26 (us-east-1b)
    10.0.0.128/26 (us-east-1c)

  Private Subnets（EKS nodes 在這，Internal ALB 也在這）：
    10.0.1.0/24  (us-east-1a)
    10.0.2.0/24 (us-east-1b)
    10.0.3.0/24 (us-east-1c)

  EKS Node Type: t3.xlarge（4 vCPU, 16GB RAM）
  Node Count: 3 desired, 3-10 range
  EBS per node: 100Gi

  Storage Classes:
    gp3（custom StorageClass，用於 vmstorage PVC）
    ← 比 gp2 便宜 20%，IOPS/throughput 可獨立設定
```

---

## Dashboard 部署方式（IaC）

```
Grafana sidecar ConfigMap 模式：

1. Terraform 讀取 dashboards/ 目錄下的所有 *.json
   resource "kubernetes_config_map" "grafana_central_dashboards" {
     data = {
       for f in fileset("${path.module}/dashboards", "*.json") :
       f => file("${path.module}/dashboards/${f}")
     }
   }

2. Grafana Helm values 設定 provider：
   dashboardsConfigMaps:
     central-monitoring: grafana-central-dashboards

3. Grafana sidecar 監控 ConfigMap label，
   label "dashboard-provider: central-monitoring" 的 ConfigMap 自動載入
   → 不需要重啟 Grafana pod，新增 dashboard = update ConfigMap

Dashboard datasource UID 必須設定為 victoriametrics-ds（確定性 UID）：
  所有 dashboard JSON 裡的 datasource UID 都要是這個值，
  否則 Grafana 顯示 "datasource not found"
```

---

## Security Group 設定（常見靜默失敗來源）

EKS 使用 VPC CNI，pod 有獨立 VPC IP，ALB 直接對 pod IP 發起連線。Security Group 必須明確允許：

```
ALB Security Group → vmauth pod SG：
  Inbound: TCP 8427 from ALB SG

vmauth pod SG → vminsert pod SG：
  Inbound: TCP 8480 from vmauth SG

vminsert pod SG → vmstorage pod SG：
  Inbound: TCP 8400 (write) from vminsert SG

vmselect pod SG → vmstorage pod SG：
  Inbound: TCP 8401 (read) from vmselect SG

ALB Security Group → grafana pod SG：
  Inbound: TCP 3000 (or NodePort) from ALB SG

各 Region EKS node SG → vmauth pod SG（跨 Region remote_write via TGW）：
  Inbound: TCP 8427 from 各 Region VPC CIDR
```

> 缺少任一條規則都會造成靜默失敗：連線 timeout，Prometheus 日誌顯示 `context deadline exceeded`，資料停止進入 VM。

---

## ALB Idle Timeout 與 remote_write 長連線

**問題：** ALB 預設 idle timeout 是 **60 秒**。Prometheus remote_write 使用持久 HTTP 連線（keep-alive），在低流量時段連線可能超過 60 秒沒有資料傳輸，ALB 會主動關閉連線。

**症狀：** 每隔 60 秒出現一次 `connection reset by peer` 或 `EOF`，Prometheus 自動重試，資料最終不丟失，但 remote_write error 計數持續上升，看起來像 TGW 問題。

**解法：**
```
方法 1（推薦）：把 ALB idle timeout 調高到 300s
  → Terraform 在 ALB Ingress annotation 加：
    alb.ingress.kubernetes.io/load-balancer-attributes: idle_timeout.timeout_seconds=300

方法 2：在 Prometheus remote_write 設定短一點的 keepalive
  remote_write:
    - url: ...
      http_config:
        tls_config: ...
      # 讓 Prometheus 主動在 50s 後重建連線，避免被 ALB 切斷
```

---

## WAL 緩衝與 TGW 中斷容忍

Prometheus WAL（Write-Ahead Log）預設緩衝約 **2 小時**的資料。

```
TGW 中斷 < 2 小時：
  Prometheus 繼續 scrape，資料存在 WAL
  TGW 恢復後自動補發，資料不丟失

TGW 中斷 > 2 小時：
  WAL 滿了開始 drop 舊資料
  恢復後有 gap（有些時間點的資料永久丟失）

在 ~75K samples/sec 下，WAL 每分鐘累積約 4.5M samples
超過 2 小時 = ~540M samples 可能丟失

改善方法：
  - 換成 VMAgent 取代 Prometheus（VMAgent 支援可設定更長的持久磁碟 queue）
  - 設定 remote_write queue_config.max_samples_per_send 和 max_shards
```

**高基數 Region 特別注意：** 高基數服務每次 scrape 可能產生數百萬個 samples，遠超過 `max_samples_per_send`（預設 10,000）。需要調整：
```yaml
remote_write:
  - url: ...
    queue_config:
      max_samples_per_send: 10000
      max_shards: 50          # 預設 200，但 SG 高基數建議先測試
      capacity: 100000        # 每個 shard 的 buffer 大小
```
