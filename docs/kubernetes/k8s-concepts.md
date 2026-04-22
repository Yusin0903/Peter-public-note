---
sidebar_position: 1
---

# Kubernetes 核心概念筆記

## 請求進入 Pod 的三層架構

```
外部使用者
    │
    ▼
┌──────────┐
│  Ingress │  L7 路由規則（/api/* → Service A, /dashboard/* → Service B）
└──────────┘
    │
    ▼
┌──────────┐
│  Service │  穩定的內部入口，用 label selector 找到 Pod 做 load balancing
└──────────┘
    │
    ▼
┌──────────┐
│   Pod    │  實際跑程式的容器
└──────────┘
```

---

## Ingress

- **本質**：L7 路由規則表，定義「什麼 host/path → 哪個 Service」
- **不是 endpoint**，真正開出 endpoint 的是 Ingress Controller
- 需要搭配 Ingress Controller 才能運作（AWS ALB Controller, NGINX 等）

### pathType 三種

| pathType | 說明 |
|----------|------|
| `Exact` | 完全一致（`/foo` 只匹配 `/foo`） |
| `Prefix` | 前綴匹配，以 `/` 為邊界 |
| `ImplementationSpecific` | 交給 Ingress Controller 決定（可支援 wildcard `*`） |

### Ingress NGINX 退役（2026/03）

- 退役的是 **Ingress NGINX Controller**，不是 Ingress API 本身
- Ingress API 是 GA，frozen 但不會 deprecate
- 官方推薦遷移到 **Gateway API**（v1.5, 2026/02 發布）
- AWS ALB Controller 不受影響（AWS 自己維護）

---

## Service

### 三種 type

| type | 對外暴露方式 | 用途 |
|------|------------|------|
| **ClusterIP** | 只有 cluster 內部可連（預設） | 內部服務互相呼叫 |
| **NodePort** | 每個 Node 開固定 port（30000-32767） | 搭配 ALB 等外部 LB |
| **LoadBalancer** | 自動建雲端 LB | 正式對外服務 |

### port vs targetPort

```yaml
ports:
  - port: 80          # Service 對外暴露的 port（cluster 內用這個）
    targetPort: 8081   # Pod 實際 listen 的 port（= containerPort）
```

### 內部 DNS 解析

K8s 自動為每個 Service 建立 DNS record，Pod 之間可以直接用名稱互連：

```bash
# 同 namespace → 直接用 Service 名稱
curl http://my-service:80

# 跨 namespace → 加 namespace 名稱
curl http://my-service.other-namespace:80

# 完整 FQDN（較少用，但最明確）
curl http://my-service.other-namespace.svc.cluster.local:80
```

---

## Workload 類型完整一覽

| 類型 | 核心特性 | 典型用途 |
|------|---------|---------|
| **Deployment** | 無狀態，replicas 自由調整 | API server、web app、proxy、reverse proxy |
| **StatefulSet** | 有狀態，固定名字 + 固定 PVC | 資料庫、時序資料庫（TSDB）、Grafana |
| **DaemonSet** | 每台 node 跑一個，node 增加自動擴展 | log collector、node metrics exporter |
| **Job** | 跑完（exit 0）就停止，不重啟 | DB migration、一次性腳本 |
| **CronJob** | 定時產生 Job | 定時備份、定時清理、定期報表 |
| **ReplicaSet** | 幾乎不直接用 | Deployment 底層自動建立，管 Pod 數量 |

### 生命週期

```
Deployment / StatefulSet / DaemonSet → 一直跑，掛了自動重啟
Job                                  → 跑完就停，不重啟
CronJob                              → 定時產生 Job
```

### StatefulSet vs Deployment

```
Deployment（API server、proxy）：
  Pod-abc123 重啟 → 可能變成 Pod-xyz789（名字不固定）
  掛在哪台 node 無所謂，沒有自己的硬碟

StatefulSet（資料庫、TSDB）：
  db-0 重啟 → 還是 db-0（名字固定）
  有固定的 PVC，db-0 的 /data 永遠掛同一顆硬碟
```

**選擇原則**：需要持久化資料或固定 identity → StatefulSet，其他 → Deployment。

### DaemonSet

```
# cluster 有 3 台 node

Deployment replicas=2：           DaemonSet：
  node-1: [api-server]             node-1: [log-collector]
  node-2: [api-server]             node-2: [log-collector]
  node-3: (空的)                   node-3: [log-collector]

新 node-4 加入：
  node-4: (不會自動加)              node-4: [log-collector] ← 自動！
```

適合「需要在每台機器上收集資料」的 agent，例如 log collector、node metrics exporter。

### ReplicaSet — 為什麼不直接用

```
你建 Deployment
  → Deployment 自動建 ReplicaSet
  → ReplicaSet 管 Pod 數量

直接建 ReplicaSet 缺少 rolling update、rollback 功能
實務上只用 Deployment，不直接碰 ReplicaSet
```

---

## CronJob

```yaml
schedule: "10 */1 * * *"        # 每小時第 10 分鐘執行
concurrencyPolicy: Forbid       # 上一次沒跑完不啟動新的
successfulJobsHistoryLimit: 1   # 只保留 1 個成功紀錄
backoffLimit: 3                 # 失敗最多重試 3 次
```

---

## Pod Log 查詢

```bash
# 單一 Pod
kubectl logs -f <pod-name>

# 用 label 看所有 replica 的 log
kubectl logs -f -l app=my-app

# 所有 Pod 的 log 一起 grep
kubectl logs -l app=my-app --all-containers | grep "keyword"
```

