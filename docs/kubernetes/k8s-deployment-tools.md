---
sidebar_position: 7
---

# K8s 部署工具比較 & Terraform 定位

---

## Terraform 不是 K8s 部署工具

Terraform 是 **infrastructure 管理工具**，K8s 只是它能管的其中一個東西。

### Terraform 能管的東西

```
AWS       → VPC, EKS, EC2, RDS, S3, IAM, Route53, ALB...
Azure     → AKS, VM, Storage, AD...
GCP       → GKE, Compute, Cloud SQL...
K8s       → Helm release, kubectl manifest, namespace...
其他      → GitHub repo, Datadog monitor, PagerDuty,
            Cloudflare DNS, Vault secrets...
```

基本上任何有 API 的服務都能用 Terraform 管。

---

## K8s 部署主流工具比較

| 工具 | 定位 | 適合 |
|---|---|---|
| **Terraform + Helm** | 建 infra + 部署 app 一起管 | Ops/Platform team |
| **Helm** 單獨用 | K8s app 部署 | 只管 K8s，不管雲端資源 |
| **ArgoCD / FluxCD** | GitOps — git push 自動部署到 K8s | 持續部署、app team |
| **kubectl** | 手動 apply YAML | debug、學習 |
| **Kustomize** | YAML overlay 管多環境 | 不想用 Helm template |
| **Pulumi** | 用程式語言（Python/TypeScript）寫 infra | 不想學 HCL |

---

## Terraform + Helm 搭配

```
Terraform 管：
  → K8s cluster 本身（EKS / AKS / GKE）
  → 雲端資源（Load Balancer, IAM, Secrets, Storage...）
  → 呼叫 Helm 部署 app

Helm 管：
  → K8s 裡面的 app（Deployment, Service, ConfigMap, RBAC...）
```

如果只用 Helm — 能部署 app 到 K8s，但誰來建 K8s cluster？Load Balancer？Secrets？

**Terraform 管整個 stack（雲端 + K8s），Helm 只管 K8s 裡面的 app。**

---

## Helm chart vs 手寫 YAML

### Helm chart — 幫你寫好 YAML

```
手動：
  手寫 Deployment YAML
  手寫 Service YAML
  手寫 ServiceAccount + RBAC YAML
  kubectl apply -f 一個一個套

Helm：
  chart 裡已包好所有 YAML template
  只需要填 values（image tag, replica count...）
  helm install 一次全部搞定
```

### kubectl_manifest — 還是自己寫 YAML

```hcl
# 放在 Terraform 裡，但 YAML 是自己寫的
yaml_body = <<-YAML
  apiVersion: apps/v1
  kind: Deployment
  ...
YAML
```

### 比較

| | 手動 kubectl | Terraform + Helm |
|---|---|---|
| 複雜元件 | 自己寫 20+ YAML | Helm chart 包好，填 values |
| 簡單資源 | `kubectl apply -f` | `kubectl_manifest`（一樣自己寫 YAML） |
| 版本控制 | 手動管 YAML | git + Terraform state 自動追蹤 |
| 多環境 | 每個環境複製一份改值 | 同一份 code 不同 inputs |
| 回滾 | apply 舊版本 YAML | Terraform state 追蹤，自動 diff |

**Terraform 的價值不是「幫你寫 YAML」，而是管理狀態 + 多環境 + 版本控制 + 依賴順序。**

---

## Helm values.yaml 多環境管理

Helm 的核心思想：**一份 chart template + 不同環境的 values.yaml**。

### 目錄結構

```
my-inference-chart/
├── Chart.yaml
├── templates/
│   ├── deployment.yaml      # 用 {{ .Values.xxx }} 取值
│   ├── service.yaml
│   ├── hpa.yaml
│   └── configmap.yaml
├── values.yaml              # 預設值（也是文件）
├── values-staging.yaml      # staging 環境覆蓋
└── values-production.yaml   # production 環境覆蓋
```

### values.yaml（預設值）

```yaml
# values.yaml — 所有環境的預設值 + 文件化
replicaCount: 1

image:
  repository: my-org/inference-server
  tag: latest
  pullPolicy: IfNotPresent

resources:
  requests:
    cpu: "2"
    memory: "8Gi"
    nvidia.com/gpu: "1"
  limits:
    cpu: "4"
    memory: "16Gi"
    nvidia.com/gpu: "1"

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 5
  targetCPUUtilizationPercentage: 70

model:
  path: s3://my-models/llm-7b/
  maxBatchSize: 32

probes:
  readiness:
    initialDelaySeconds: 60
    periodSeconds: 10
  liveness:
    initialDelaySeconds: 120
    periodSeconds: 30
```

### values-staging.yaml（staging 環境只覆蓋不同的部分）

```yaml
# values-staging.yaml — 只寫跟預設值不同的部分
replicaCount: 1

image:
  tag: "v1.2.0-rc1"

resources:
  requests:
    cpu: "1"
    memory: "4Gi"
    nvidia.com/gpu: "1"
  limits:
    cpu: "2"
    memory: "8Gi"
    nvidia.com/gpu: "1"

model:
  maxBatchSize: 8    # staging 用小 batch，省資源
```

### values-production.yaml

```yaml
# values-production.yaml
replicaCount: 3

image:
  tag: "v1.2.0"
  pullPolicy: Always

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10

model:
  maxBatchSize: 64

probes:
  readiness:
    initialDelaySeconds: 90   # production model 可能更大，需要更多時間
```

