---
sidebar_position: 3
---

# K8s & AWS 基礎名詞對照表

---

## Kubernetes 核心

| 名詞 | 一句話 | 類比 | 為什麼 inference system 要懂 |
|---|---|---|---|
| **Pod** | 最小部署單位，跑一個或多個 container | 一台機器上跑的一個 process | 你的 inference server 就跑在 Pod 裡，一個 Pod = 一個 GPU 占用單位 |
| **Deployment** | 管理 Pod 的副本數量、更新策略 | PM 說「這個服務要跑 3 份」 | inference server 的標準 workload 類型，支援 rolling update 不中斷服務 |
| **StatefulSet** | 有狀態的 Deployment，每個 Pod 有固定名稱和磁碟 | 資料庫 instance | 向量 DB（Qdrant, Weaviate）、時序 DB 用這個，不是 inference server |
| **Service** | 給一組 Pod 一個穩定的內部 IP/DNS | 櫃台接待 | inference server 跑多個 replica，外部用 Service 統一入口，不用管哪個 Pod |
| **Ingress** | L7 路由規則（host/path → Service） | 大樓門口指示牌 | 對外暴露 `/predict` endpoint，同時可以配 TLS、rate limiting |
| **Namespace** | 資源隔離的虛擬分組 | 辦公室的不同樓層 | 把 inference、monitoring、infra 分開，避免 resource quota 互相影響 |
| **ConfigMap** | 存設定檔（非機密） | 共用資料夾的 config | model 參數、服務設定不用 bake 進 image，改設定不用重 build |
| **Secret** | 存機密資料（密碼、token） | 保險箱裡的 config | 存 S3 token、DB 密碼、API key，絕對不要 hardcode 在 image 或 YAML 裡 |
| **PVC** | PersistentVolumeClaim — Pod 的磁碟申請單 | 跟 IT 申請硬碟 | TSDB、向量 DB 需要 PVC；inference server 通常不需要（model 用 emptyDir 或直接從 S3 載） |
| **PV** | PersistentVolume — 實際的磁碟 | IT 給你的硬碟 | K8s 自動幫你建，通常不需要手動管 |
| **StorageClass** | 磁碟的規格表 | 硬碟型號目錄 | EKS 用 gp3，選錯（gp2）會花冤枉錢且 IOPS 不夠 |
| **CRD** | CustomResourceDefinition — 自訂資源類型 | 教 K8s 認識新東西 | 很多 ML infra 工具（KServe、Ray、Argo Workflows）用 CRD 擴展 K8s |
| **Operator** | 自動管理 CRD 的 controller | 機器人看 CRD，有變化就處理 | Prometheus Operator、GPU Operator 都是，幫你自動管複雜的有狀態系統 |
| **DaemonSet** | 每個 Node 跑一個 Pod | 每台機器都裝的 agent | `dcgm-exporter`（GPU metrics）、`node-exporter` 都用 DaemonSet，新 GPU node 加入自動安裝 |
| **Node** | K8s cluster 裡的一台機器 | 辦公室的一台電腦 | GPU inference 要確保 Pod 排到有 GPU 的 node，用 nodeSelector 或 nodeAffinity |
| **Helm** | K8s 的套件管理工具 | 像 pip/npm | 部署 Prometheus、Grafana、NGINX、你自己的服務都用 Helm，不用手寫 20 個 YAML |
| **kubectl** | K8s 的 CLI 工具 | 像 aws cli | debug、部署、查 log 的日常工具 |
| **HPA** | Horizontal Pod Autoscaler — 自動水平擴縮 | 流量大自動加 worker | 根據 CPU/memory/custom metrics 自動調整 inference server replica 數量 |
| **ResourceQuota** | 限制一個 namespace 能用多少資源 | 部門預算上限 | 防止 inference 服務把整個 cluster 的 GPU 都吃光，保護其他 namespace |
| **LimitRange** | 設定 Pod 的預設資源和上下限 | 每個員工的費用報銷上限 | 沒設 resources 的 Pod 套用預設值，防止人家不設 limits 就佔資源 |

---

## HPA 詳細說明

> **Python 類比**：
> ```python
> # HPA 就像 Celery 的 autoscale 功能
> # celery worker --autoscale=10,2
> # → 最少 2 個 worker，最多 10 個，根據 queue 深度自動調整
>
> # K8s HPA 等價：
> # minReplicas: 2, maxReplicas: 10
> # 根據 CPU 使用率 or 自訂 metrics 自動調整
> ```

基礎 CPU HPA：
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: inference-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: inference-server
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

## ConfigMap 詳細說明

ConfigMap 有兩種用法：**環境變數**和**volume 掛載**。

```yaml
# 建立 ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: inference-config
data:
  MAX_BATCH_SIZE: "32"          # 當環境變數用
  TIMEOUT_SECONDS: "30"
  config.yaml: |                # 當設定檔用（volume mount）
    model:
      name: llm-7b
      temperature: 0.7
```

