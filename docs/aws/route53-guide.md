---
sidebar_position: 8
---

# Route53 — AWS DNS 服務

## Route53 是什麼

Route53 是 AWS 的 DNS 服務，負責把域名（`example.com`）翻譯成 IP 地址。

---

## Hosted Zone 兩種類型

| | Public Hosted Zone | Private Hosted Zone (PHZ) |
|---|---|---|
| **誰能查** | 全世界 | 只有關聯的 VPC 內部 |
| **用途** | 公開網站、API | 內部服務互連 |
| **域名範例** | `grafana.example.com` | `vmauth.monitoring.example.internal` |
| **費用** | $0.50/月 + 每百萬查詢 $0.40 | $0.50/月 + 每百萬查詢 $0.40 |

---

## Record 類型

### 常用 Record

| Type | 用途 | 值的格式 |
|------|------|---------|
| **A** | 域名 → IPv4 | `192.168.1.1` |
| **AAAA** | 域名 → IPv6 | `2001:db8::1` |
| **CNAME** | 域名 → 另一個域名 | `internal-k8s-xxx.elb.amazonaws.com` |
| **Alias** | 域名 → AWS 資源（Route53 專屬） | 選 ALB / CloudFront / S3 等 |

### CNAME vs Alias — 核心差異

**問題：ALB 沒有固定 IP，IP 會隨時變。怎麼讓域名指向 ALB？**

#### CNAME（標準 DNS 做法）

```
用戶查 grafana.example.com
  → DNS 回答：去問 internal-k8s-xxx.elb.amazonaws.com（CNAME）
    → DNS 再查一次 → 拿到 ALB 當下的 IP
      → 總共 2 次 DNS 查詢
```

- 需要 **兩次 DNS 查詢**
- 每次查詢都要**收費**
- **不能用在 zone apex**（例如 `example.com` 本身，只能用在 `sub.example.com`）

#### Alias（Route53 專屬捷徑）

```
用戶查 grafana.example.com
  → Route53 內部直接知道 ALB 的 IP（因為 ALB 也在 AWS 裡）
    → 一次就回答 ALB 當下的 IP
      → 總共 1 次 DNS 查詢
```

- 只需要 **一次 DNS 查詢**
- 指向 AWS 資源時**免費**（不收查詢費）
- **可以用在 zone apex**
- Route53 自動追蹤 ALB IP 變化

#### 比較表

| | CNAME | Alias |
|---|---|---|
| **運作方式** | 「去問另一個名字」 | 「我直接告訴你 IP」 |
| **DNS 查詢次數** | 2 次 | 1 次 |
| **費用** | 要錢 | 指向 AWS 資源免費 |
| **Zone apex** | 不能（`example.com` 不行） | 可以 |
| **指向非 AWS 資源** | 可以（任何域名） | 不行（只能指向 AWS 資源） |
| **在其他 DNS provider 可用** | 可以 | 不行（Route53 專屬） |

#### 結論

指向 AWS 資源（ALB、NLB、CloudFront、S3）→ **一律用 Alias**。
指向非 AWS 的外部服務 → 只能用 CNAME。

---

## Alias 支援的 AWS 資源

| AWS 資源 | Alias Record Type |
|----------|------------------|
| ALB / NLB / CLB | A (IPv4) 或 AAAA (IPv6) |
| CloudFront | A |
| S3 靜態網站 | A |
| 另一個 Route53 record（同 HZ） | A / AAAA / CNAME |
| API Gateway | A |
| VPC Endpoint | A |

---

## Route53 Console 操作：建立 Alias A Record

1. **Route53** → **Hosted zones** → 選擇你的 hosted zone
2. **Create record**
3. 填入：

| 欄位 | 值 |
|------|-----|
| Record name | `grafana-central`（會自動帶上 hosted zone 的域名） |
| Record type | **A** |
| Alias | **打開（toggle on）** |
| Route traffic to | **Alias to Application and Classic Load Balancer** |
| Region | 選 ALB 所在的 region（如 US East N. Virginia） |
| 選擇 LB | 從下拉選單選你的 ALB |
| Routing policy | Simple routing |

4. **Create records**

---

## Private Hosted Zone (PHZ) 跨 VPC 使用

PHZ 預設只在建立時關聯的 VPC 內可查。要讓其他 VPC 也能解析，需要 associate：

```
PHZ: monitoring.example.internal
  ├── VPC A (Central) — 建立時自動關聯
  ├── VPC B (Region B) — 需要手動 associate
  └── VPC C (Region C) — 需要手動 associate
```

### 同 Account

```bash
aws route53 associate-vpc-with-hosted-zone \
  --hosted-zone-id Z0123456789 \
  --vpc VPCRegion=us-east-1,VPCId=vpc-xxx
```

### 跨 Account

需要兩步：
1. Zone owner account 授權：`create-vpc-association-authorization`
2. VPC owner account 關聯：`associate-vpc-with-hosted-zone`

---

## Terraform 範例

### Public Hosted Zone + Alias A Record

```hcl
# 指向既有的 public hosted zone
data "aws_route53_zone" "public" {
  name         = "example.com"
  private_zone = false
}

# Alias A record → ALB
resource "aws_route53_record" "grafana_central" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = "grafana-central.example.com"
  type    = "A"

  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}
```

### Private Hosted Zone + CNAME

```hcl
resource "aws_route53_zone" "internal" {
  name = "monitoring.example.internal"

  vpc {
    vpc_id = module.vpc.vpc_id
  }

  lifecycle {
    ignore_changes = [vpc]
  }
}

resource "aws_route53_record" "vmauth" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = "vmauth.monitoring.example.internal"
  type    = "CNAME"
  ttl     = 300
  records = ["internal-k8s-xxx.elb.us-east-1.amazonaws.com"]
}
```

---

## 常見問題

### Q: PHZ 的 record 在 VPC 外面查得到嗎？
不行。PHZ 只有關聯的 VPC 內部可以解析。公司辦公室要能查，需要 Route53 Resolver Endpoint 或 VPN + DNS 轉發。

### Q: Alias record 可以指向其他 account 的 ALB 嗎？
可以，但你需要知道 ALB 的 DNS name 和 hosted zone ID。

### Q: 一個域名可以同時有 CNAME 和其他 record 嗎？
不行。CNAME 是排他的，有 CNAME 就不能有 A、AAAA 或其他 record。這也是 zone apex 不能用 CNAME 的原因（apex 需要 SOA 和 NS record）。Alias 沒有這個限制。