### 部署指令

```bash
# staging
helm upgrade --install inference-server ./my-inference-chart \
  -f values.yaml \
  -f values-staging.yaml \
  --namespace staging

# production
helm upgrade --install inference-server ./my-inference-chart \
  -f values.yaml \
  -f values-production.yaml \
  --namespace production \
  --set image.tag=v1.2.0   # 也可以用 --set 覆蓋單一值（CI/CD 常用）
```

---

## Kustomize — YAML overlay 不用 template

Kustomize 的思想：**保留原始 YAML，用 overlay 疊加差異**。不用 template 語法，純 YAML。

### 目錄結構

```
k8s/
├── base/                       # 原始設定，所有環境共用
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── configmap.yaml
└── overlays/
    ├── staging/
    │   ├── kustomization.yaml
    │   └── patch-resources.yaml   # 只寫要改的部分
    └── production/
        ├── kustomization.yaml
        └── patch-resources.yaml
```

### base/kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
  - configmap.yaml
```

### base/deployment.yaml（原始 YAML，不含任何 template 語法）

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inference-server
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: inference-server
          image: my-org/inference-server:latest
          resources:
            requests:
              cpu: "2"
              memory: "8Gi"
              nvidia.com/gpu: "1"
            limits:
              cpu: "4"
              memory: "16Gi"
              nvidia.com/gpu: "1"
```

### overlays/production/kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# 基於 base
resources:
  - ../../base

# 修改 image tag
images:
  - name: my-org/inference-server
    newTag: "v1.2.0"   # 只改 tag，不用複製整個 YAML

# 設定 replica 數量
replicas:
  - name: inference-server
    count: 3

# 套用 resource patch
patches:
  - path: patch-resources.yaml
```

### overlays/production/patch-resources.yaml

```yaml
# 只寫要改的部分（strategic merge patch）
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inference-server
spec:
  template:
    spec:
      containers:
        - name: inference-server
          resources:
            requests:
              cpu: "4"
              memory: "16Gi"
            limits:
              cpu: "8"
              memory: "32Gi"
```

### 部署指令

```bash
# 預覽最終 YAML（不實際部署）
kubectl kustomize overlays/production

# 部署
kubectl apply -k overlays/production

# 也可以用 Helm 管 Kustomize（兩者可以共存）
```

---

## ArgoCD GitOps 流程

ArgoCD 的核心思想：**git repo 是真相來源，cluster 狀態要和 git 保持一致**。

```
GitOps 流程：

  開發者 push code
       │
       ▼
  Git Repo（YAML / Helm / Kustomize）
       │
       ▼  ArgoCD 定期 pull（或 webhook 觸發）
  ArgoCD 比較：
  「git 裡的 desired state」vs「cluster 的 current state」
       │
       ├── 一致 → 什麼都不做（Synced）
       └── 不一致 → 自動（或手動）同步到 cluster（Out of Sync → Synced）
```

```
┌─────────────────────────────────────────────────────┐
│                    Git Repository                   │
│                                                     │
│  main branch:                                       │
│    k8s/production/                                  │
│      deployment.yaml  (image: v1.1.0)               │
│                                                     │
│  PR merged: image tag changed to v1.2.0             │
│    k8s/production/                                  │
│      deployment.yaml  (image: v1.2.0)  ← 新的      │
└────────────────────┬────────────────────────────────┘
                     │ ArgoCD 偵測到變化
                     ▼
┌─────────────────────────────────────────────────────┐
│                   ArgoCD                           │
│                                                     │
│  App: inference-server                              │
│  Status: OutOfSync ← git 和 cluster 不一致          │
│                                                     │
│  Diff:                                              │
│    - image: my-org/inference-server:v1.1.0          │
│    + image: my-org/inference-server:v1.2.0          │
│                                                     │
│  Auto-sync: Enabled → 自動 apply 變更               │
└────────────────────┬────────────────────────────────┘
                     │ kubectl apply
                     ▼
┌─────────────────────────────────────────────────────┐
│                  EKS Cluster                        │
│                                                     │
│  Deployment rolling update: v1.1.0 → v1.2.0        │
│  Status: Synced ✓                                   │
└─────────────────────────────────────────────────────┘
```

### ArgoCD Application 設定

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: inference-server
  namespace: argocd
spec:
  project: default

  # 從哪裡讀設定
  source:
    repoURL: https://github.com/my-org/k8s-manifests
    targetRevision: main
    path: apps/inference-server/overlays/production   # Kustomize overlay

  # 部署到哪裡
  destination:
    server: https://kubernetes.default.svc   # 當前 cluster
    namespace: inference

  syncPolicy:
    automated:
      prune: true       # git 刪了資源，cluster 也刪
      selfHeal: true    # 有人手動改 cluster，自動 revert 回 git 的狀態
    syncOptions:
      - CreateNamespace=true
```

### ArgoCD 的優勢（vs 手動 kubectl apply）

| | 手動 kubectl apply | ArgoCD GitOps |
|---|---|---|
| 部署紀錄 | 誰部署了什麼？不知道 | git commit history = 完整部署紀錄 |
| 回滾 | 手動 apply 舊 YAML | `git revert` + ArgoCD 自動同步 |
| 誰改了 cluster？ | 不知道 | git blame 一目了然 |
| 環境一致性 | 可能有人手動改了 cluster | selfHeal 自動修正回 git 狀態 |
| 部署 PR review | 沒有 | k8s YAML 的 PR review 就是部署 review |
