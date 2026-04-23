---
sidebar_position: 5
---

# CronJob

K8s 的 CronJob 就是 crontab 的 K8s 版本，定時觸發一個 Job（跑完就停的容器）。

> **Python 類比**：就像用 `APScheduler` 或 `crontab` 定時執行 Python script，但在 K8s cluster 裡執行、有 retry 機制、有歷史紀錄。

```python
# 你以前可能這樣做：
# crontab: "10 */1 * * *  python /app/cleanup.py"

# K8s CronJob 等價：
# schedule: "10 */1 * * *"  → 每小時第 10 分鐘
# backoffLimit: 3            → 失敗最多重試 3 次（像 tenacity retry）
# concurrencyPolicy: Forbid  → 上一個還沒跑完就不啟動新的
```

---

## 設定範例

```yaml
schedule: "10 */1 * * *"        # 每小時第 10 分鐘執行
concurrencyPolicy: Forbid       # 上一次沒跑完不啟動新的
successfulJobsHistoryLimit: 1   # 只保留 1 個成功紀錄
backoffLimit: 3                 # 失敗最多重試 3 次
```

---

## concurrencyPolicy 三種

| 值 | 行為 |
|---|---|
| `Forbid` | 上一次沒跑完，這次跳過 |
| `Allow` | 允許同時多個 Job 並發（預設） |
| `Replace` | 殺掉上一次，啟動新的 |

```python
# Python 類比：

# Forbid = threading.Lock() 搶不到就放棄
import threading
lock = threading.Lock()
if not lock.acquire(blocking=False):
    print("上次還沒跑完，跳過這次")

# Allow = 不管 lock，每次都開新 thread
# Replace = 先 cancel 舊 task，再開新的（像 asyncio.Task.cancel()）
```

---

## 適合的使用場景

```python
# 1. 定時備份
# schedule: "0 2 * * *"  → 每天凌晨 2 點
python backup_database.py --target s3://my-bucket/

# 2. 定時清理過期資料
# schedule: "0 * * * *"  → 每小時
python cleanup_expired_tokens.py --ttl 86400

# 3. 定期產生報表
# schedule: "30 8 * * 1"  → 每週一早上 8:30
python generate_weekly_report.py --send-email

# 4. Inference batch job
# schedule: "*/30 * * * *"  → 每 30 分鐘執行一次 batch inference
python batch_inference.py --input s3://data/pending/ --output s3://data/results/
```