多 replica 時每個 Pod 只有部分流量的 log，要查特定 request 建議用集中式 log（如 CloudWatch Logs Insights、Loki）或 trace ID。

---

## 容器服務比較（以 AWS 為例）

| | EKS (Kubernetes) | Lambda |
|---|---|---|
| 運作方式 | 你管 Pod，持續運行 | 事件觸發，跑完消失 |
| 適合 | 長時間服務、複雜架構 | 短任務（≤15 min）、事件驅動 |
| 費用 | Node 開著就收錢 | 只收執行時間 |
| 管理成本 | 要管 node、scaling、部署 | 幾乎不用管 |

EKS = AWS 代管的 Kubernetes，幫你管 control plane，你只管 worker node 和部署。

---

## K8s Storage：StorageClass / PVC / PV

### 三層關係

```
StorageClass（規格表）
  → 定義「怎麼建磁碟」（type、provisioner、回收策略）
  → 整個 cluster 只有幾個，所有 pod 共用

PVC — PersistentVolumeClaim（申請單）
  → Pod 說「我要一顆 500Gi 的 gp3 磁碟」
  → 每個需要磁碟的 pod 各自一張

PV — PersistentVolume（實際的磁碟）
  → K8s 收到 PVC 後自動建立
  → 對應到雲端的真實磁碟（AWS EBS、GCP PD 等）
```

### 類比

```
StorageClass = 餐廳菜單（定義有哪些磁碟規格可選）
PVC = 點餐單（客人：我要 gp3 套餐，大份 500Gi）
PV = 廚房做出來的那道菜（實際的 volume）
```

### StorageClass 範例

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com        # 誰建磁碟（AWS EBS CSI Driver）
parameters:
  type: gp3                          # 磁碟類型
  fsType: ext4                       # 檔案系統
volumeBindingMode: WaitForFirstConsumer  # 等 pod 排程後才建（確保同 AZ）
allowVolumeExpansion: true           # 之後可以擴大，不需要重建
reclaimPolicy: Retain                # pod 刪除後 volume 保留
```

### PVC 範例

```yaml
volumeClaimTemplate:
  spec:
    storageClassName: gp3        # 用哪個 StorageClass
    resources:
      requests:
        storage: 500Gi           # 要多大
```

### 完整建立流程

```
1. StorageClass "gp3" 已建好（定義磁碟規格）

2. StatefulSet 宣告 PVC：storageClassName: gp3, storage: 500Gi

3. K8s scheduler 把 pod 排到 node-1（us-west-2a）

4. WaitForFirstConsumer → 現在才開始建 volume
   K8s 看 PVC → 找到 StorageClass "gp3" → 呼叫 provisioner
   → 雲端 API 建立 500Gi 磁碟（同 AZ）

5. K8s 建立 PV，綁定 PVC ↔ PV ↔ 實際磁碟

6. 磁碟掛載到 node → pod 可以讀寫
```

### 生命週期

| 事件 | PVC | PV | 實際磁碟 |
|---|---|---|---|
| Pod 建立 | 建立 | 自動建立 | 雲端自動建 |
| Pod 重啟 | 不變 | 不變 | 不變（資料保留） |
| Pod 搬到其他 node（同 AZ） | 不變 | 不變 | detach + reattach |
| Pod 刪除 | 刪除 | 看 reclaimPolicy | Retain → 保留 / Delete → 刪除 |

### reclaimPolicy

```
Retain  → pod 刪了磁碟還在，資料保留（適合資料庫、TSDB）
Delete  → pod 刪了磁碟也自動刪（適合暫時性 cache）
```

### volumeBindingMode

```
Immediate           → PVC 建立時立刻建磁碟
                       問題：可能跟 pod 不同 AZ → 掛載失敗
WaitForFirstConsumer → 等 pod 排程後才建
                       確保磁碟跟 pod 在同一個 AZ ✓
```

### 雲端磁碟 vs Node 本地磁碟

| | 雲端磁碟（EBS / PD） | Node 本地磁碟 |
|---|---|---|
| 本質 | 獨立的網路磁碟 | Node 自帶的 root disk |
| Node 刪了 | 磁碟還在 | 資料消失 |
| Pod 搬家 | 可以重新掛載到其他 Node | 不行 |
| 適合 | 需要持久化的資料 | 暫時性 cache |

### IOPS vs Throughput

```
IOPS = 每秒幾次讀寫操作（Input/Output Operations Per Second）
  → 影響：大量小型寫入（例如即時 metrics 寫入，每筆很小但頻率高）
  → 類比：圖書館員每秒能拿幾本書

Throughput = 每秒搬多少資料量（MiB/s）
  → 影響：大量連續讀取（例如查詢歷史資料，一次掃描幾 GB）
  → 類比：圖書館員每秒能搬多少公斤的書
```

### AWS EBS gp2 vs gp3（常見選擇）

| | gp2 | gp3 |
|---|---|---|
| 價格/GiB/月 | $0.10 | $0.08（便宜 20%） |
| IOPS | 跟容量綁定（3 IOPS/GiB） | 固定 3000 基礎（不管容量） |
| Throughput | 最高 250 MiB/s | 125 MiB/s 基礎，可升到 1000 MiB/s |
| IOPS 可調 | 不行，想加 IOPS 就要加容量 | 可以獨立調整，最高 16000 |

gp3 幾乎在所有場景都比 gp2 好。AWS 官方建議新 workload 用 gp3。

**gp2 的痛點**：想要 3000 IOPS 就必須開 1000GiB 的 volume（浪費空間和錢）。gp3 不管多小的 volume 都直接給 3000 IOPS。
