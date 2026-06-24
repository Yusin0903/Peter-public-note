---
sidebar_position: 22
---
<!-- generated from ~/peter-llm-wiki; edit source there, not here -->

# EKS Node Group 改 Subnet / AZ 的踩坑全紀錄

這篇講「把一個既有的 EKS managed node group 從跨 3 AZ 改成跨 2 AZ」會踩到的坑。雖然案例是改 Thanos 監控的 node group，但這裡面的東西是 **AWS/EKS 通用知識**——之後改任何「既有環境的 node group 拓樸」或「動到 stateful workload 的 AZ」都會遇到。

核心知識點：EBS 綁 AZ、StorageClass 的 binding mode、改 subnet 會整組重建 node group、撞 409 怎麼解。

## 背景：為什麼 stateful workload 改 AZ 這麼麻煩

有個專屬 node group 跑 stateful 服務（用 EBS 硬碟），本來 3 台、每個 AZ 一台（1a/1b/1c）。想省一台改成 2 台，結果 pod 卡住起不來，報 `volume node affinity conflict`。

**根本原因：EBS 硬碟綁死在它建立時的那個 AZ，不能跨 AZ 掛。**

- PV（硬碟）散在三個 AZ。
- desired=2 時，ASG 自己決定開哪兩個 AZ 的 node，它不知道你的 PV 在哪。
- 只要它沒在某個有 PV 的 AZ 開 node，那個 PV 的 pod 就找不到地方排 → Pending。

這就是為什麼當初被迫設 desired=3——每個 AZ 都有 node，PV 一定有地方去。但想降回 2 就卡。

## 要 desired=2 能跑的鐵律

> 每個 stateful 副本的 PVC，一定要有「同一個 AZ」的 node 可以接它。

做法兩件事一起：

1. **Node group 只綁兩個 AZ 的 subnet**（不是全部三個）。Terraform 裡用 `slice(private_subnets, 0, 2)` 取前兩個 AZ。這樣 desired=2 一定每個 AZ 一台，不會亂挑。
2. **stateful 元件加 `topologySpreadConstraints`**，強制 2 個副本一個 AZ 一個。

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule   # 硬性：不准兩副本擠同一 AZ
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: <你的 app>
```

效果：單一 AZ 掛掉，最多只倒一半（不會全倒）。

> 小提醒：`labelSelector` 一定要對到 pod 真正的 label。不同 helm chart label 命名不一樣（有的用 `app.kubernetes.io/name`，有的用舊版 `app`/`component`）。寫錯的話 selector 匹配不到任何 pod，topologySpread 就**靜默失效**（不會報錯），等於沒設。一定要 `kubectl get pod <name> --show-labels` 確認過。

## 坑 1：StorageClass 缺了，clean apply 才會炸

**StorageClass（SC）是什麼？** 就是「怎麼自動生一塊硬碟」的模板。pod 要硬碟時，照這個模板去 AWS 開 EBS。

我們的設定寫死要用一個叫 `gp3` 的 SC。線上跑得好好的，但全新環境部署時所有 stateful 硬碟都生不出來 → 全 Pending。

**為什麼？** 因為這個 gp3 SC 是**很久以前有人手動 `kubectl apply` 建的，從沒寫進 IaC**。用完 SC 還被刪了，但既有 PV 已經綁好所以照常跑。全新環境根本沒這個 SC。

**為什麼線上一直沒事？** 關鍵觀念：

> PV 一旦 `Bound`（綁定）之後就不再需要 SC 了——SC 只在「第一次建硬碟」那一刻用到。

所以線上重啟 pod 都正常（reuse 已綁的 PV，不碰 SC），沒人發現 SC 早就不見了。只有「從零建新硬碟」才會撞牆。**這類「靠手動撐著」的隱形依賴，clean apply 是照妖鏡。**

**修法**：把 gp3 SC 正式寫進 IaC。關鍵設定：

```yaml
provisioner: ebs.csi.aws.com            # 用新版 EBS CSI driver（不是舊版 in-tree kubernetes.io/aws-ebs）
volumeBindingMode: WaitForFirstConsumer # 命脈！見下
reclaimPolicy: Retain                   # 刪 PVC 不連硬碟一起刪，保資料
allowVolumeExpansion: true
parameters:
  type: gp3
  encrypted: "true"
