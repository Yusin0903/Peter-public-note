---
title: EKS 用獨立 Node Group 隔離服務避免互搶資源
sidebar_position: 21
---
<!-- generated from ~/peter-llm-wiki; edit source there, not here -->

# EKS 用獨立 Node Group 隔離服務避免互搶資源

## 為什麼要這樣做

如果所有服務都跑在同一個 node group，resource 緊張的時候 K8s 可能把你比較不重要的 pod 踢掉來騰空間給別人。stateful 的服務（像 Thanos compactor、store-gateway、Prometheus）被驅逐的話資料會爛掉，或者需要重新 reattach EBS，整個很麻煩。

解法就是給這些服務一個專屬的 node group，然後用 taint + toleration 確保只有自己的 pod 能跑上去。

## 怎麼設定

### 1. Node Group 加 taint（Terraform）

```hcl
nodegroup_thanos = {
  ...
  taints = [
    {
      key    = "dedicated"
      value  = "thanos"
      effect = "NO_SCHEDULE"
    }
  ]
  labels = {
    role = "thanos"
  }
}
```

`NO_SCHEDULE` 的意思是：沒有對應 toleration 的 pod，K8s 根本不會排到這台機器上。

### 2. Pod 加 toleration + affinity

```yaml
tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "thanos"
    effect: "NoSchedule"

affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: role
              operator: In
              values:
                - thanos
```

toleration 讓 pod 可以進這個 node group，affinity 讓 pod 優先（或強制）選這個 node group。兩個一起用才算完整隔離。

## taint effect 三種選一個

| Effect | 行為 |
|---|---|
| `NoSchedule` | 新 pod 不能調度進來，已跑的不動 |
| `PreferNoSchedule` | 盡量不要，但資源不夠的時候還是會進來 |
| `NoExecute` | 新的不能進，舊的沒有 toleration 也會被踢出去 |

一般用 `NoSchedule` 就夠了。

## 實際踩過的坑

Thanos 幾個 stateful 的 pod（compactor、store-gateway、self-prometheus）的 PVC 是 gp3 EBS，EBS **不能跨 AZ**。如果 node group 的 AZ 沒涵蓋到 PVC 原本建在哪個 AZ，pod 就會一直卡 Pending（`volume node affinity conflict`）。

所以 node group 的 `min_size` 要設成至少跟 AZ 數量一樣多，才能確保每個 AZ 都有機器。只設 `desired_size` 沒用，因為 EKS module 預設會 ignore desired 的變動（避免跟 Cluster Autoscaler 打架）。
