---
sidebar_position: 6
---

# VPC 網路完整指南：VPC、NAT Gateway、VPC Endpoint、Transit Gateway

這份筆記從 VPC 是什麼講起，接著說明 private subnet 如何出網、如何省掉 NAT Gateway 的費用，最後說明跨 VPC/Region 的連線方式。

---

## VPC 基礎（快速入門）

VPC（Virtual Private Cloud）是你在 AWS 上的「私有網路空間」，就像你在一棟辦公大樓裡有一整層樓的私人辦公室。

```
AWS Region（us-east-1）
└── VPC（10.0.0.0/16）
    ├── Public Subnet（10.0.1.0/24）
    │   ├── 有 Internet Gateway → 可以直接連 internet
    │   └── 資源有 Public IP（例如：Load Balancer、Bastion Host）
    │
    └── Private Subnet（10.0.2.0/24）
        ├── 沒有 Internet Gateway → 無法直接連 internet
        └── 資源只有 Private IP（例如：EC2 inference worker、RDS）
```

> **Python 類比**：
> - VPC = Python 的 `virtualenv`，隔離的網路空間，外面看不到裡面
> - Public Subnet = 你 `virtualenv` 裡公開 expose 的 FastAPI port（0.0.0.0:8080）
> - Private Subnet = 你 `virtualenv` 裡只有內部能呼叫的模組（`localhost:5432`）
>
> ```python
> # Private Subnet 的 EC2 就像這樣：
> # 只能被同一個 VPC 內的機器呼叫，外部無法直接連
>
> # ✅ 可以：VPC 內的 Load Balancer 轉發請求
> # ❌ 不行：從外部 internet 直接 SSH 進去（沒有 Public IP）
> ```

**為什麼要用 Private Subnet？**

Inference worker 不需要被外網直接存取，放 private subnet 更安全：
- 外部攻擊者無法直接連到你的模型服務
- 減少暴露面積（attack surface）
- 資料庫（RDS、Redis）放 private subnet，應用層放 private subnet，只有 Load Balancer 放 public

---

## NAT Gateway — 「出口警衛」

讓 **private subnet 的機器可以連出去 internet**，但外部無法主動連進來。

```
你的 EC2（私有 IP，無法直接上網）
    │
    ▼
NAT Gateway（必須放在 Public Subnet）← 把私有 IP 換成公有 IP
    │
    ▼
Public Internet   ← 資料出去繞一圈公網
    │
    ▼
目的地（例如：GitHub、Docker Hub、外部 API）
```

```python
# Python 類比：
# 就像你的 inference server 在內網，要呼叫外部 API 時
# 必須透過公司的 proxy 出去

import httpx

proxies = {"https://": "http://nat-gateway-ip:3128"}  # NAT Gateway 就是這個 proxy
client = httpx.Client(proxies=proxies)

# EC2 → NAT Gateway（換成公有 IP）→ 外部 API
response = client.get("https://api.openai.com/v1/models")
```

**使用情境：**
- EC2 要下載套件（`apt install`、`pip install`）
- Python inference worker 要呼叫外部 API（OpenAI、Stripe 等）
- 任何 private subnet 的資源需要出去 internet

**收費（us-east-1）：**
- $0.045/小時（存在費，不管有沒有流量）
- $0.045/GB 處理的資料量

---

## VPC Endpoint — 「AWS 服務的內部通道」

**這是最常被忽略但最重要的省錢方式。**

VPC Endpoint 讓你的 EC2 直接存取 S3、DynamoDB 等 AWS 服務，**完全不需要走 NAT Gateway**。

```
沒有 VPC Endpoint（走 NAT Gateway）：
EC2 → NAT Gateway → Internet → S3
費用：$0.045/小時 + $0.045/GB

有 VPC Endpoint（不走 NAT Gateway）：
EC2 → VPC Endpoint → S3（AWS 內部網路）
費用：S3 VPC Endpoint 免費！DynamoDB VPC Endpoint 免費！
```

