---
sidebar_position: 1
---

# OSI 模型、ACL、Proxy 白話完全指南

> 當同事說「這個 ACL 擋住了」或「用 proxy 繞掉」，你需要知道的所有概念。

---

## OSI 7 層模型白話版

OSI 模型是「網路通訊怎麼運作」的分層框架。每一層只負責自己的事，不管其他層。

```
Layer 7 — Application（應用層）   HTTP, HTTPS, gRPC, WebSocket
Layer 6 — Presentation（表示層）  加密/解密（TLS）、資料格式（JSON, XML）
Layer 5 — Session（會話層）       連線管理（幾乎被 L4 吸收）
Layer 4 — Transport（傳輸層）     TCP, UDP — 負責「可靠傳輸」和「port 號」
Layer 3 — Network（網路層）       IP — 負責「路由」，決定封包怎麼從 A 到 B
Layer 2 — Data Link（資料連結層） MAC address — 同一個網段內的傳輸
Layer 1 — Physical（實體層）      實際的電纜、光纖、Wi-Fi 訊號
```

**白話理解：**

```
你在瀏覽器輸入 https://example.com/api/data

L7（應用層）：
  瀏覽器產生 HTTP GET 請求
  「我要 /api/data 這個資源」

L6（表示層）：
  TLS 加密整個 HTTP 請求
  讓中間人看不到內容

L4（傳輸層）：
  加上 TCP header，包含 src port 和 dst port（443）
  負責確保封包都到達、沒有遺漏

L3（網路層）：
  加上 IP header，包含 src IP 和 dst IP
  路由器看這層決定封包往哪裡送

L2（資料連結層）：
  加上 MAC address
  同一個網段（LAN）內找到下一跳

L1（實體層）：
  把 0 和 1 變成電訊號/光訊號送出去
```

> **類比：寄包裹**
> - L7 = 包裹的內容物（你要寄什麼）
> - L4 = 寄件人電話 + 收件人電話（port）
> - L3 = 寄件地址 + 收件地址（IP）
> - L2 = 交給哪個快遞員（MAC）
> - L1 = 快遞員開車的馬路（實體線路）

---

## 實際工作只需要記住三層

```
L7（應用層）：HTTP/HTTPS、host、path、header、body
  → 這層做的事：URL routing、認證、WAF、API Gateway

L4（傳輸層）：IP + Port、TCP/UDP
  → 這層做的事：防火牆、Load Balancer（NLB）、port 白名單

L3（網路層）：IP、CIDR、路由
  → 這層做的事：路由表、subnet、VPC peering
```

---

## ACL 是什麼

ACL（Access Control List）= 存取控制清單，就是一張「允許/拒絕」的規則表。

```
ACL 的基本結構：
Rule 1: 允許 IP 10.0.0.0/24 的流量進入 port 443
Rule 2: 拒絕 IP 192.168.1.0/24 的所有流量
Rule 3: 允許所有人存取 port 80
Rule 4: 拒絕其他所有（default deny）
```

### AWS 上各層的 ACL

| 名稱 | 層級 | 範圍 | 特點 |
|------|------|------|------|
| **Network ACL（NACL）** | L3/L4 | Subnet 層 | stateless，進出要分別設規則 |
| **Security Group（SG）** | L4 | EC2/Pod 層 | stateful，允許進就自動允許回應 |
| **WAF（Web Application Firewall）** | L7 | ALB/CloudFront 層 | 可以根據 HTTP header、body、URL 來決定允許/拒絕 |
| **K8s NetworkPolicy** | L3/L4 | Pod 層 | 控制哪些 Pod 可以跟哪些 Pod 溝通 |

### NACL vs Security Group 的關鍵差異

```
NACL（stateless）：
  進的規則和出的規則是分開的
  → 你允許 TCP port 443 進來
  → 但回應封包（ephemeral port）要出去，你也要明確允許出去
  → 忘記設出去的規則 = 連線建立但沒有回應

Security Group（stateful）：
  允許進來的連線，回應自動被允許出去
  → 只需要設「進來的規則」
  → 更符合人類直覺
```

---

## Proxy 是什麼

Proxy（代理）= 幫你轉發請求的中間人。

