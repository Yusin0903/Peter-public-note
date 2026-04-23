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