> **Python 類比**：VPC Endpoint 就像把 `boto3` 的 S3 呼叫從「走外部 HTTP proxy」改成「走內部 Unix socket」，同樣的 API，底層路徑完全不同，但 code 完全不用改。
>
> ```python
> import boto3
>
> # 有沒有 VPC Endpoint，code 完全一樣
> s3 = boto3.client("s3", region_name="us-east-1")
> s3.download_file("my-model-bucket", "models/resnet50.pt", "/tmp/model.pt")
>
> # 差別在於網路路徑：
> # 沒有 VPC Endpoint：EC2 → NAT Gateway → Internet → S3  （要錢）
> # 有 VPC Endpoint：  EC2 → AWS 內部骨幹 → S3          （免費！）
> ```

### 哪些服務有免費 VPC Endpoint？

```
Gateway Endpoint（完全免費，強烈推薦設定）：
├── Amazon S3
└── Amazon DynamoDB

Interface Endpoint（每小時 ~$0.01，有費用但通常值得）：
├── SQS
├── STS（IAM token）
├── CloudWatch Logs
├── Secrets Manager
└── 其他大部分 AWS 服務
```

### Inference System 的推薦設定

```
你的 EC2 Inference Worker（Private Subnet）
    │
    ├──→ S3（存模型檔案、推理結果）  ──→ Gateway VPC Endpoint（免費）
    │
    ├──→ DynamoDB（job metadata）   ──→ Gateway VPC Endpoint（免費）
    │
    ├──→ SQS（任務佇列）            ──→ Interface VPC Endpoint（省 NAT 費用）
    │
    └──→ 外部 API（OpenAI 等）      ──→ NAT Gateway（唯一真正需要的場景）
```

---

## Transit Gateway — 「內部高速公路」

讓 **多個 VPC 或多個 Region 之間互連**，不走公網。

```
Region A（例如 ap-southeast-1）
  └── VPC A（inference worker）
        │
        ▼
   Transit Gateway   ← AWS 自己的骨幹網路，不出 AWS
        │
        ▼
   Region B（例如 us-east-1）
  └── VPC B（中央 metrics / logging 服務）
```

```python
# Python 類比：
# 就像公司內網的直連專線，不用出去公網就能互相通信
# 你的 inference worker 在 ap-southeast-1
# metrics 要推到 us-east-1 的 VictoriaMetrics
# 透過 Transit Gateway = 走公司內部專線，不經過 internet

import httpx

# 不走公網，直接走 AWS 內部骨幹網路
# 對 code 來說跟普通 HTTP 一樣，但底層走的是 Transit Gateway
response = httpx.post(
    "http://victoriametrics.internal:8428/api/v1/import",
    content=metrics_payload,
)
# 費用只有 $0.02/GB，而且不用出 AWS 更安全
```

**使用情境：**
- 10 個 region 的 inference service 要互相溝通
- 把多個 VPC 串接在一起（hub-and-spoke 架構）
- cross-region 推 metrics（各 region 的 Prometheus remote_write 到中央）

---

## 費用計算範例（真實 Inference 工作負載）

**情境：10 個 region，每個 region 有 5 台 EC2 Inference Worker，每天：**
- 從 S3 下載模型：1 GB/天（model warm-up 和更新）
- 推理結果寫入 S3：10 GB/天
- 讀寫 DynamoDB：1 百萬次/天
- 推 metrics 到中央（cross-region）：2 GB/天/region
- 呼叫外部 API：0.5 GB/天

```
# 沒有優化（全走 NAT Gateway）：
NAT Gateway 存在費：
  10 個 region × 1 個 NAT Gateway × $0.045/小時 × 24 × 30 = $324/月

NAT Gateway 流量費（每個 region）：
  S3 讀寫：11 GB × $0.045 = $0.495
  DynamoDB：(幾乎不算 GB)
  Metrics：2 GB × $0.045 = $0.090
  外部 API：0.5 GB × $0.045 = $0.0225
  每個 region/天：~$0.61

10 個 region × $0.61/天 × 30 天 = $183/月

# 合計（未優化）：$324 + $183 = $507/月

# ────────────────────────────────────────

# 優化後（S3/DynamoDB 用 Gateway VPC Endpoint，跨 region 用 Transit Gateway）：
NAT Gateway 存在費：仍然需要（為了外部 API）
  10 region × $0.045/小時 × 24 × 30 = $324/月

NAT Gateway 流量費（只剩外部 API 流量）：
  0.5 GB × $0.045 × 10 region × 30 天 = $6.75/月

Transit Gateway（跨 region metrics）：
  2 GB × $0.02 × 10 region × 30 天 = $12/月

S3 / DynamoDB Gateway Endpoint：$0（免費！）

# 合計（優化後）：$324 + $6.75 + $12 = $342.75/月

# 節省：$507 - $343 ≈ $164/月 ≈ 32% 費用節省
```

