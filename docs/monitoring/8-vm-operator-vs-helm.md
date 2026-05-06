---
sidebar_position: 17
---

# VictoriaMetrics 部署模式：Operator vs Helm chart

VM 官方有兩種主流部署方式——**VM Operator + CRD** 跟**直接 Helm chart**。兩個 chart 都在 `victoriametrics.github.io/helm-charts`，但機制完全不同。踩過坑後整理選擇邏輯。

---

## 兩種模式總覽

```
Operator 模式：
  helm install victoria-metrics-operator   ← 裝管理員
  kubectl apply VMCluster.yaml             ← 申請單（CRD）
  Operator 看到 → 自動建 vminsert / vmselect / vmstorage 跟一堆 K8s 資源

Helm chart 模式：
  helm install victoria-metrics-cluster    ← 直接裝
  → 一次性產出 vminsert（Deployment）/ vmselect（Deployment）/ vmstorage（StatefulSet）
```

---

## 結構性差異

| 維度 | Operator | Helm chart |
|---|---|---|
| **元件數** | 6（operator pod + 5 種 CRD reconcilers）| 2-3（cluster + auth + alert chart 各自獨立 release）|
| **vmselect / vminsert 部署形式** | StatefulSet（每 replica 自己 PVC）| **Deployment（共用 PVC）** ⚠️ |
| **vmstorage 部署形式** | StatefulSet | StatefulSet（一致）|
| **VMUser / 多 token auth** | CRD（VMUser × N）| 自己組 vmauth `auth.yml` ConfigMap，靠 templatefile |
| **PrometheusRule converter** | 有（Operator 自動轉 Prometheus rule → vmalert）| 無 |
| **destroy 行為** | ❌ Helm release 跟 CRD 砍順序對不上 → PVC/Pod 變孤兒 | ✅ `helm uninstall` 直接砍乾淨 |
| **enabled=false rollback** | ❌ Operator 卡住時 toggle 沒效 | ✅ `count = 0` 即可 |
| **學習曲線** | 多一層 CRD 抽象，初學者卡 | 純標準 K8s object |

---

## 何時選 Operator

✅ 多 region 動態增刪 token（10 region 各自 VMUser，`for_each` 在 Terraform 自動展開）
✅ 計畫用 PrometheusRule CRD 寫 alerting rule
✅ 有 VM 進階功能需求（VMRule、VMServiceScrape、VMPodScrape、VMAlertmanagerConfig）
✅ 期望 GitOps + Operator 自動 reconcile drift

---

## 何時選 Helm chart

✅ 單純需求（中央 cluster、固定幾個 component）
✅ 用 `terraform destroy/apply` 做 lifecycle 管理（不要孤兒）
✅ 想用 standard Helm values 分層管理（_common / env / ci）
✅ Phase 5 alerting 直接寫 vmalert YAML rule，不需要 PrometheusRule CRD converter

---

## 實戰陷阱（踩過的雷）

### 1. Operator 模式下 `terraform destroy` 容易留孤兒

```
順序問題：
  1. helm uninstall victoria-metrics-operator
     → Operator pod 死
  2. kubectl delete VMCluster
     → CRD 物件想刪，但 finalizer 沒人處理（Operator 已死）
     → 卡 Terminating
  3. StatefulSet / PVC / Service 變成孤兒
     → terraform state 已乾淨，但 K8s 資源還在
```

解法：先砍 CRD object（讓 Operator 處理 finalizer）→ 再砍 Operator → 再砍 CRD definition。

### 2. 同樣 helm chart `victoria-metrics-cluster` 把 vmselect 做成 Deployment

vmselect chart 預設：
```yaml
vmselect:
  replicaCount: 2
  persistentVolume:
    enabled: true
    accessModes:
      - ReadWriteOnce
```

→ Deployment + 共用 RWO PVC + replicas=2 = **永遠 Multi-Attach 卡死**。

