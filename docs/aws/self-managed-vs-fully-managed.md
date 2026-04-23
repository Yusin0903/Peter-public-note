---
sidebar_position: 1
---

# 自己管 vs 半托管 vs 全託管

## 三個層次的對比

AWS 上的服務管理可以分成三個層次，差別在於「你要負責多少基礎設施」：

```
自己管（Self-managed）     半托管（Semi-managed）     全託管（Fully managed）
EC2 + MySQL               RDS (MySQL/Postgres)        DynamoDB
─────────────────────     ───────────────────────     ──────────────────────
你負責一切                 AWS 負責 OS/Engine          AWS 負責一切
最靈活，維運最重            你負責 schema、查詢、HA設定   你只管資料模型和讀寫
```

---

## 自己管（MySQL on EC2）

你要自己處理所有事情：

```
你負責：
├── 開 EC2 裝 MySQL
├── 設定 CPU / Memory
├── 硬碟快滿了要擴容
├── 定期備份（cron job + mysqldump）
├── 版本升級 / 安全性修補
├── 主從複製（高可用）← 這個最容易忘記
├── 監控、告警
└── 壞了要自己修（半夜收到 PagerDuty）
```

> **Python 類比**：就像你自己維護一個 FastAPI server，不只是寫 API，還要自己設定 Nginx、SSL 憑證更新、log rotate、機器掛掉自動重啟。所有基礎設施都是你的責任。
>
> ```python
> # 自己管 = 從頭建所有東西
> import subprocess
>
> subprocess.run(["apt", "install", "mysql-server"])      # 安裝
> subprocess.run(["mysqldump", "-u", "root", "mydb"])     # 備份（你自己寫 cron）
> subprocess.run(["systemctl", "restart", "mysql"])       # 掛了自己重啟
> # 主從複製：你要自己設定 binlog、replication user、slave 同步
> # 磁碟快滿：你要自己加 EBS volume 並擴展 filesystem
> ```

### 真實的災難場景（自己管沒設好複製時）

```
午夜 2:00：主 MySQL 機器磁碟滿了 → MySQL 掛掉
↓
你沒有設 Read Replica → 只有一台機器 → 完全 offline
↓
Inference worker 全部拿不到設定 → 503 錯誤
↓
磁碟擴容要 15 分鐘 → 15 分鐘 downtime

vs.

RDS / DynamoDB：AWS 自動處理，你根本不知道發生了什麼
```

---

## 半托管（RDS）— Inference System 的推薦 SQL 選擇

RDS（Relational Database Service）是最值得注意的中間地帶：

```
AWS 幫你負責：
├── 硬體、OS
├── 資料庫引擎（MySQL / PostgreSQL / 等）的安裝和升級
├── 自動備份（Point-in-time recovery，最多 35 天）
├── Multi-AZ 部署（自動主從切換，約 1-2 分鐘 failover）
├── 儲存自動擴容（autoscaling storage）
└── 安全性修補

你還要負責：
├── 選擇 instance size（db.t3.medium? db.r6g.xlarge?）
├── schema 設計和 migration
├── 查詢優化（index、explain plan）
├── 設定 Multi-AZ（要額外付費）
└── 連線池設定（RDS Proxy 或 SQLAlchemy pool）
```

> **Python 類比**：就像用 managed Kubernetes（EKS）而不是自己裝 K8s，底層節點 OS 是 AWS 管的，但你的 Pod spec、resource limits、HPA 設定還是你的事。
>
> ```python
> # RDS = 你只管 SQL 邏輯，OS/engine 是 AWS 的事
> from sqlalchemy import create_engine
>
> # RDS endpoint 看起來像這樣
> engine = create_engine(
>     "postgresql://user:pass@mydb.cluster-xyz.us-east-1.rds.amazonaws.com/mydb",
>     pool_size=10,
>     max_overflow=20,
> )
>
> # Multi-AZ 自動 failover：主掛了，endpoint 自動指向 standby
> # 你的 code 完全不用改，連接字串一樣
> ```

---

## 全託管（DynamoDB）

AWS 幫你處理，你只管用：