**關鍵洞察：**
- S3 和 DynamoDB Gateway Endpoint 永遠應該設定，完全免費
- 跨 region 流量用 Transit Gateway 比 NAT Gateway 便宜 55%（$0.02 vs $0.045/GB）
- NAT Gateway 的存在費（$0.045/小時）佔了大部分成本，如果所有 AWS 服務都走 VPC Endpoint，可以考慮移除 NAT Gateway

---

## 一句話總結

| | NAT Gateway | VPC Endpoint | Transit Gateway |
|--|:-----------:|:------------:|:---------------:|
| 用途 | private → internet | private → AWS 服務 | VPC ↔ VPC / Region ↔ Region |
| 走哪裡 | 公網 | AWS 內部（不出 VPC） | AWS 內部骨幹 |
| 費用/GB | $0.045 | S3/DynamoDB 免費 | $0.02 |
| 典型場景 | 呼叫外部 API | 存取 S3、DynamoDB | 跨 region 服務互通 |

**Inference System 的網路架構建議：**
1. 設定 S3 + DynamoDB Gateway VPC Endpoint（免費，立刻做）
2. 跨 region 通訊用 Transit Gateway
3. 只有真正需要連外部 internet 的流量，才走 NAT Gateway

---

## VPC Peering vs Transit Gateway — 同 Region 跨 VPC

Same region, same account, two VPCs need to talk. Two options:

同 region 同帳號，兩個 VPC 要互連，有兩種方式：

| | VPC Peering | Transit Gateway |
|---|---|---|
| Architecture / 架構 | Point-to-point, direct connection | Hub-and-spoke, central router |
| Cost / 費用 | Free (only pay for data transfer) | TGW hourly fee + data transfer |
| Best for / 適合 | 2-3 VPCs | Many VPCs (5+) |
| Setup / 設定 | Simple (create peering + route tables) | More complex (TGW + attachments + routes) |
| Transitive routing | No — A↔B and B↔C does NOT mean A↔C | Yes — all attached VPCs can reach each other |

```
VPC Peering (point-to-point):
  VPC A ←──────→ VPC B      Direct, no middleman
  VPC A ←──────→ VPC C      Need separate peering
  VPC B    ✗     VPC C      Not automatic! Need another peering

Transit Gateway (hub-and-spoke):
  VPC A ──→ TGW ←── VPC B   All connected through TGW
  VPC C ──→ TGW             A↔B, A↔C, B↔C all work
```

**Key point: networking ≠ DNS.** Even if two VPCs can send packets to each other (via Peering or TGW), DNS resolution is a separate layer. Pod A in VPC-1 asking "what IP is `my-service.internal`?" won't get an answer unless DNS is also configured.

**重點：網路通 ≠ DNS 通。** 即使兩個 VPC 透過 Peering 或 TGW 可以互相送 packet，DNS 是另一層。VPC-1 的 pod 問「`my-service.internal` 是哪個 IP？」不會得到答案，除非 DNS 也有設定。

---

## VPC 與 DNS — Route53 Private Hosted Zone

### The problem / 問題

```
VPC A (EKS cluster A):
  Pod → nslookup my-service.internal → ❓ who is that?

VPC B (EKS cluster B):
  ALB: my-service.internal → 10.x.x.x
  But VPC A doesn't know this!
```

Networking (TGW/Peering) lets packets travel between VPCs, but DNS is a separate system. You need Route53 Private Hosted Zone (PHZ) to make internal hostnames resolvable.

TGW/Peering 讓 packet 能在 VPC 之間傳送，但 DNS 是另一個系統。需要 Route53 PHZ 讓內部域名能被解析。

### Route53 Private Hosted Zone (PHZ)

PHZ = a private DNS zone that only associated VPCs can query. Like a phone book that only certain offices can look up.

PHZ = 私有 DNS zone，只有關聯的 VPC 能查詢。像一本只有特定辦公室能查的電話簿。

