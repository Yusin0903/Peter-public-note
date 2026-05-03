---
sidebar_position: 12
---

# Thanos 架構介紹

> Thanos 是 Prometheus 的水平擴展層，不替換 Prometheus，而是在它上面加元件。
> 核心思想：把 Prometheus 的短期資料（熱資料）和 S3 的長期資料（冷資料）統一成一個查詢界面。

---

## 為什麼需要 Thanos

Prometheus 單節點的限制：

| 問題 | 說明 |
|------|------|
| 單點故障 | 一個 Prometheus 掛掉就沒有資料 |
| 垂直擴展上限 | RAM 放不下超過約 100 萬個 active series |
| 資料保留有限 | EBS 成本隨保留期線性增長；90 天就很貴 |
| 無跨實例查詢 | 多個 Region 的 Prometheus 相互獨立，查詢無法跨越 |

Thanos 解決：高可用（多個 Prometheus 互備）+ 長期保留（S3）+ 統一查詢（Query 層聚合）。

---

## 核心元件

### Thanos Sidecar

```
Prometheus Pod:
┌────────────────────────────────┐
│  container: prometheus          │
│  container: thanos-sidecar     │
└────────────────────────────────┘
```

**職責：**
- 暴露 gRPC Store API — 讓 Thanos Query 可以來取資料
- 定期把 Prometheus 完成的 TSDB block（2 小時為一個 block）上傳到 S3
- 充當「最近 2 小時資料」的查詢端點（直接從 Prometheus TSDB 讀）


### Thanos Query

**職責：**
- 提供統一的 PromQL API（Grafana 連這裡，不連 Prometheus）
- 向多個「Store API endpoint」發送查詢，合併結果
- 自動去重：同一個時間序列若來自多個 Prometheus（HA 對），保留一份

```
Thanos Query:
  收到 Grafana 的 PromQL 請求
      │
      ├──▶ Sidecar (Region A) — 最近 2 小時
      ├──▶ Sidecar (Region B) — 最近 2 小時
      ├──▶ Sidecar (Region C) — 最近 2 小時
      └──▶ Store Gateway — 超過 2 小時的歷史資料（從 S3 讀）
      
      合併結果後回傳給 Grafana
```


### Thanos Store Gateway

**職責：**
- 把 S3 裡的 TSDB block 變成 gRPC Store API
- Thanos Query 透過它查詢歷史資料
- 有 bucket cache — 常查的時間範圍在記憶體裡緩存

```
S3 bucket:
  blocks/
    ├── 01GXXXXXX/   ← 2 小時的 block，已壓縮
    ├── 01GYYYYYY/
    └── ...

Store Gateway 把這些 block 提供成可查詢的 API
（不需要把整個 block 下載下來才能查詢，支援稀疏讀取）
```

### Thanos Compactor

**職責：**
- 定期把 S3 裡的小 block 合併成大 block（降低 S3 API 費用和查詢時的讀取量）
- 執行 downsampling：raw → 5min 解析度（40 天後）；5min → 1h 解析度（5min 資料累積 10 天後）
- **全域唯一，不建議多個同時跑** — 針對相同 block range 的兩個 Compactor 會造成資料損毀（新版支援 tenant 分片，但需明確設定）

```
S3 原始（很多小 block）：
  [2h][2h][2h][2h][2h][2h][2h][2h][2h][2h][2h][2h]
  
Compact 後（大 block，節省 S3 API 費用）：
  [2h][2h]  →  [24h]
  [24h][24h][24h][24h][24h][24h][24h]  →  [1w]
  
Downsampling（超過 40 天，5min 解析度）：
  原始 15s scrape → 5min 平均
```

### Thanos Query Frontend（可選）

**職責：**
- 在 Thanos Query 前面加快取層（Memcached 或 Redis）
- 把長時間範圍的查詢拆成多個短範圍查詢並行
- 降低 Thanos Query 的 RAM 壓力

---

## 完整資料流

### 寫入路徑（Sidecar 模式）

```
Prometheus（每個 Region）:
  1. 照常 scrape targets 每 15s
  2. 資料存入本地 TSDB（2 小時一個 block，WAL 緩衝）
  3. Block 完成後，Sidecar 自動上傳到 S3：
     PUT s3://thanos-blocks/01GXXXXXX/chunks/000001
     PUT s3://thanos-blocks/01GXXXXXX/meta.json
     PUT s3://thanos-blocks/01GXXXXXX/index
```

### 查詢路徑

```
Grafana  ──PromQL──▶  Thanos Query Frontend（快取 + 拆分）
                               │
                    Thanos Query（fan-out 聚合）
                    │                    │
              Sidecar gRPC          Store Gateway gRPC
         （最近 2 小時，              （歷史資料，
          直讀 Prometheus TSDB）      從 S3 讀 block）
```

### Receive 模式（push-based 替代）

```
每個 Region Prometheus:
  remote_write ──▶  Thanos Receive（hashring 分片）
                         │
                    local TSDB + 上傳 S3
                         │
             Thanos Query + Store Gateway（同 Sidecar 模式）
```

Receive 模式讓 Prometheus 不需要加 Sidecar container，但 central 端的 Receive 元件更複雜（需要 hashring 設定來做 sharding）。

---

## 高可用設計

### Prometheus HA 對

```
Region A:
  Prometheus-0 ──Sidecar──▶ S3（上傳 block）
  Prometheus-1 ──Sidecar──▶ S3（上傳相同 block）
  
兩個 Prometheus 抓一樣的 targets → S3 裡有重複的 block
Thanos Query deduplication（必要設定）：
  - 設定 --query.replica-label=prometheus_replica
  - Query 自動識別 "prometheus_replica" 不同但其他 label 相同的 series，保留一份
  - ⚠️ 若沒有設定此 flag，兩個 Prometheus 的資料都會出現在查詢結果，數值翻倍
```

### Store Gateway HA

```
Store Gateway × 2：
  兩個都指向同一個 S3 bucket
  Thanos Query 向兩個都發查詢，取最快回來的那份
  任一個掛掉，查詢繼續正常
```

---

## 元件資源需求（參考規模：~5M active series）

| 元件 | CPU | RAM | 備註 |
|------|-----|-----|------|
| Thanos Sidecar | 0.1-0.5 vCPU | 128-512Mi | 跑在 Prometheus pod 旁，輕量 |
| Thanos Query | 1-4 vCPU | 2-8Gi | 隨同時查詢數增加 |
| Thanos Query Frontend | 0.5-1 vCPU | 512Mi-2Gi | 快取 reduce Query 負載 |
| Thanos Store Gateway | 1-2 vCPU | 2-4Gi | 有 bucket cache 時 RAM 可能更高 |
| Thanos Compactor | 1-2 vCPU | 2-4Gi | 壓縮時 RAM 使用量大 |

---

## Thanos 適合的場景

| 場景 | 說明 |
|------|------|
| 資料保留超過 3 年 | S3 的成本遠低於 EBS 長期保留 |
| 需要 downsampling | 老資料降採樣節省儲存和查詢時間 |
| 多個 Prometheus 跑相同 targets（HA）| Query 層自動 dedup，不需手動處理 |
| 已有 S3 大量使用經驗 | 依賴不是負擔 |
| Prometheus 生態已深度整合 | 不想碰 TSDB 底層，只加一層擴展 |