```

### WaitForFirstConsumer 是多 AZ 設計的命脈

意思是：**「等 pod 排到某台 node 之後，才在那台 node 的 AZ 建硬碟」**。

如果設成 `Immediate`，硬碟會在 pod 還沒排程前就先隨機挑一個 AZ 建好 → pod 可能排到別的 AZ → 又跨 AZ 掛不上 → 回到最初的痛。

「硬碟跟著 pod 走、落在對的 AZ」就是靠這個。

### reclaimPolicy 為什麼選 Retain

`Retain` = 刪 PVC 時底層 EBS 硬碟**保留**（不刪）。代價是會留「孤兒」硬碟要手動清，但好處是手滑刪 PVC 不會瞬間蒸發資料。prod 一定要這個。

> 注意：改 SC 的 reclaimPolicy **不會影響已存在的 PV**。SC 的設定只是「之後用這個 SC 新建的 PV」的初始值；既有 PV 的 policy 早就固化在自己身上了，要改得直接 `kubectl patch pv`。

## 坑 2：改 subnet 會「整組重建」node group，還撞 409

改 node group 的 `subnet_ids`，Terraform 不是改一改，而是**砍掉整個 node group 重建**（術語：replacement，計畫裡顯示 `+/- create replacement and then destroy`）。

問題：node group 名字寫死、沒有隨機後綴（`use_name_prefix = false`）。Terraform 想「先建新的、再砍舊的」，但新舊**同名** → AWS 回 `409 ResourceInUseException` → 卡死。

**怎麼解？**

- **手動刪舊 node group**（`aws eks delete-nodegroup`），再重跑 CI。舊的不在了，建同名新的就不撞。
- 另一招：把名字改掉（加 `-2az` 之類）讓新舊不同名。但名字會永久變，且全新環境本來就不會撞（沒有舊的），所以不值得為它改名。

**關鍵：手動刪 AWS 資源後，Terraform state 還記著它。** 但重跑 CI 時 plan 階段會做 refresh，發現 AWS 上已經沒了 → 自動把計畫從「replace」改成「全新 create」→ 就不撞了。多半不用手動 `state rm`。

> 刪 node group 前務必確認**只影響目標 workload**。不同 node group 靠 `nodeSelector`（如 `role=xxx`）隔離，pod 不會跑到別的 node group。刪前可以用 `kubectl get pods -A --field-selector spec.nodeName=<node>` 反查那幾台 node 上到底跑了誰。

EKS node group 刪除本身很慢（5~15 分鐘），一直 `DELETING` 不代表卡住——它要 drain pod、終結 ASG/EC2、等 EBS detach。

## 坑 3：apply 卡在 helm timeout（其實是預期的善後點）

重跑 apply，新 node group 順利建好，但 apply 報 `context deadline exceeded` 卡在某個 helm release。

**原因**：helm `wait=true` 會等所有 pod Ready 才算成功。但有一個 pod 的舊 PV 在被移除的那個 AZ（1c），新 node group 只有 1a/1b → 它永遠排不上 → helm 等到超時。

**這不是失敗，是預期的善後點**。node group 跟設計都成功了，只差清掉舊 AZ 的殘留 PV。

**善後**（如果該服務是無狀態 cache，刪了重建零風險；有狀態的要評估）：

```bash
# 刪掉綁在舊 AZ 的 PVC，StatefulSet 會自動建新的
kubectl delete pvc <stuck-pvc> -n <ns>
kubectl delete pod <stuck-pod> -n <ns>
```

刪完後 StatefulSet 建同名新 PVC → 新 pod 排到還活著的 AZ（topologySpread 會把它推到沒被占用的那個）→ WaitForFirstConsumer 在那個 AZ 建新硬碟 → Running。

舊 PV 因為 Retain 會變 `Released` 留著，記得手動清（連 AWS 上的 EBS 一起刪，不然一直收費）。

## 最後收尾

再跑一次 CI plan，剩乾淨的小改動，例如：

- helm release `status: failed -> deployed`——上次 timeout 被標記 failed，但 pod 其實早好了，這次只是把 helm 狀態扶正，不重啟 pod。
- 一些 IAM tag / aws_auth 格式的 drift（無害）。

跑完就收斂，下次 plan 應該是 `No changes`。

## 一定要記住的觀念

1. **EBS 綁死 AZ，不能跨 AZ 掛**——所有「PV 抓不到 / volume node affinity conflict」追到底幾乎都是這個。
2. **PV 一旦 Bound 就不再需要 SC**——所以缺 SC 這種坑只在「從零建新硬碟」才爆，既有環境感覺不到。
3. **WaitForFirstConsumer** 讓硬碟跟著 pod 落到對的 AZ，是多 AZ 設計的關鍵。
4. **改 node group 的 subnet = 整組重建**，名字寫死會撞 409，要嘛手動刪舊的、要嘛改名。
5. **手動刪 AWS 資源後，Terraform plan 的 refresh 會自動同步 state**，多半不用手動 state rm。
6. **未追蹤的手動狀態是定時炸彈**——這次的 gp3 SC 就是。clean apply 是照妖鏡，會把所有「靠手動撐著」的東西照出來。
7. **topologySpread 的 labelSelector 寫錯會靜默失效**，一定要對著真實 pod label 確認。