```
Step 1: Create PHZ "my-app.internal"
  → A phone book is created, but empty

Step 2: Add DNS records
  → "api.my-app.internal" → CNAME → internal-alb-xxx.elb.amazonaws.com
  → Now the phone book has an entry

Step 3: Associate VPCs
  → VPC A: can look up this phone book ✅
  → VPC B: can look up this phone book ✅
  → VPC C: not associated, can't resolve ❌
```

### Three things needed for cross-VPC DNS / 跨 VPC DNS 需要三件事

| Step | What / 做什麼 | Why / 為什麼 |
|---|---|---|
| 1. Create PHZ | `aws route53 create-hosted-zone --name my-app.internal --vpc VPCRegion=us-east-1,VPCId=vpc-xxx` | Create the phone book, associate with the first VPC |
| 2. Add records | `aws route53 change-resource-record-sets` with CNAME pointing to ALB | Write entries in the phone book |
| 3. Associate additional VPCs | `aws route53 associate-vpc-with-hosted-zone --vpc VPCId=vpc-yyy` | Let other VPCs look up the phone book |

### Common mistake / 常見錯誤

```
✅ Network: VPC A → TGW → VPC B (packets can travel)
❌ DNS: Pod in VPC A → nslookup service.internal → NXDOMAIN

"I set up TGW but DNS still doesn't resolve!"
→ TGW only handles network routing, not DNS
→ You still need PHZ + VPC association
```

---

## VPC 與 EKS / Kubernetes 的關係

### VPC is the network layer, K8s is the application layer

VPC 是網路層，K8s 是應用層。兩者關係：

```
AWS Layer (VPC):
┌─────────────────────────────────┐
│ VPC (10.0.0.0/16)               │
│  ├── Subnet A (10.0.1.0/24)    │
│  │    └── EC2 Node 1            │  ← EKS worker node
│  │         ├── Pod A (10.0.1.5) │  ← Pod IP from VPC subnet (VPC CNI)
│  │         └── Pod B (10.0.1.6) │
│  ├── Subnet B (10.0.2.0/24)    │
│  │    └── EC2 Node 2            │
│  │         └── Pod C (10.0.2.3) │
│  └── ALB (internal)             │  ← Created by ALB Controller
└─────────────────────────────────┘

K8s Layer (inside EKS):
┌─────────────────────────────────┐
│ Namespace: monitoring           │
│  ├── Service: prometheus (ClusterIP)    │
│  ├── Service: grafana (NodePort)        │
│  └── Ingress: grafana-ingress-alb      │ → triggers ALB creation
│                                         │
│ Namespace: app                          │
│  └── Deployment: my-app                 │
└─────────────────────────────────┘
```

### Key relationships / 關鍵關係

| Concept | Explanation |
|---|---|
| One EKS cluster = one VPC | An EKS cluster's nodes all run in a single VPC. EKS 的 node 都跑在同一個 VPC 裡 |
| Pod IPs come from VPC | VPC CNI assigns VPC subnet IPs to pods. Not virtual IPs — real, routable VPC IPs. Pod IP 來自 VPC subnet，是真的可路由 IP |
| K8s namespace ≠ VPC | Namespaces are logical grouping inside K8s, unrelated to VPC structure. Namespace 是 K8s 內部邏輯分組，跟 VPC 無關 |
| K8s Service ≠ ALB | Service is internal to K8s. ALB is an AWS resource created by ALB Controller when it sees an Ingress. Service 是 K8s 內部的，ALB 是 AWS 資源 |
| Cross-VPC = cross-cluster | Two EKS clusters in different VPCs need VPC-level networking (Peering/TGW) + DNS (PHZ) to communicate. 跨 VPC = 跨 cluster，需要網路層 + DNS 層都通 |

### What VPC handles vs what K8s handles

| Layer | VPC handles / VPC 管 | K8s handles / K8s 管 |
|---|---|---|
| IP allocation | Subnet CIDR → Node IP, Pod IP (via VPC CNI) | Service ClusterIP (virtual, kube-proxy manages) |
| Load balancing | ALB / NLB (AWS managed) | Service (kube-proxy iptables) |
| DNS | Route53 PHZ for cross-VPC resolution | CoreDNS for in-cluster Service names |
| Network isolation | Security Groups, NACLs, VPC boundaries | NetworkPolicy (optional, CNI-dependent) |
| Cross-cluster communication | TGW, VPC Peering, VPC Endpoint | Not K8s's job — relies on VPC layer |
