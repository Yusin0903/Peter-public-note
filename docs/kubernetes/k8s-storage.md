---
sidebar_position: 6
---

# K8s Storage：StorageClass / PVC / PV

## 三層關係

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

---

## StorageClass 範例

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

---

## PVC 範例

```yaml
volumeClaimTemplate:
  spec:
    storageClassName: gp3        # 用哪個 StorageClass
    resources:
      requests:
        storage: 500Gi           # 要多大
```

---

## 完整建立流程

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

---

## 生命週期

| 事件 | PVC | PV | 實際磁碟 |
|---|---|---|---|
| Pod 建立 | 建立 | 自動建立 | 雲端自動建 |
| Pod 重啟 | 不變 | 不變 | 不變（資料保留） |
| Pod 搬到其他 node（同 AZ） | 不變 | 不變 | detach + reattach |
| Pod 刪除 | 刪除 | 看 reclaimPolicy | Retain → 保留 / Delete → 刪除 |

---

## reclaimPolicy

```
Retain  → pod 刪了磁碟還在，資料保留（適合資料庫、TSDB）
Delete  → pod 刪了磁碟也自動刪（適合暫時性 cache）
```

---

## volumeBindingMode

```
Immediate           → PVC 建立時立刻建磁碟
                       問題：可能跟 pod 不同 AZ → 掛載失敗
WaitForFirstConsumer → 等 pod 排程後才建
                       確保磁碟跟 pod 在同一個 AZ ✓
```

> **為什麼 AZ 很重要**：AWS EBS 磁碟是 AZ 級別的資源，`us-west-2a` 建的磁碟無法掛到 `us-west-2b` 的機器上。

---

## 雲端磁碟 vs Node 本地磁碟

| | 雲端磁碟（EBS / PD） | Node 本地磁碟 |
|---|---|---|
| 本質 | 獨立的網路磁碟 | Node 自帶的 root disk |
| Node 刪了 | 磁碟還在 | 資料消失 |
| Pod 搬家 | 可以重新掛載到其他 Node | 不行 |
| 適合 | 需要持久化的資料 | 暫時性 cache |

---

## emptyDir — Pod 內容器共享的臨時 Volume

`emptyDir` 是 Pod 級別的臨時 Volume：**Pod 存在時存在，Pod 刪了就消失**。最重要的用途是讓同一個 Pod 裡的多個容器共享資料。

```yaml
spec:
  containers:
    - name: inference-server
      volumeMounts:
        - name: shared-output
          mountPath: /output

    - name: result-uploader       # sidecar
      volumeMounts:
        - name: shared-output
          mountPath: /output      # 同一個 volume，可以讀 inference 結果

  volumes:
    - name: shared-output
      emptyDir: {}                # 預設用磁碟空間

    - name: shm
      emptyDir:
        medium: Memory            # 使用 RAM（tmpfs），適合 /dev/shm
        sizeLimit: 8Gi            # 限制大小，防止 OOM
```

**三種 emptyDir 用途**：

| 用途 | 設定 | 說明 |
|---|---|---|
| Sidecar 共享資料 | `emptyDir: {}` | init container 下載的 model，主容器使用 |
| PyTorch shared memory | `medium: Memory` | `/dev/shm`，DataLoader 多 worker 需要 |
| 快取計算結果 | `emptyDir: {}` | 同一個 Pod 多次請求複用的暫存結果 |

**inference system 的典型場景**：
```yaml
# init container 從 S3 下載 model → 寫到 emptyDir
# 主容器從 emptyDir 載入 model（不用每次從 S3 拉）
volumes:
  - name: model-cache
    emptyDir:
      sizeLimit: 20Gi    # 限制 20GB，防止把 node 磁碟塞爆
```

---

## ConfigMap as Volume Mount

ConfigMap 不只可以當環境變數，還可以掛成檔案。適合把設定檔（YAML、JSON、.env）注入到容器裡。

```yaml
# 建立 ConfigMap（存設定檔內容）
apiVersion: v1
kind: ConfigMap
metadata:
  name: inference-config
data:
  config.yaml: |
    model:
      name: llm-7b
      max_tokens: 2048
      temperature: 0.7
    server:
      workers: 4
      timeout: 30
  logging.conf: |
    [loggers]
    keys=root
    [handlers]
    keys=consoleHandler
```

```yaml
# 在 Deployment 裡掛成檔案
spec:
  containers:
    - name: inference-server
      volumeMounts:
        - name: config-volume
          mountPath: /app/config    # ConfigMap 的 key 變成這個資料夾裡的檔案名稱
          readOnly: true

  volumes:
    - name: config-volume
      configMap:
        name: inference-config
        # 結果：
        # /app/config/config.yaml   ← ConfigMap 的 config.yaml key
        # /app/config/logging.conf  ← ConfigMap 的 logging.conf key
```

**ConfigMap vs Secret vs 環境變數選擇**：

| 資料類型 | 推薦方式 |
|---|---|
| 非機密設定（model 參數、timeout） | ConfigMap（環境變數或 volume） |
| 機密資料（API key、DB 密碼） | Secret（volume 掛載，避免環境變數洩漏） |
| 需要程式動態讀取（不重啟就能更新） | ConfigMap/Secret as volume（K8s 會自動更新檔案） |
| 簡單的單一值 | 環境變數 |

---

## IOPS vs Throughput

```
IOPS = 每秒幾次讀寫操作（Input/Output Operations Per Second）
  → 影響：大量小型寫入（例如即時 metrics 寫入，每筆很小但頻率高）
  → 類比：圖書館員每秒能拿幾本書

Throughput = 每秒搬多少資料量（MiB/s）
  → 影響：大量連續讀取（例如查詢歷史資料，一次掃描幾 GB）
  → 類比：圖書館員每秒能搬多少公斤的書
```

---

## AWS EBS gp2 vs gp3（常見選擇）

| | gp2 | gp3 |
|---|---|---|
| 價格/GiB/月 | $0.10 | $0.08（便宜 20%） |
| IOPS | 跟容量綁定（3 IOPS/GiB） | 固定 3000 基礎（不管容量） |
| Throughput | 最高 250 MiB/s | 125 MiB/s 基礎，可升到 1000 MiB/s |
| IOPS 可調 | 不行，想加 IOPS 就要加容量 | 可以獨立調整，最高 16000 |

gp3 幾乎在所有場景都比 gp2 好。AWS 官方建議新 workload 用 gp3。

**gp2 的痛點**：想要 3000 IOPS 就必須開 1000GiB 的 volume（浪費空間和錢）。gp3 不管多小的 volume 都直接給 3000 IOPS。
