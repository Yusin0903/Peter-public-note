---
sidebar_position: 6
---

# NAT Gateway vs Transit Gateway

這兩個都叫 "Gateway"，但用途完全不同。

> **Python 類比一句話**：
> - `NAT Gateway` = 你的 Python script 透過代理伺服器連外網（private → internet）
> - `Transit Gateway` = 公司內網的高速專線，讓不同辦公室的機器直接互連（VPC ↔ VPC）

---

## NAT Gateway — 「出口警衛」

讓 **private subnet 的機器可以連出去 internet**。

```
你的 EC2（私有 IP，無法直接上網）
    │
    ▼
NAT Gateway   ← 把私有 IP 換成公有 IP
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
- Python inference worker 要呼叫外部 API
- 任何 private subnet 的資源需要出去 internet

**收費：**
- $0.045/GB（資料走公網，比較貴）
- 每小時還要付 $0.045 的存在費

---

## Transit Gateway — 「內部高速公路」

讓 **多個 VPC 或多個 Region 之間互連**，不走公網。

```
Region A（例如 ap-southeast-1）
  └── VPC A
        │
        ▼
   Transit Gateway   ← AWS 自己的骨幹網路，不出 AWS
        │
        ▼
   Region B（例如 us-east-1）
  └── VPC B
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

**收費：**
- $0.02/GB（在 AWS 內部走，比公網便宜）
- 不需要 NAT Gateway，省掉 $0.045/GB

---

## 一句話總結

| | NAT Gateway | Transit Gateway |
|--|:-----------:|:---------------:|
| 用途 | private → internet | VPC ↔ VPC / Region ↔ Region |
| 走哪裡 | 公網 | AWS 內部骨幹 |
| 費用/GB | $0.045 | $0.02 |
| 典型場景 | EC2 下載套件 / 呼叫外部 API | 跨 region 服務互通 |

---

## 實際案例

10 個 region 的 Prometheus，每個都要把 metrics 推到中央 VictoriaMetrics：

```python
# Prometheus remote_write config（各 region 的設定）
# 資料走 Transit Gateway → 直接打到中央 VPC 的 VictoriaMetrics

remote_write:
  - url: "http://victoriametrics.central-vpc.internal:8428/api/v1/write"
    # 走 Transit Gateway，不出 AWS
    # $0.02/GB vs NAT Gateway 的 $0.045/GB
    # 10 個 region 每天推幾百 GB → 省下大量費用
```

- **如果走 NAT Gateway**：資料出去公網再回來，每 GB $0.045
- **如果走 Transit Gateway**：資料在 AWS 內部傳，每 GB $0.02，更快更安全

這也是為什麼 cross-region metrics 傳輸的成本其實很低 — Transit Gateway 本來就是設計來做這件事的。
