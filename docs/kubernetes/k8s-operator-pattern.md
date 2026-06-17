---
title: "K8s Operator 模式"
sidebar_position: 11
---
<!-- generated from ~/peter-llm-wiki; edit source there, not here -->

# K8s Operator 模式

## Helm vs Operator 差別

**純 Helm：**

```
你 → helm install nginx → K8s 直接建 Pod/Service/Deployment
```

Helm 就是一個包裝好的安裝包，裝完就結束，K8s 直接管理這些資源。

**Operator 模式：**

```
你 → helm install nginx-operator → 裝了一個「管理員」
你 → kubectl apply nginx.yaml (CRD) → 管理員看到，幫你建 Pod/Service/Deployment
```

多了一個中間人（Operator）在 cluster 裡持續跑，負責監控和管理你的應用。

簡單說：
- **Helm** = 安裝包
- **Operator** = 安裝包 + 常駐管理員

---

## 為什麼要有 Operator？

有些應用很複雜，光靠 K8s 原生資源不夠用。例如資料庫 cluster：
- 要知道哪個是 primary、哪個是 replica
- 升級要按特定順序
- 節點掛掉要自動重新選 primary

這些邏輯 K8s 不懂，Operator 把這些**領域知識**寫進去，幫你自動處理。

---

## 適合用 Operator 的場景

| 場景 | 原因 |
|---|---|
| 資料庫 cluster（PostgreSQL、MySQL） | 主從切換、備份、升級順序有複雜邏輯 |
| 多個同類 cluster 動態建立/刪除 | CRD 讓每個 cluster 只需一個 YAML |
| 從 Prometheus Operator 遷移 | 保留 `ServiceMonitor` CR 相容性 |
| 需要自動 reconcile（自我修復） | Operator 持續監控，偏離就修正 |

---

## Operator 的缺點

**Destroy 順序問題（Terraform + Operator 常見）：**

```
Terraform destroy 順序：
  1. 刪 VMCluster CR（Operator 要負責清理子資源）
  2. 刪 Operator（但 Operator 已經不在了）
  → 沒人處理 finalizer → CR 卡在 Terminating
  → StatefulSet/Pod 孤兒化，繼續存活
```

Terraform 只知道它自己建的資源，Operator 動態建出來的 Pod/StatefulSet 不在 TF state 裡，所以不會被清掉。

**乾淨 destroy 的正確做法：**
1. 先手動 `kubectl delete <CR>` 等它真的消失
2. 再跑 `terraform destroy`

---

## 常見 Operator 範例

| 應用 | Operator |
|---|---|
| VictoriaMetrics | VictoriaMetrics Operator（管 VMCluster、VMAgent 等 CRD） |
| PostgreSQL | CloudNativePG、Zalando PostgreSQL Operator |
| Elasticsearch | Elastic Cloud on Kubernetes (ECK) |
| Kafka | Strimzi Kafka Operator |
| Redis | Redis Enterprise Operator |
