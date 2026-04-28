---
sidebar_position: 11
---

# AWS Certificate Manager (ACM)

ACM 是 AWS 的 **TLS/SSL 憑證管理服務**。幫你申請、管理、部署 HTTPS 用的憑證，而且免費。

---

## 基本概念

```
使用者 → https://my-app.example.com → ALB (用 ACM 憑證做 TLS 終結) → Pod (HTTP)
                                        ↑
                                     ACM 管這段
```

| 概念 | 說明 |
|---|---|
| **TLS/SSL 憑證** | 證明「這個 domain 是我的」，讓瀏覽器顯示 HTTPS 鎖頭 |
| **ACM** | AWS 免費幫你申請和管理憑證 |
| **TLS 終結 (TLS Termination)** | ALB 負責解密 HTTPS，後端 Pod 只收 HTTP |
| **Domain Validation** | 證明你擁有這個 domain（透過 DNS 或 Email） |

---

## 憑證類型

| 類型 | 涵蓋範圍 | 範例 |
|---|---|---|
| **單一域名** | 只有一個 domain | `api.example.com` |
| **Wildcard** | 一個層級的所有子域名 | `*.example.com` → 涵蓋 `api.example.com`, `app.example.com` 等 |
| **SAN (Subject Alternative Names)** | 列舉多個特定域名 | `api.example.com`, `app.example.com`, `admin.example.com` |

### Wildcard vs SAN

```
Wildcard 憑證: *.example.com
  ✅ api.example.com
  ✅ app.example.com
  ✅ anything.example.com
  ❌ sub.api.example.com  (不涵蓋兩層)
  ❌ example.com          (不涵蓋裸域名)

SAN 憑證: [api.example.com, app.example.com, admin.example.com]
  ✅ api.example.com
  ✅ app.example.com
  ✅ admin.example.com
  ❌ new.example.com      (沒列在清單裡)
  → 要加新域名就要重新申請/修改憑證
```

---

## Domain Validation (DNS 驗證)

ACM 需要你證明你擁有這個 domain。最常用的是 **DNS 驗證**：

```
1. 你在 ACM 申請 api.example.com 的憑證
2. ACM 給你一筆 CNAME record:
   _abc123.api.example.com → _xyz789.acm-validations.aws.
3. 你把這筆 CNAME 加到 Route53 (或你的 DNS provider)
4. ACM 驗證 CNAME 存在 → 確認你擁有這個 domain → 發憑證
5. 只要 CNAME 一直存在，ACM 會自動 renew 憑證 (不用手動)
```

ACM Console 裡的 **"Create record in Route53"** 按鈕就是幫你做步驟 3。

---

## 跟 ALB 搭配使用

ALB 做 TLS 終結，你不需要在 Pod 裡面處理 HTTPS：

```
Client                    ALB                      Pod
  │                        │                        │
  │── HTTPS:443 ──────────→│                        │
  │   (ACM 憑證加密)        │── HTTP:80 ────────────→│
  │                        │   (內部明文, 安全)      │
  │←── HTTPS response ─────│←── HTTP response ──────│
```

### 在 K8s Ingress 裡指定 ACM 憑證

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:123456:certificate/abc-123
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-Res-2021-06
```

ALB Controller 看到 `certificate-arn` → 自動設定 ALB 的 HTTPS listener 使用這張憑證。

---

## Public vs Private 憑證

| | ACM Public Certificate | ACM Private Certificate |
|---|---|---|
| 費用 | 免費 | ~$400/月 (Private CA 費用) |
| 域名 | 公共域名 (`example.com`) | 私有域名 (`.internal`, `.local`) |
| 驗證方式 | DNS 或 Email | Private CA 直接簽發 |
| 用途 | 對外服務 | 內部服務互相通訊 |

### 為什麼 `.internal` 域名不能用 Public Certificate

ACM Public Certificate 只能發給**公共可驗證**的域名。`.internal` 不是公共 DNS 上的域名，ACM 無法用 DNS 驗證你擁有它。

要用 `.internal` 域名的 HTTPS，只有兩個選擇：
1. **AWS Private CA** — 貴 (~$400/月)
2. **跳過 TLS 驗證** — `insecure_skip_verify: true`（內網可接受）

---

## 常見情境

### 情境 1：新服務要 HTTPS

```
1. 確認你的域名在哪張 ACM 憑證上
   → ACM Console → 找 certificate → 看 Domain names 列表

2a. 域名已在憑證上 → 直接用，在 Ingress 設定 certificate-arn
2b. 域名不在 → 需要申請新憑證或修改現有憑證
```

### 情境 2：SAN 憑證要加新域名

```
ACM 不支援直接修改已發行的 SAN 憑證。
→ 要重新申請一張包含所有域名的新憑證
→ 做 DNS 驗證
→ 把 ALB 的 certificate-arn 換成新的
```

### 情境 3：內部服務要 HTTPS 但用 `.internal` 域名

```
選項 A：Private CA (貴)
選項 B：用公共域名 (例如 *.app.example.com) 取代 .internal
選項 C：HTTP only (內網流量可接受)
選項 D：HTTPS + insecure_skip_verify (跳過驗證, 內網可接受)
```

---

## 常用 CLI

```bash
# 列出所有憑證
aws acm list-certificates --region us-east-1

# 查看憑證詳情（涵蓋哪些域名）
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:us-east-1:123456:certificate/abc-123 \
  --query 'Certificate.SubjectAlternativeNames'

# 申請新憑證（DNS 驗證）
aws acm request-certificate \
  --domain-name api.example.com \
  --validation-method DNS \
  --subject-alternative-names app.example.com admin.example.com

# 查看驗證狀態
aws acm describe-certificate \
  --certificate-arn <arn> \
  --query 'Certificate.DomainValidationOptions'
```

---

## ACM vs 自己管憑證

| | ACM | 自己管 (Let's Encrypt, cert-manager) |
|---|---|---|
| 費用 | 免費 (Public) | 免費 (Let's Encrypt) |
| 自動 renew | 有 (只要 DNS 驗證 CNAME 在) | 要自己設定 (cert-manager CronJob) |
| 跟 ALB 整合 | 原生支援 (annotation 一行) | 要額外設定 |
| 私有域名 | 需要 Private CA ($400/月) | cert-manager + 自建 CA (免費) |
| 適合 | AWS ALB/NLB/CloudFront | Nginx Ingress, 非 AWS 環境 |
