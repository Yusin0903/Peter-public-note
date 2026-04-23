---
sidebar_position: 1
---

# 自己管 vs 全託管（Self-managed vs Fully managed）

## 自己管（MySQL on EC2）

你要自己處理所有事情：

```
你負責：
├── 開 EC2 裝 MySQL
├── 設定 CPU / Memory
├── 硬碟快滿了要擴容
├── 定期備份
├── 版本升級 / 安全性修補
├── 主從複製（高可用）
├── 監控、告警
└── 壞了要自己修
```

> **Python 類比**：就像你自己 `pip install` 每個套件、手動管理 virtualenv、自己寫備份 script，所有基礎設施都是你的責任。
>
> ```python
> # 自己管 = 從頭建所有東西
> import subprocess
>
> subprocess.run(["apt", "install", "mysql-server"])   # 安裝
> subprocess.run(["mysqldump", "-u", "root", "mydb"])  # 備份（你自己寫）
> subprocess.run(["systemctl", "restart", "mysql"])    # 掛了自己重啟
> ```

---

## 全託管（DynamoDB）

AWS 幫你處理，你只管用：

```
AWS 負責：
├── 硬體、OS、資料庫引擎
├── 自動擴縮容量
├── 自動備份
├── 自動跨 AZ 複製（高可用）
├── 安全性修補
└── 監控

你只需要：
├── 建表
├── 讀寫資料
└── 付錢（按用量計費）
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

## 一句話總結

| | 自己管（EC2 + MySQL） | 全託管（DynamoDB） |
|---|---|---|
| 類比 | 自己煮飯，買食材、洗碗全包 | 去餐廳點餐，廚房的事不用管 |
| Python 比喻 | 自己架 server + 寫所有工具 script | 直接 `import boto3` 用 |
| 彈性 | 高（可以隨意調整） | 低（AWS 決定底層） |
| 維運成本 | 高 | 幾乎零 |
