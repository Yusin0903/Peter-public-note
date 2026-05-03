---
sidebar_position: 8
---

# Route53 / ACM / K8s Ingress — 完整關係解析

## 這三個東西各自在幹嘛

```
用戶在瀏覽器輸入 https://grafana.example.com
  │
  │ ① Route53：域名 → IP（你要去哪）
  ▼
  ALB (IP: 10.0.1.50)
  │
  │ ② ACM cert：TLS 握手（證明我是誰）
  │    ALB 出示憑證，瀏覽器驗證合法性
  ▼
  │ ③ K8s Ingress：路由規則（流量去哪個 Pod）
  │    host=grafana.example.com → Grafana Pod :80
  ▼
  Grafana Pod
```

| 元件 | 職責 | 比喻 |
|------|------|------|
| **Route53** | DNS 解析：域名 → IP | 電話簿（查名字找到地址） |
| **ACM Certificate** | TLS 憑證：證明伺服器身分 | 身分證（證明「我是 grafana.example.com」） |
| **K8s Ingress** | 路由規則：請求分配到哪個 Pod | 大樓櫃台（看你找誰，指引到哪間辦公室） |
| **ALB** | 實際執行以上所有 | 大樓本身（有地址、有門禁、有櫃台） |

---

## Route53 是什麼

Route53 是 AWS 的 DNS 服務，負責把域名翻譯成 IP 地址。

### Hosted Zone 兩種類型

| | Public Hosted Zone | Private Hosted Zone (PHZ) |
|---|---|---|
| **誰能查** | 全世界 | 只有關聯的 VPC 內部 |
| **用途** | 公開網站、API | 內部服務互連 |
| **域名範例** | `grafana.example.com` | `vmauth.monitoring.example.internal` |
| **費用** | $0.50/月 + 每百萬查詢 $0.40 | $0.50/月 + 每百萬查詢 $0.40 |

### Record 類型

| Type | 用途 | 值的格式 |
|------|------|---------|
| **A** | 域名 → IPv4 | `192.168.1.1` |
| **AAAA** | 域名 → IPv6 | `2001:db8::1` |
| **CNAME** | 域名 → 另一個域名 | `internal-k8s-xxx.elb.amazonaws.com` |
| **Alias** | 域名 → AWS 資源（Route53 專屬） | 選 ALB / CloudFront / S3 等 |

---

## CNAME vs Alias

**問題：ALB 沒有固定 IP，IP 會隨時變。怎麼讓域名指向 ALB？**

### CNAME（標準 DNS）

```
用戶查 grafana.example.com
  → DNS 回答：去問 internal-k8s-xxx.elb.amazonaws.com（CNAME）
    → DNS 再查一次 → 拿到 ALB 當下的 IP
      → 總共 2 次 DNS 查詢
```

### Alias（Route53 專屬捷徑）

```
用戶查 grafana.example.com
  → Route53 內部直接知道 ALB 的 IP（因為 ALB 也在 AWS 裡）
    → 一次就回答 ALB 當下的 IP
      → 總共 1 次 DNS 查詢
```

### 比較

| | CNAME | Alias |
|---|---|---|
| **運作方式** | 「去問另一個名字」 | 「我直接告訴你 IP」 |
| **DNS 查詢次數** | 2 次 | 1 次 |
| **費用** | 要錢 | 指向 AWS 資源免費 |
| **Zone apex** | 不能（`example.com` 不行） | 可以 |
| **指向非 AWS 資源** | 可以 | 不行（Route53 專屬） |

**結論：** 指向 AWS 資源（ALB、NLB、CloudFront）→ 一律用 Alias。

---

## ACM 是什麼

AWS Certificate Manager，負責管理 TLS 憑證。憑證的作用是讓瀏覽器確認「這個伺服器真的是它說的那個域名」。

### 憑證類型

| 類型 | 涵蓋範圍 | 範例 |
|------|---------|------|
| **單域名** | 一個域名 | `grafana.example.com` |
| **SAN (Subject Alternative Name)** | 多個指定域名 | `grafana.example.com` + `api.example.com` |
| **Wildcard** | 所有子域名（一層） | `*.example.com`（涵蓋 `grafana.example.com`、`api.example.com` 等） |

