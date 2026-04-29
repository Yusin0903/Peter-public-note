---
sidebar_position: 11
---

# Thanos vs VictoriaMetrics

> 兩者都解決「Prometheus 不能水平擴展」的問題，但設計哲學不同。
> 以下以 10 個 AWS Region、~75K samples/sec、~4.9M active series 的規模為例進行比較。

---

## 一句話差異

| | Thanos | VictoriaMetrics |
|--|--------|----------------|
| 設計哲學 | Prometheus 的擴充層（sidecars + object storage） | 從頭設計的 TSDB，相容 Prometheus API |
| 長期儲存 | S3 / GCS / Azure Blob（必須） | EBS 或本地磁碟（S3 可選） |
| 遷移方式 | 官方推薦：每個 Region 加 Sidecar container | 推薦：Prometheus remote_write（只改 config） |
| RAM 效率 | 與 Prometheus 相當 | 7-10x 低於 Prometheus（相同基數） |
| PromQL 相容性 | 完整（本身就是 Prometheus 生態） | 99% 相容 + MetricsQL 擴充 |

---

## 架構模式比較

### Thanos Sidecar 模式（官方推薦）

```
每個 Region EKS Pod：
┌────────────────────────────────────┐
│ container: prometheus (既有)        │
│ container: thanos-sidecar (新增)   │ ← 每個 Region manifest 都要改
└────────────────────────────────────┘
         │ gRPC Store API (pull，非 push)
         ▼
Central：
  Thanos Query ──▶ Thanos Store Gateway ──▶ S3 (long-term)
                ──▶ Sidecar gRPC (recent data)
  Thanos Compactor（定期壓縮 S3 blocks）
```

**資料流：**
- 最近 2 小時的資料：Query 直接向各 Region 的 Sidecar 拉（gRPC）
- 超過 2 小時的資料：Sidecar 上傳到 S3，Query 透過 Store Gateway 讀取
- Compactor：定期把 S3 裡的小 block 合併壓縮，降低儲存和查詢成本

### Thanos Receive 模式（較新）

```
每個 Region：
  Prometheus ──remote_write──▶ Thanos Receive (central)
                                      │
                              Thanos Query Frontend
                              Thanos Store Gateway
                              Thanos Compactor
                              S3
```

**與 VictoriaMetrics 的架構類似，但元件更多。**

### VictoriaMetrics Cluster 模式

```
每個 Region（只改 prometheus.yml）：
  Prometheus ──remote_write──▶ vmauth (TLS + bearer token)
                                    │
                               vminsert ×2 (stateless)
                                    │
                              vmstorage ×3 (replicationFactor=2)
                                    │
                              vmselect ×2 (stateless)
                                    │
                           Central Grafana / vmalert
```

---

## 元件數量比較

| 元件職責 | Thanos Sidecar | Thanos Receive | VictoriaMetrics |
|---------|:--------------:|:--------------:|:---------------:|
| 接收寫入 | Sidecar（各 Region） | Receive | vminsert |
| 儲存資料 | Prometheus TSDB + S3 | Receive + S3 | vmstorage + EBS |
| 查詢路由 | Query + Query Frontend | Query + Query Frontend | vmselect |
| 長期壓縮 | Compactor | Compactor | 內建（vmstorage） |
| 認證/路由 | 需自架 reverse proxy | 需自架 reverse proxy | vmauth（內建） |
| **Central 元件數** | **4-5** | **5** | **3-4**（含 vmauth） |
| **外部依賴** | S3 必須 | S3 必須 | 無（EBS 即可） |

---

## 成本比較（以 10 Region、~75K samples/sec 為例）

| 項目 | Thanos Receive | VictoriaMetrics | 差距 |
|------|:-------------:|:---------------:|:----:|
| EC2（Query、Store、Compactor） | ~$350 | ~$542 | Thanos 便宜 |
| S3 儲存（必要 vs 可選） | ~$12-20 | ~$0 | Thanos 多 $12-20 |
| EBS 儲存 | 較少（靠 S3） | ~$120（3× 500GB） | VM 多 |
| **合計** | **~$427** | **~$555** | VM 貴 ~$128/月 |

> $128/月 ≈ $1,536/年。換來的是：更少元件、更低 RAM 使用、無 S3 依賴、更低遷移風險。

---

## RAM 效率對比

在 ~4.9M active series 的 central TSDB 場景：

| 方案 | 預估 Central RAM 需求 |
|------|:--------------------:|
| Thanos Store Gateway | 2-4Gi per node |
| Thanos Query | 2-8Gi（取決於查詢量） |
| VictoriaMetrics vmstorage | 8-16Gi **per node**（3 nodes，replicationFactor=2 實際存 ~9.8M series） |
| VictoriaMetrics vmselect | 4-8Gi per node |

雖然 VM 的 vmstorage 需要更多 RAM，但效率優勢在**各 Region 端**更明顯：
- 高基數 Region 的 Prometheus 在記憶體限制下已接近 OOM 邊緣（以 1.6M series 為例）
- 換成 VMAgent（無本地 TSDB，純 scrape + remote_write）可降到 ~500Mi，RAM 減少幅度遠超 7-10x
- 注意：7-10x 是 VM TSDB vs Prometheus TSDB 的比較；VMAgent 完全移除本地 TSDB，節省更多

---

## 遷移難度比較

### Thanos Sidecar 模式
```
要做的事（每個 Region）：
  1. 修改 Helm values 加 thanos-sidecar container
  2. 加 ObjectStore secret（S3 credentials）
  3. Rolling restart Prometheus pod
  4. 等 Sidecar 上傳初始 block 到 S3（可能 2+ 小時）
  5. 驗證 Thanos Query 能讀到這個 Region

風險：10 個 Region × 上述步驟 = 10 次 manifest 修改 + 10 次 rollout
```

### VictoriaMetrics remote_write
```
要做的事（每個 Region）：
  1. 在 prometheus.yml 加 remote_write block（3-5 行）
  2. reload Prometheus config（無需 restart）
  3. 驗證 VMUI 看到新 Region 的資料

風險：config reload 失敗最多讓 remote_write 不動，不影響本地 scraping
```

---

## 什麼情況下該選 Thanos

| 情況 | 為何偏向 Thanos |
|------|----------------|
| 資料保留超過 ~3 年 | Thanos 靠 S3 可無限保留；VM EBS 方案有成本上限 |
| 需要 multi-tenancy | Thanos Receive 有 tenant 隔離設計 |
| 需要跨 TSDB deduplication | 多個 Prometheus 同時抓同一個 target，Thanos Query 可去重 |
| 已有大量 S3 預算和經驗 | S3 依賴不是問題，反而是既有基礎設施 |
| 團隊有 Thanos 專責人員 | 運維複雜度有人承擔 |

---

## 不選 Thanos 的原因整理

1. **Sidecar 模式違背「零中斷遷移」策略** — 10 個 Region 全部要改 manifest + rollout
2. **Receive 模式元件複雜** — 雖已 production-ready（Thanos v0.32+），但 hashring 設定複雜，社群案例仍少於 Sidecar 模式
3. **S3 是額外依賴** — 需要管理 bucket、lifecycle policy、IAM policy
4. **元件多 = 故障點多** — 5 個 central 元件 vs VM 的 3 個
5. **$128/月 的節省不值得** — 換來明顯更高的運維負擔
6. **RAM 劣勢在 Region 端明顯** — 高基數 Region 已在 OOM 邊緣，VM Agent 可省 7-10x RAM
