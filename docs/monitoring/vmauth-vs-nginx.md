---
date: 2026-05-06
type: domain
tags: [vmauth, nginx, reverse-proxy, victoriametrics, authentication]
---

# vmauth vs Nginx：Reverse Proxy 比較

## Nginx（基本 Reverse Proxy）

```
client request → nginx → upstream
```

- 只看 **path** 決定轉發目標
- Auth 需自己實作（`auth_basic` 或 Lua 模組）
- 多 backend load balance 用 `upstream` block

## vmauth（帶認證 + 多 backend 路由）

```
client request → vmauth
                   ↓ 1. 檢查 bearer_token（識別是誰）
                   ↓ 2. 比對 src_paths（這 user 准走這 path 嗎）
                   ↓ 3. 配對到 url_prefix（轉發哪個 backend）
                   ↓ 4. 把原 path 接在 url_prefix 後面
→ upstream
```

- token → 路由的核心邏輯：不同 token 可以打不同 backend
- 自動 retry / load balance：`url_prefix` 可以是 list
- 適合 VictoriaMetrics 多租戶 / 多 region 場景

## 關鍵差異

| 項目 | Nginx | vmauth |
|---|---|---|
| Auth 機制 | 需自行實作 | 內建 bearer_token 驗證 |
| 路由依據 | server_name / location | token + src_paths |
| Load balance | upstream block | url_prefix list（自動 retry）|
| 適用場景 | 通用 reverse proxy | VM 生態系多 backend 路由 |
