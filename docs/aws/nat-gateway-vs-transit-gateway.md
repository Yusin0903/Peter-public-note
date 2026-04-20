---
sidebar_position: 6
---

# NAT Gateway vs Transit Gateway

這兩個都叫 "Gateway"，但用途完全不同。

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

**使用情境：**
- EC2 要下載套件（apt install、npm install）
- Lambda 要呼叫外部 API
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

**使用情境：**
- 10 個 region 的服務要互相溝通
- 把多個 VPC 串接在一起（hub-and-spoke 架構）
- cross-region 推資料（例如：各 region 的 Prometheus remote_write 到中央）

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
| 典型場景 | EC2 下載套件 | 跨 region 服務互通 |

---

## 實際案例

我們有 10 個 region 的 Prometheus，每個都要把 metrics 推到中央 VictoriaMetrics。

- **如果走 NAT Gateway：** 資料出去公網再回來，每 GB $0.045
- **如果走 Transit Gateway：** 資料在 AWS 內部傳，每 GB $0.02，更快更安全

這也是為什麼 cross-region metrics 傳輸的成本其實很低 — Transit Gateway 本來就是設計來做這件事的。