第一個 Pod 起來 attach PVC 成功，第二個 Pod 永遠 ContainerCreating。

```
Multi-Attach error for volume "pvc-xxx"
Volume is already used by pod(s) vm-cluster-vmselect-yyy
```

解法（多 replica 想要持久 cache 沒辦法）：
- `persistentVolume.enabled: false` → 用 emptyDir，個別 Pod 各自 cache
- 或 `replicaCount: 1`（捨 HA）
- 或 `accessModes: ReadWriteMany` + EFS（過度工程）

→ vmselect cache 是 read-mostly 的優化，**emptyDir 是對的選擇**。Operator 模式之所以沒問題是因為它把 vmselect 做成 StatefulSet，每 replica 有自己 PVC（`volumeClaimTemplate`）。

### 3. Helm chart fullnameOverride 影響所有資源名

```yaml
fullnameOverride: vm-cluster
```

→ StatefulSet 變 `vm-cluster-vmstorage` 而不是 `vm-cluster-victoria-metrics-cluster-vmstorage`。

連帶影響：
- PVC name = `vmstorage-volume-vm-cluster-vmstorage-{0,1,2}`
- Service name = `vm-cluster-vmselect` / `vm-cluster-vminsert`
- Grafana datasource URL 必須對齊
- vmauth `url_prefix` 必須對齊
- Pre-bind PV 的 claimRef 必須對齊

設 `fullnameOverride` 之前先 `helm template ... | grep -E "kind:|name:"` 確認所有名字。

### 4. Operator → Helm migration 保資料策略

EBS 在 Operator 模式建（StatefulSet 動態 provision），Helm 模式 PVC name 變了沒人接 → 看似要丟 90 天資料。

實際做法：
1. Operator 模式 PV `reclaimPolicy: Retain` → 砍 StatefulSet 後 EBS 保留
2. Helm 模式之前手動建 PV，**寫死 EBS volumeHandle + 預先 claimRef** 對應 Helm 即將建的 PVC name
3. Helm chart 起 StatefulSet → PVC 自動 Bound 到我們建的 PV → mount 舊 EBS → 看到舊資料

關鍵 PV spec：
```yaml
spec:
  csi:
    volumeHandle: vol-018b913a6d45ef78c   # 舊 EBS
  claimRef:
    namespace: monitoring
    name: vmstorage-volume-vm-cluster-vmstorage-0   # Helm 即將建的 PVC name
  nodeAffinity:                            # EBS 是 AZ 級別，必加
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: topology.kubernetes.io/zone
              operator: In
              values:
                - us-east-1c               # EBS 所在 AZ
```

少了 `nodeAffinity` 會踩到 `InvalidVolume.ZoneMismatch`——scheduler 不知道 EBS 卡在哪 AZ，Pod 排到別的 AZ 就 attach fail。

---

## 結論

| 場景 | 選 |
|---|---|
| 中央 cluster、destroy/apply 要乾淨 | **Helm chart** |
| 多 tenant、動態 VMUser 多 token 路由 | Operator |
| Phase 5 用 PrometheusRule | Operator |
| Phase 5 直接寫 vmalert YAML rule | Helm chart |
| 團隊不熟 K8s CRD | **Helm chart** |
| 單一 destroy/apply 操作多次 | **Helm chart** |

**TI Monitoring 專案選 Helm chart**，理由是 destroy 體驗、values layering 一致性、團隊熟悉度。多 region token 透過 templatefile 在 vmauth `auth.yml` 渲染，不靠 VMUser CRD。

---

## 相關 note

- [K8s Operator 模式](/docs/kubernetes/k8s-operator-pattern) — 通用 Operator vs Helm 比較
- [K8s Storage 實戰陷阱](/docs/kubernetes/k8s-storage) — PV/PVC、AZ、Multi-Attach 細節
- [VictoriaMetrics 架構](/docs/monitoring/4-victoriametrics-architecture) — VM 元件本身