```
沒有 proxy：
Client → 直接連 → Server

有 proxy：
Client → Proxy → Server
Client 看起來是在跟 Proxy 說話
Server 看起來是在跟 Proxy 說話
兩邊都不直接知道對方的真實位置
```

### Forward Proxy vs Reverse Proxy

```
Forward Proxy（正向代理）：
  代理的是 Client
  Client → Forward Proxy → Internet
  用途：翻牆、隱藏 client IP、企業內網過濾

  例子：你在公司，公司規定所有流量走 proxy
  你 → 公司 proxy → Google
  Google 看到的來源是公司 proxy 的 IP，不是你的 IP

Reverse Proxy（反向代理）：
  代理的是 Server
  Internet → Reverse Proxy → Backend Server
  用途：Load Balancing、SSL termination、隱藏 server IP

  例子：你打開 example.com
  你 → Nginx（reverse proxy）→ 後端 app server
  你以為在跟 example.com 說話，其實後面有很多台 server
```

> **白話類比：**
> - Forward Proxy = 你的助理，幫你打電話給別人（別人不知道是你打的）
> - Reverse Proxy = 公司的總機，幫公司接電話（你不知道接電話的是哪個員工）

---

## 為什麼 Proxy 可以繞過 ACL

這是重點。ACL 通常是根據 **IP 和 Port** 來判斷要不要允許流量。

```
情境：
  你的服務（IP: 10.0.1.5）
  想連到 DB（IP: 10.0.2.10, Port: 5432）
  但 NACL 規則：拒絕 10.0.1.0/24 存取 port 5432

  ❌ 直連被擋：
  你（10.0.1.5） → DB（10.0.2.10:5432）= NACL 拒絕

  ✅ 透過 proxy 繞過：
  你（10.0.1.5） → Proxy（10.0.3.1:8080）= NACL 允許（10.0.3.0/24 沒被擋）
  Proxy（10.0.3.1） → DB（10.0.2.10:5432）= Proxy 的 IP 被允許

  結果：你透過 proxy 成功連到 DB
  NACL 從未「看到」你直接連 DB
```

**為什麼可以這樣？**

因為 NACL 是 stateless 的 L3/L4 規則，它只看：
- 封包的來源 IP
- 封包的目的 IP
- Port

它不知道「這個請求背後的真正發起人是誰」。Proxy 換掉了來源 IP，ACL 就看不出來了。

---

## L7 ACL（WAF）更難繞

L7 的 WAF 看的不只是 IP，還看 HTTP 內容：

```
WAF 可以根據這些來擋：
- HTTP header（User-Agent、X-Forwarded-For）
- URL path（/admin/*）
- Request body（有沒有 SQL injection 的字串）
- Request 頻率（rate limiting）
- 地理位置（GeoIP）

所以 L7 WAF 更難繞：
- 換 IP 沒用（WAF 看的是請求內容）
- 需要知道 WAF 的規則才能繞
```

---

## AWS 上的實際對照

```
你的 EKS Pod（10.0.1.5）想存取另一個 VPC 的 DB

Layer 3 路由：
  兩個 VPC 要先 peering 或走 Transit Gateway
  路由表要有對方的 CIDR

Layer 4 NACL：
  目標 subnet 的 NACL 要允許你的 IP 進入 port 5432

Layer 4 Security Group：
  DB 的 Security Group 要允許你的 Pod IP（或 SG）存取 port 5432

如果其中一層擋住：
  → 加 proxy（在被允許的 subnet 裡）來轉發

實際情境：
  同事說「幫你建一個 proxy 在 us-east-1，繞過 SG 限制」
  = 在已被允許的地方加一台機器，讓它幫你轉發到被擋住的目標
```

---

## 快速判斷被哪層擋住

```
無法連線時，從低層往高層排查：

1. L3（路由）：
   ping <target_ip>
   如果 ping 不通 → 路由沒通，或 NACL 把 ICMP 擋掉

2. L4（port）：
   nc -zv <target_ip> <port>
   telnet <target_ip> <port>
   如果 port 連不上 → Security Group 或 NACL 擋掉

3. L7（應用）：
   curl -v https://<target>
   如果 port 通但 HTTP 回 403/401 → 應用層的 ACL（WAF、認證）擋掉
```

---