```yaml
# 用法 1：環境變數
env:
  - name: MAX_BATCH_SIZE
    valueFrom:
      configMapKeyRef:
        name: inference-config
        key: MAX_BATCH_SIZE

# 用法 2：整個 ConfigMap 當環境變數
envFrom:
  - configMapRef:
      name: inference-config

# 用法 3：掛成設定檔
volumeMounts:
  - name: config
    mountPath: /app/config
volumes:
  - name: config
    configMap:
      name: inference-config
```

> **Python 類比**：
> ```python
> # ConfigMap = 外部注入的設定，不 bake 進 code 裡
> import os
>
> # 環境變數用法（ConfigMap → 環境變數）
> max_batch = int(os.environ["MAX_BATCH_SIZE"])  # 來自 ConfigMap
>
> # Volume 用法（ConfigMap → 檔案）
> import yaml
> with open("/app/config/config.yaml") as f:
>     config = yaml.safe_load(f)   # 來自 ConfigMap volume mount
> ```

---

## Secret 詳細說明

Secret 跟 ConfigMap 用法幾乎一樣，但 K8s 會對 Secret 做 base64 編碼（注意：不是加密，只是編碼）。生產環境建議用 AWS Secrets Manager + External Secrets Operator，或 IRSA 直接授權存取。

```yaml
# 建立 Secret（value 要 base64 encode）
apiVersion: v1
kind: Secret
metadata:
  name: inference-secrets
type: Opaque
data:
  api-key: bXktc2VjcmV0LWtleQ==    # base64("my-secret-key")
```

```yaml
# 在 Pod 裡使用
env:
  - name: API_KEY
    valueFrom:
      secretKeyRef:
        name: inference-secrets
        key: api-key
```

> **Python 類比**：
> ```python
> # Secret = .env 檔案的 K8s 版本
> # 不要把 API key hardcode 在 code 或 image 裡
>
> from dotenv import load_dotenv
> load_dotenv()  # 本地開發：從 .env 讀
>
> import os
> api_key = os.environ["API_KEY"]  # K8s：從 Secret 注入的環境變數讀
> ```

---

## Namespace 詳細說明

Namespace 是 K8s 的邏輯隔離層，同一個 cluster 裡切出不同的「虛擬 cluster」。

```bash
# 常見的 namespace 規劃
kubectl get namespaces

# inference  → inference server、batch job
# monitoring → Prometheus、Grafana、AlertManager
# infra      → cert-manager、ingress-controller
# default    → 不要在 default namespace 跑 production workload！
```

```yaml
# 建立 namespace
apiVersion: v1
kind: Namespace
metadata:
  name: inference
  labels:
    environment: production
```

> **Python 類比**：
> ```python
> # Namespace = Python 的 module/package
> # 不同 namespace 的資源名稱可以重複，就像不同 module 可以有同名的函數
>
> # inference.Service("my-service") 和 monitoring.Service("my-service") 是不同的
> # 就像 numpy.array 和 pandas.array 是不同的東西
> ```

**跨 namespace 溝通**：

```bash
# 同 namespace：直接用 service 名稱
curl http://inference-service:8080/predict

# 跨 namespace：用 FQDN
curl http://inference-service.inference.svc.cluster.local:8080/predict
```

---

## IRSA — IAM Roles for Service Accounts

IRSA 是 EKS 上讓 Pod 取得 AWS 資源存取權限的正確方式。不要把 AWS credentials 放進 Secret！

```
傳統錯誤做法：
  AWS_ACCESS_KEY_ID + SECRET → Secret → Pod 環境變數
  問題：key 洩漏、無法 rotate、稽核困難

IRSA 正確做法：
  IAM Role → 綁定到 K8s ServiceAccount → Pod 自動取得臨時 token
  好處：不需要管 key、自動 rotate、細粒度權限控制
```

```yaml
# Step 1: 建立 ServiceAccount 並標記要使用的 IAM Role
apiVersion: v1
kind: ServiceAccount
metadata:
  name: inference-sa
  namespace: inference
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/inference-role

# Step 2: Deployment 指定使用這個 ServiceAccount
spec:
  template:
    spec:
      serviceAccountName: inference-sa   # 使用上面的 SA
      containers:
        - name: inference-server
          # 不需要設定 AWS_ACCESS_KEY_ID！
          # boto3 會自動從環境取得臨時 token
```

```python
# Python code 不需要改，boto3 自動使用 IRSA token
import boto3

s3 = boto3.client("s3")  # 自動使用 IRSA 提供的臨時憑證
response = s3.get_object(Bucket="my-models", Key="weights.bin")
```

> **Python 類比**：
> ```python
> # IRSA = 像 Python 的 @property 動態取得 token，而不是 hardcode 密碼
>
> # 錯誤做法（hardcode）：
> AWS_KEY = "AKIAIOSFODNN7EXAMPLE"   # 危險！洩漏就完了
>
> # 正確做法（IRSA）：
> import boto3
> session = boto3.Session()
> # SDK 自動去 IMDSv2 拿臨時 token，你完全不用管
> creds = session.get_credentials()  # 動態取得，每小時自動 rotate
> ```

