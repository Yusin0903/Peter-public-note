---
sidebar_position: 3
---


# Kubernetes 核心名詞對照表

---

## 基礎資源

| 名詞 | 一句話 | 類比 | 重點 |
|---|---|---|---|
| **Pod** | 最小部署單位，跑一個或多個 container | 一台機器上跑的一個 process | 一個 Pod = 一個工作單位，Pod 掛掉 K8s 會自動重啟 |
| **Deployment** | 管理 Pod 的副本數量、更新策略 | PM 說「這個服務要跑 3 份」 | 標準的無狀態服務 workload 類型，支援 rolling update 不中斷服務 |
| **StatefulSet** | 有狀態的 Deployment，每個 Pod 有固定名稱和磁碟 | 資料庫 instance | 向量 DB、時序 DB 用這個，每個 Pod 有固定的 index（-0, -1, -2） |
| **DaemonSet** | 每個 Node 跑一個 Pod | 每台機器都裝的 agent | `node-exporter`、`fluentd` 都用 DaemonSet，新 Node 加入自動安裝 |
| **CronJob** | 定時執行的 Job | crontab | 定期跑 batch 任務、清理舊資料 |

---

## 網路與路由

| 名詞 | 一句話 | 類比 | 重點 |
|---|---|---|---|
| **Service** | 給一組 Pod 一個穩定的內部 IP/DNS | 櫃台接待 | Pod IP 會變，Service IP 固定；分 ClusterIP、NodePort、LoadBalancer |
| **Ingress** | L7 路由規則（host/path → Service） | 大樓門口指示牌 | 對外暴露 HTTP/HTTPS endpoint，可以配 TLS、path routing |
| **Namespace** | 資源隔離的虛擬分組 | 辦公室的不同樓層 | 把不同服務分開，避免 resource quota 互相影響 |

**跨 namespace 溝通：**

```bash
# 同 namespace：直接用 service 名稱
curl http://my-service:8080

# 跨 namespace：用 FQDN
curl http://my-service.monitoring.svc.cluster.local:8080
```

---

## 設定與機密

| 名詞 | 一句話 | 類比 | 重點 |
|---|---|---|---|
| **ConfigMap** | 存設定檔（非機密） | 共用資料夾的 config | 改設定不用重 build image；可當環境變數或 volume 掛載 |
| **Secret** | 存機密資料（密碼、token） | 保險箱裡的 config | base64 編碼（不是加密）；生產環境建議配合 Secrets Manager + ESO |

**ConfigMap 兩種用法：**

```yaml
# 用法 1：環境變數
env:
  - name: MAX_BATCH_SIZE
    valueFrom:
      configMapKeyRef:
        name: my-config
        key: MAX_BATCH_SIZE

# 用法 2：掛成設定檔
volumeMounts:
  - name: config
    mountPath: /app/config
volumes:
  - name: config
    configMap:
      name: my-config
```

---

## 儲存

| 名詞 | 一句話 | 類比 | 重點 |
|---|---|---|---|
| **PVC** | PersistentVolumeClaim — Pod 的磁碟申請單 | 跟 IT 申請硬碟 | TSDB、DB 需要 PVC；無狀態服務通常不需要 |
| **PV** | PersistentVolume — 實際的磁碟 | IT 給你的硬碟 | K8s 自動幫你建，通常不需要手動管 |
| **StorageClass** | 磁碟的規格表 | 硬碟型號目錄 | EKS 用 gp3，比 gp2 便宜且 IOPS 更好 |

---

## 擴縮與資源控制

| 名詞 | 一句話 | 類比 | 重點 |
|---|---|---|---|
| **HPA** | Horizontal Pod Autoscaler — 自動水平擴縮 | 流量大自動加 worker | 根據 CPU/memory/custom metrics 自動調整 replica 數量 |
| **ResourceQuota** | 限制一個 namespace 能用多少資源 | 部門預算上限 | 防止一個服務把整個 cluster 的資源吃光 |
| **LimitRange** | 設定 Pod 的預設資源和上下限 | 每個員工的費用報銷上限 | 沒設 resources 的 Pod 套用預設值 |

**HPA 範例：**

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-service
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

---

## 擴展機制

| 名詞 | 一句話 | 類比 | 重點 |
|---|---|---|---|
| **CRD** | CustomResourceDefinition — 自訂資源類型 | 教 K8s 認識新東西 | Prometheus Operator、VictoriaMetrics Operator 都用 CRD |
| **Operator** | 自動管理 CRD 的 controller | 機器人看 CRD，有變化就處理 | 幫你自動管複雜的有狀態系統 |

---

## 基礎工具

| 名詞 | 一句話 | 用途 |
|---|---|---|
| **kubectl** | K8s 的 CLI 工具 | debug、部署、查 log 的日常工具 |
| **Helm** | K8s 的套件管理工具 | 部署 Prometheus、Grafana 等，不用手寫一堆 YAML |
| **Node** | K8s cluster 裡的一台機器 | Pod 排到哪個 Node 取決於 nodeSelector / nodeAffinity |

---

## 常用 kubectl 指令

```bash
# 查看 pods
kubectl get pods -n <namespace>
kubectl describe pod <pod-name> -n <namespace>

# 查 logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous  # 上一次掛掉的 log

# 進 container
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# 查 resource 使用量
kubectl top pods -n <namespace>
kubectl top nodes

# 重啟 deployment
kubectl rollout restart deployment/<name> -n <namespace>
```