## 一句話總結

| 概念 | 白話 |
|------|------|
| OSI L3 | IP 位址，決定封包去哪 |
| OSI L4 | Port，決定封包給哪個程式 |
| OSI L7 | HTTP 內容，決定做什麼事 |
| ACL | 一張允許/拒絕的規則表，看 IP 和 Port |
| NACL | AWS subnet 層的 ACL，stateless |
| Security Group | AWS 機器層的防火牆，stateful |
| WAF | L7 的防火牆，看 HTTP 內容 |
| Forward Proxy | 幫 client 轉發，隱藏 client 真實 IP |
| Reverse Proxy | 幫 server 接收，隱藏 server 真實 IP |
| Proxy 繞過 ACL | ACL 看 IP，Proxy 換掉來源 IP，ACL 就看不出來 |

---

## English Version

### OSI Model — Plain English

```
Layer 7 — Application:  HTTP, HTTPS, gRPC — what the app sends/receives
Layer 6 — Presentation: TLS encryption/decryption, data format (JSON, XML)
Layer 5 — Session:      Connection management (mostly absorbed by L4)
Layer 4 — Transport:    TCP/UDP — port numbers, reliable delivery
Layer 3 — Network:      IP — routing, how packets get from A to B
Layer 2 — Data Link:    MAC address — delivery within same network segment
Layer 1 — Physical:     Cables, fiber, Wi-Fi signals
```

**What you actually need to know:**
- **L3** = IP address, routing
- **L4** = Port number, TCP/UDP (firewall rules)
- **L7** = HTTP content, headers, URL (WAF, API Gateway)

### ACL (Access Control List)

A list of allow/deny rules. Evaluated top-to-bottom, first match wins.

```
Rule 1: ALLOW  src 10.0.0.0/24  dst port 443
Rule 2: DENY   src 192.168.1.0/24  any
Rule 3: ALLOW  any  dst port 80
Rule 4: DENY   all  (default deny)
```

**AWS ACL types:**

| Name | Layer | Scope | Key trait |
|------|-------|-------|-----------|
| Network ACL (NACL) | L3/L4 | Subnet | Stateless — inbound and outbound rules are separate |
| Security Group (SG) | L4 | EC2/Pod | Stateful — allowing inbound auto-allows response |
| WAF | L7 | ALB/CloudFront | Inspects HTTP content (headers, body, URL) |
| K8s NetworkPolicy | L3/L4 | Pod | Controls Pod-to-Pod communication |

### Proxy

A middleman that forwards requests on your behalf.

```
Without proxy:  Client ──────────────────→ Server

With proxy:     Client → Proxy → Server
```

**Forward Proxy** = Acts on behalf of the **client**
- Client → Forward Proxy → Internet
- Use case: bypass restrictions, hide client IP, corporate filtering

**Reverse Proxy** = Acts on behalf of the **server**
- Internet → Reverse Proxy → Backend
- Use case: load balancing, SSL termination, hide backend IPs

### Why Proxy Can Bypass ACL

ACL rules check **source IP and port**. They don't know who is "behind" the request.

```
Scenario:
  Your service (10.0.1.5) wants to reach DB (10.0.2.10:5432)
  NACL rule: DENY 10.0.1.0/24 → port 5432

  ❌ Direct: 10.0.1.5 → 10.0.2.10:5432  ← blocked by NACL

  ✅ Via proxy:
     10.0.1.5 → Proxy (10.0.3.1:8080)   ← NACL allows this
     Proxy (10.0.3.1) → 10.0.2.10:5432  ← Proxy IP is allowed

The NACL never sees 10.0.1.5 directly connecting to the DB.
The proxy swaps the source IP — NACL can't tell the difference.
```

**L7 WAF is harder to bypass** because it inspects HTTP content (headers, body, URL), not just IP/port.

### Debugging Connection Issues

```bash
# L3 — routing/ICMP
ping <target_ip>

# L4 — port reachability
nc -zv <target_ip> <port>
telnet <target_ip> <port>

# L7 — application response
curl -v https://<target>

# If ping fails → routing or NACL blocking ICMP
# If port fails → Security Group or NACL blocking the port
# If port works but HTTP 403 → L7 ACL (WAF, auth) blocking
```