### ARN 是什麼

ARN 是 ACM 憑證的唯一識別碼（地址）：

```
arn:aws:acm:us-east-1:067240665187:certificate/021ab848-33de-4117-8782-05449a7bcb65
│       │       │          │                      │
│       │       │          │                      └── 憑證 ID
│       │       │          └── AWS Account
│       │       └── Region
│       └── 服務 = ACM
└── AWS 資源
```

ACM cert 建立後 ARN **永遠不變**，即使 renew 也不會換。

### DNS 驗證流程

```
1. ACM Console → Request certificate → 填域名
2. ACM 給你一筆 CNAME record（用來證明你擁有這個域名）
3. 你把 CNAME 加到 Route53
4. ACM 驗證 CNAME 存在 → 發憑證 → 狀態變成 Issued
5. 只要 CNAME 一直在，ACM 會自動 renew
```

---

## K8s Ingress 怎麼串起 Route53 和 ACM

### Ingress YAML 裡的關鍵設定

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    # ② 告訴 ALB 用哪張 ACM cert 做 TLS
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
    # ALB 類型
    alb.ingress.kubernetes.io/scheme: internal
spec:
  ingressClassName: alb
  rules:
  # ③ 路由規則：什麼 host → 哪個 Pod
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

### 三者的依賴關係

```
Route53 (DNS)          ACM (TLS cert)         K8s Ingress (路由)
    │                       │                       │
    │  不依賴任何人          │  DNS 驗證需要 Route53   │  需要 cert ARN
    │                       │                       │  需要 host 域名
    ▼                       ▼                       ▼
    ┌─────────────────── ALB ───────────────────────┐
    │                                               │
    │  1. Route53 把域名解析到 ALB IP               │
    │  2. ALB 用 ACM cert 做 TLS 握手              │
    │  3. ALB 根據 Ingress host rule 轉發到 Pod    │
    └───────────────────────────────────────────────┘
```

### 建立順序

```
1. Route53 Public HZ     ← 可以獨立建（不需要 ACM）
2. ACM Certificate       ← DNS 驗證需要在 Route53 加 CNAME
3. K8s Ingress + Deploy  ← 需要 cert ARN 填入 annotation
4. Route53 A Record      ← 指向 ALB（ALB 要先存在才能選）
```

---

## ALB 做了三件獨立的事

重點：**這三件事是獨立運作的，一個錯不代表全部不通。**

```
請求進來：https://grafana.example.com

1. TLS 握手（用 certificate-arn 指定的 cert）
   → ALB 不管 cert 域名對不對，直接出示
   → 瀏覽器負責驗證域名是否匹配
   → 匹配 → 🔒 安全
   → 不匹配 → ⚠️ 警告，但用戶可以選擇繼續

2. Host Routing（用 Ingress rules 的 host）
   → 看 HTTP header 的 Host 是什麼
   → 匹配 → 轉發到對應的 Pod
   → 不匹配 → 404 或 default backend

3. Target 轉發（用 Ingress backend 的 service/port）
   → 把解密後的 HTTP 流量送到 Pod
```

### 為什麼 cert 域名錯了還能連？

```
你訪問：grafana-central.example.com
ALB 出示的 cert：ti2-stg.example.com（域名不匹配）

1. DNS 解析 → ✅ Route53 有設，解析到 ALB IP
2. TCP 連線 → ✅ ALB :443 可以連
3. TLS 握手 → ⚠️ ALB 出示 cert，瀏覽器發現域名不匹配
   → 瀏覽器顯示警告「不安全」
   → 但用戶可以點「繼續前往」
4. Host Routing → ✅ Host header 匹配 Ingress rule
5. 轉發到 Pod → ✅ Grafana 正常回應
```

**結論：** cert 域名錯了不影響連線，只影響瀏覽器是否顯示「安全」。ALB 不負責驗證 cert 跟域名匹不匹配，那是瀏覽器的工作。

---

## 完整實例：Central Grafana 的 HTTPS 設定

### 目標

