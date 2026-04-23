---
sidebar_position: 4
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

> **Python 類比**：
> ```python
> # StorageClass = 定義磁碟規格的 dataclass
> @dataclass
> class StorageClass:
>     name: str = "gp3"
>     provisioner: str = "ebs.csi.aws.com"
>     iops: int = 3000
>
> # PVC = 你的 code 呼叫 open() 申請檔案資源
> # pvc = open("/data/myfile", "w")  # 申請磁碟資源
>
> # PV = OS 實際分配給你的 file descriptor
> # 你不直接操作 fd，OS（K8s）幫你處理
> ```
>
> 更直白的比喻：
> - `StorageClass` = 餐廳菜單（定義有哪些磁碟規格可選）
> - `PVC` = 點餐單（客人：我要 gp3 套餐，大份 500Gi）
> - `PV` = 廚房做出來的那道菜（實際的 volume）

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

```python
# Python 類比：整個流程就像 Python 的 context manager
class StorageProvisioner:
    def __enter__(self):
        # 1. 確認 StorageClass 規格
        # 2. 等 Pod 排程後才真正建立（WaitForFirstConsumer）
        self.volume = aws.create_ebs_volume(size="500Gi", type="gp3")
        self.volume.attach(node=scheduler.current_node)
        return self.volume

    def __exit__(self, *args):
        if self.reclaim_policy == "Retain":
            pass       # 保留磁碟（reclaimPolicy: Retain）
        else:
            self.volume.delete()   # 刪除（reclaimPolicy: Delete）

with StorageProvisioner() as vol:
    # Pod 跑的時候磁碟一直掛著
    write_data(vol, "/data/metrics.db")
# Pod 結束後依 reclaimPolicy 決定磁碟命運
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

```python
# Python 類比：
# Retain  = tempfile.NamedTemporaryFile(delete=False)  # 自己管清理
# Delete  = tempfile.NamedTemporaryFile(delete=True)   # 自動清掉
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

```python
# Python 類比：
# 雲端磁碟（EBS） = 外接 USB 硬碟，拔掉再插到別台電腦資料還在
# Node 本地磁碟  = 電腦的 /tmp，重開機就沒了
```

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

```python
# Python inference system 的實際影響：
# 高 IOPS 場景：每次 inference 結果都即時寫入 DB（小資料、高頻率）
#   → 需要高 IOPS，選 gp3 並調高 IOPS 設定

# 高 Throughput 場景：batch inference 後一次讀取幾 GB 的結果檔案
#   → 需要高 Throughput，選 gp3 並調高 throughput 設定

import time

# 模擬 IOPS 瓶頸：1000 次小寫入
for i in range(1000):
    with open(f"/data/result_{i}.json", "w") as f:
        f.write('{"score": 0.95}')  # 每筆很小，但次數多 → 看 IOPS

# 模擬 Throughput 瓶頸：一次讀取大檔
with open("/data/embeddings.npy", "rb") as f:
    data = f.read()  # 一次讀幾 GB → 看 Throughput
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