---

## ResourceQuota 詳細說明

```yaml
# 限制 inference namespace 最多能用多少資源
apiVersion: v1
kind: ResourceQuota
metadata:
  name: inference-quota
  namespace: inference
spec:
  hard:
    requests.nvidia.com/gpu: "8"    # 最多申請 8 張 GPU
    requests.cpu: "32"
    requests.memory: "128Gi"
    limits.cpu: "64"
    limits.memory: "256Gi"
    pods: "50"                       # 最多 50 個 Pod
```

> **Python 類比**：
> ```python
> # ResourceQuota = 限制一個 team 能用多少雲端資源的預算控制
> # 就像 AWS Service Quotas，但可以自己設定
>
> class TeamBudget:
>     max_gpu = 8
>     max_memory_gb = 128
>
>     def can_allocate(self, gpu: int, memory_gb: int) -> bool:
>         return (self.used_gpu + gpu <= self.max_gpu and
>                 self.used_memory + memory_gb <= self.max_memory_gb)
> ```

---

## LimitRange 詳細說明

```yaml
# 設定 namespace 裡每個 Pod 的預設資源和上下限
apiVersion: v1
kind: LimitRange
metadata:
  name: inference-limits
  namespace: inference
spec:
  limits:
    - type: Container
      default:              # 沒設 limits 的 Pod 套用這個
        cpu: "2"
        memory: "4Gi"
      defaultRequest:       # 沒設 requests 的 Pod 套用這個
        cpu: "500m"
        memory: "1Gi"
      max:                  # 單個 container 最多
        cpu: "16"
        memory: "64Gi"
      min:                  # 單個 container 最少
        cpu: "100m"
        memory: "128Mi"
```

---

## AWS 基礎

| 名詞 | 一句話 | 為什麼 inference system 要懂 |
|---|---|---|
| **EKS** | Elastic Kubernetes Service — AWS 代管的 K8s | 你的 inference cluster 跑在這上面，AWS 幫你管 control plane |
| **EC2** | Elastic Compute Cloud — 虛擬機 | K8s worker node 就是 EC2，GPU 機型（p3、p4、g4dn、g5）在這裡選 |
| **EBS** | Elastic Block Store — 網路磁碟 | StatefulSet 的 PVC 後端，選 gp3 而不是 gp2 |
| **ALB** | Application Load Balancer — L7 負載均衡 | Ingress 背後的實際 LB，支援路徑路由、TLS termination、WAF |
| **ECR** | Elastic Container Registry — Docker image 倉庫 | 存你的 inference server image，跟 EKS 整合不需要額外 auth |
| **IAM** | Identity and Access Management — 權限管理 | IRSA 的基礎，Pod 存取 S3/Secrets Manager 的權限在這裡設 |
| **ACM** | AWS Certificate Manager — SSL/TLS 憑證管理 | Ingress 的 HTTPS 憑證，免費且自動 renew |
| **Secrets Manager** | 集中管理密碼和 token | 比 K8s Secret 更安全，支援自動 rotation，配合 External Secrets Operator 使用 |
| **S3** | Simple Storage Service — 物件儲存 | 存 model weights、batch inference 的 input/output，幾乎所有 ML pipeline 都用到 |
| **Route53** | DNS 服務 | Ingress 的 domain 設定，`inference.mycompany.com` → ALB |
| **VPC** | Virtual Private Cloud — 虛擬網路 | EKS cluster 跑在 VPC 裡，控制哪些服務可以互相溝通 |
| **Transit Gateway** | 跨 VPC / 跨 Region 的網路路由 | 多個 VPC 之間的 inference 服務互連，或跨 region 部署 |

---

## Terraform

| 名詞 | 一句話 |
|---|---|
| **Terraform** | IaC 工具，用 HCL 定義雲端資源 |
| **Provider** | Terraform 跟雲端 API 的橋接 |
| **Module** | 一組 resource 打包成可重用模組 |
| **State** | Terraform 記錄的資源狀態 |
| **Plan** | 預覽變更 |
| **Apply** | 實際執行變更 |
| **Terragrunt** | Terraform 的 wrapper，解決多環境共用 |

---

## Monitoring

| 名詞 | 一句話 |
|---|---|
| **Prometheus** | 開源監控系統，pull-based metrics 收集 |
| **remote_write** | Prometheus 把 metrics 推到遠端儲存的標準 API |
| **external_labels** | 加在所有 metrics 上的固定 label |
| **PromQL** | Prometheus 的查詢語言 |
| **Grafana** | 視覺化 dashboard 工具 |
| **Datasource** | Grafana 連接資料來源的設定 |
| **Cardinality** | Metrics 的唯一 time series 數量 |