讓公司內部網路可以用 `https://ti-grafana-central-stg.visionone.trendmicro.com` 安全連到 Central Grafana。

### 步驟拆解

| 步驟 | 做什麼 | 在哪裡做 |
|------|--------|---------|
| 1 | 申請 ACM cert（域名 `ti-grafana-central-stg.visionone.trendmicro.com`） | ACM Console |
| 2 | DNS 驗證（加 CNAME 到 Route53） | Route53 Console |
| 3 | cert ARN 填入 Ingress annotation | `update_env.sh` → `certificate-arn` |
| 4 | host 填入 Ingress rule | `update_env.sh` → `GRAFANA_CENTRAL_HOSTNAME_PLACEHOLDER` |
| 5 | 部署 → ALB Controller 自動設定 ALB | CI/CD deploy |
| 6 | Route53 加 A record (Alias) → ALB | Route53 Console |
| 7 | 瀏覽器訪問 → Route53 解析 → ALB TLS → Grafana | 驗證 |

### 流量路徑

```
瀏覽器: https://ti-grafana-central-stg.visionone.trendmicro.com
  │
  │ Route53 Public HZ: A (Alias) → Internal ALB
  ▼
  ALB :443
  │ ACM cert: ti-grafana-central-stg.visionone.trendmicro.com
  │ TLS 握手 → 瀏覽器驗證 → 🔒 安全
  │
  │ Ingress host rule 匹配 → 轉發
  ▼
  Grafana Central Pod :80
```

### 驗證 cert 是否正確

```bash
# Terminal
echo | openssl s_client -connect ti-grafana-central-stg.visionone.trendmicro.com:443 \
  -servername ti-grafana-central-stg.visionone.trendmicro.com 2>/dev/null | \
  openssl x509 -noout -subject -issuer -dates

# 預期輸出
subject= CN = ti-grafana-central-stg.visionone.trendmicro.com
issuer= O = Amazon, CN = Amazon RSA 2048 M03
notBefore= ...
notAfter= ...
```

瀏覽器：點網址列 🔒 鎖頭 → Certificate → 看 Issued to 是否匹配。

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

### 注意：Internal NLB DNS 跟 PHZ 不同

Internal NLB 的 auto-generated DNS（如 `k8s-xxx.elb.us-east-1.amazonaws.com`）只能在**它所在的 VPC** 內解析。跨 VPC 即使有 TGW，DNS 也不會自動通。

解法：在 PHZ 加一筆 CNAME 指向 NLB DNS name，讓關聯的 VPC 都能解析。

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
| Region | 選 ALB 所在的 region |
| 選擇 LB | 從下拉選單選你的 ALB |
| Routing policy | Simple routing |

4. **Create records**

---

## Terraform 範例

### Public Hosted Zone + Alias A Record

```hcl
data "aws_route53_zone" "public" {
  name         = "example.com"
  private_zone = false
}

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

### Q: Route53 建立 Public HZ 需要先建 ACM cert 嗎？
不需要，兩個獨立。反過來，ACM DNS 驗證需要 Route53。

### Q: cert 域名錯了為什麼還能連？
ALB 不驗證 cert 域名是否匹配，它只出示 cert。驗證是瀏覽器做的。域名不匹配時瀏覽器會警告，但用戶可以手動繼續。

### Q: PHZ 的 record 在 VPC 外面查得到嗎？
不行。PHZ 只有關聯的 VPC 內部可以解析。

### Q: Alias record 可以指向其他 account 的 ALB 嗎？
可以，但你需要知道 ALB 的 DNS name 和 hosted zone ID。

### Q: 一個域名可以同時有 CNAME 和其他 record 嗎？
不行。CNAME 是排他的。這也是 zone apex 不能用 CNAME 的原因（apex 需要 SOA 和 NS record）。Alias 沒有這個限制。

### Q: Wildcard cert `*.example.com` 跟單域名 cert 怎麼選？
看公司規定。有些公司要求每個 app 有自己的 cert（安全隔離），有些允許 wildcard（方便管理）。Wildcard 不涵蓋 zone apex（`example.com` 本身）和二層子域名（`a.b.example.com`）。