```
AWS 負責：
├── 硬體、OS、資料庫引擎
├── 自動擴縮容量（On-demand mode）
├── 自動備份（PITR）
├── 自動跨 AZ 複製（高可用，SLA 99.999%）
├── 安全性修補
└── 監控

你只需要：
├── 設計 partition key / sort key（最重要的決策）
├── 讀寫資料
└── 付錢（按讀寫單位計費）
```

> **Python 類比**：就像直接用 `boto3` 操作 DynamoDB，你只寫業務邏輯，基礎設施完全不用管。
>
> ```python
> import boto3
>
> # 全託管：你只寫這個，底層一切都是 AWS 的事
> dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
> table = dynamodb.Table("my-table")
>
> table.put_item(Item={"id": "123", "value": "hello"})
> response = table.get_item(Key={"id": "123"})
> # 備份？擴容？HA？→ AWS 自動處理，你完全不用管
> ```

---

## 決策指南：Inference System 該選哪個？

### 直接給結論

| 使用情境 | 推薦選擇 | 理由 |
|---|---|---|
| 存 inference job 狀態（job_id → status） | **DynamoDB** | key-value 查詢，全託管，無連線池煩惱 |
| 存用戶設定、feature flags | **DynamoDB** | 動態讀取，自動擴容 |
| 需要複雜 SQL 查詢、join、transaction | **RDS** | DynamoDB 不支援 join |
| 已有 PostgreSQL schema，遷移成本高 | **RDS** | 保持熟悉的 SQL 模型 |
| 預算極限、規模還小、能接受 downtime | **EC2 + MySQL** | 最便宜，但技術債最高 |

### 對 Python Inference System 的建議

**不要用 EC2 + MySQL**，除非你有專職 DBA。Inference system 的核心價值在模型推理，不在資料庫維運。

**DynamoDB 適合 job metadata**：

```python
# inference job 追蹤：完全適合 DynamoDB
{
    "job_id": "abc-123",        # partition key
    "status": "running",
    "model_version": "v2.3",
    "created_at": "2026-04-23T10:00:00Z",
    "result_s3_path": "s3://bucket/results/abc-123.json"
}
# 查詢模式：總是用 job_id 查，沒有跨 job 的 join → DynamoDB 完美
```

**RDS 適合需要複雜查詢的情境**：

```python
# 需要這類查詢時，用 RDS
SELECT model_version, AVG(latency_ms), COUNT(*)
FROM inference_jobs
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY model_version
ORDER BY AVG(latency_ms) DESC;
# DynamoDB 無法做 GROUP BY、AVG 這類聚合 → 用 RDS
```

---

## 成本比較直覺

```
場景：儲存 100 萬筆 inference job 記錄，每天 10 萬次讀寫

EC2 + MySQL（t3.medium）：
  ├── EC2 費用：~$30/月
  ├── EBS 儲存：~$10/月
  └── 你的維運時間：???（無法計算，但 1次半夜事故 = 幾小時）

RDS（db.t3.medium，Multi-AZ）：
  ├── RDS 費用：~$100/月（Multi-AZ 約 2x 單機）
  └── 幾乎零維運（AWS 幫你 failover）

DynamoDB（On-demand）：
  ├── 儲存：100萬筆 × 1KB ≈ 1GB = $0.25/月
  ├── 讀：10萬次 × $0.000000025 ≈ $0.003/月
  └── 寫：10萬次 × $0.000000125 ≈ $0.013/月
  ＝ 合計 < $1/月（小規模的情況）

結論：DynamoDB 在 key-value 模式下便宜到幾乎免費，
     RDS 的費用多數是你在購買「不用自己處理 failover」的安心感。
```

---

## 一句話總結

| | 自己管（EC2 + MySQL） | 半托管（RDS） | 全託管（DynamoDB） |
|---|---|---|---|
| 類比 | 自己煮飯，買食材、洗碗全包 | 租廚房，廚師是你，設備是房東的 | 去餐廳點餐，廚房的事不用管 |
| 彈性 | 最高 | 高 | 中（schema 受限） |
| 維運成本 | 高 | 低 | 幾乎零 |
| 適合 Inference System | 不推薦 | 需要複雜查詢時 | 首選（job metadata、設定檔） |
