---
sidebar_position: 6
---

# NAT Gateway vs Transit Gateway

Both have "Gateway" in the name, but they serve completely different purposes.

> **Python analogy in one line**:
> - `NAT Gateway` = your Python script going through a proxy to reach the internet (private → internet)
> - `Transit Gateway` = a private leased line between offices, machines connect directly without touching the internet (VPC ↔ VPC)

---

## NAT Gateway — "Exit Guard"

Lets **machines in private subnets access the internet**.

```
Your EC2 (private IP, can't reach internet directly)
    │
    ▼
NAT Gateway   ← Translates private IP to public IP
    │
    ▼
Public Internet   ← Data goes out through public network
    │
    ▼
Destination (e.g., GitHub, Docker Hub, external APIs)
```

```python
# Python analogy:
# Your inference server is on a private network, calling an external API
# requires going through a company proxy — NAT Gateway is that proxy

import httpx

proxies = {"https://": "http://nat-gateway-ip:3128"}  # NAT Gateway = this proxy
client = httpx.Client(proxies=proxies)

# EC2 → NAT Gateway (swap to public IP) → external API
response = client.get("https://api.openai.com/v1/models")
```

**Use cases:**
- EC2 downloading packages (`apt install`, `pip install`)
- Python inference worker calling external APIs
- Any private subnet resource needing internet access

**Pricing:**
- $0.045/GB (data goes through public network, more expensive)
- $0.045/hour existence fee

---

## Transit Gateway — "Internal Highway"

Connects **multiple VPCs or Regions** without going through the public internet.

```
Region A (e.g., ap-southeast-1)
  └── VPC A
        │
        ▼
   Transit Gateway   ← AWS backbone network, stays within AWS
        │
        ▼
   Region B (e.g., us-east-1)
  └── VPC B
```

```python
# Python analogy:
# A direct internal network line between offices — no public internet needed
# Your inference worker is in ap-southeast-1
# Metrics need to reach VictoriaMetrics in us-east-1
# Transit Gateway = company intranet leased line, never leaves AWS

import httpx

# No public internet — goes through AWS internal backbone
# From code's perspective it's just a normal HTTP call
response = httpx.post(
    "http://victoriametrics.internal:8428/api/v1/import",
    content=metrics_payload,
)
# Only $0.02/GB, and more secure since it never leaves AWS
```

**Use cases:**
- 10 regions of inference services need to communicate
- Connect multiple VPCs together (hub-and-spoke architecture)
- Cross-region metrics push (Prometheus `remote_write` to central storage)

**Pricing:**
- $0.02/GB (stays within AWS, cheaper than public network)
- No NAT Gateway needed, saves $0.045/GB

---

## One-Line Summary

| | NAT Gateway | Transit Gateway |
|--|:-----------:|:---------------:|
| Purpose | private → internet | VPC ↔ VPC / Region ↔ Region |
| Network path | Public internet | AWS internal backbone |
| Cost/GB | $0.045 | $0.02 |
| Typical scenario | EC2 downloading packages / calling external APIs | Cross-region service communication |

---

## Real-World Example

10 regions of Prometheus each pushing metrics to a central VictoriaMetrics:

```python
# Prometheus remote_write config (each region)
# Data travels via Transit Gateway → directly hits central VPC's VictoriaMetrics

remote_write:
  - url: "http://victoriametrics.central-vpc.internal:8428/api/v1/write"
    # Goes through Transit Gateway, never leaves AWS
    # $0.02/GB vs NAT Gateway's $0.045/GB
    # 10 regions pushing hundreds of GB/day → significant savings
```

- **Via NAT Gateway**: data goes out to the public internet and back — $0.045/GB
- **Via Transit Gateway**: data stays within AWS — $0.02/GB, faster and more secure

This is why cross-region metrics transfer costs are actually very low — Transit Gateway is purpose-built for exactly this.
