---
sidebar_position: 4
---

# SQS 完整指南：Queue 基礎、訊息生命週期與 FIPS

SQS（Simple Queue Service）是 AWS 的全託管訊息佇列。這份筆記從 queue 是什麼講起，到 Inference System 最重要的 visibility timeout，最後說明 MD5/FIPS 問題。

---

## Queue 是什麼

Queue 是「生產者和消費者之間的緩衝區」。生產者把工作放進去，消費者依序取出並處理。

> **Python 類比**：SQS 就像 Python 的 `queue.Queue`，但它住在 AWS 雲端、可以跨機器存取、並且完全不用你維護。
>
> ```python
> import queue
> import threading
>
> # Python 內建 queue — 只在同一個 process 內用
> q = queue.Queue()
> q.put({"job_id": "123", "image_url": "s3://..."})  # 生產者
> item = q.get(timeout=20)                            # 消費者
>
> # SQS — 可以跨機器、跨 Pod、跨 Region
> import boto3
> sqs = boto3.client("sqs", region_name="us-east-1")
> sqs.send_message(QueueUrl=QUEUE_URL, MessageBody='{"job_id": "123"}')
> response = sqs.receive_message(QueueUrl=QUEUE_URL, WaitTimeSeconds=20)
> ```

---

## 訊息生命週期

理解生命週期對 inference system 至關重要，因為推理任務可能要跑好幾分鐘。

```
sent（送入 queue）
    │
    ▼
available（可被 consume）
    │
    ▼ receive_message()
in-flight（被 consumer 拿走，對其他人不可見）
    │
    ├─→ delete_message()    → 永久刪除（成功處理）
    │
    └─→ visibility timeout 到期
            │
            ▼
        available（重新可見，等另一個 consumer 來取）
        (如果超過 maxReceiveCount → 移入 DLQ)
```

```python
# 完整的取得 → 處理 → 刪除 循環
sqs = boto3.client("sqs")

response = sqs.receive_message(
    QueueUrl=QUEUE_URL,
    MaxNumberOfMessages=1,
    WaitTimeSeconds=20,
)

for msg in response.get("Messages", []):
    receipt_handle = msg["ReceiptHandle"]  # 用來刪除這筆訊息的憑證

    try:
        result = process(msg["Body"])           # 處理訊息
        sqs.delete_message(                     # 成功才刪除
            QueueUrl=QUEUE_URL,
            ReceiptHandle=receipt_handle,
        )
    except Exception:
        # 不刪除 → visibility timeout 到期後訊息重回 queue
        # 其他 worker 或下次重試時會再次取得這筆訊息
        raise
```

---

## Visibility Timeout — Inference System 最重要的設定

**這是最容易踩坑的地方。**

Visibility timeout 是「訊息被取走後，隱藏多久再重新出現」的時間。

```
scenario：Inference task 需要 3 分鐘完成，visibility timeout = 30 秒

Worker A 在 t=0 取得訊息
    ↓
t=30s：visibility timeout 到期！訊息重新出現在 queue
    ↓
Worker B 也取得同一筆訊息，開始跑
    ↓
t=180s：Worker A 完成，嘗試 delete → ReceiptHandle 已過期 → 錯誤！
t=180s：Worker B 完成，也 delete → 重複處理！
```

```python
# ❌ 預設 30 秒 visibility timeout，inference 任務必然超時
response = sqs.receive_message(
    QueueUrl=QUEUE_URL,
    MaxNumberOfMessages=1,
    WaitTimeSeconds=20,
    # VisibilityTimeout 沒設 → 用 queue 預設值（通常 30 秒）
)

# ✅ 設定比任務最長執行時間更長的 visibility timeout
response = sqs.receive_message(
    QueueUrl=QUEUE_URL,
    MaxNumberOfMessages=1,
    WaitTimeSeconds=20,
    VisibilityTimeout=600,  # 10 分鐘，比 inference 最長時間更長
)

# ✅ 進階做法：處理途中延長 visibility timeout（heartbeat）
import threading

def heartbeat(receipt_handle: str, interval: int = 60):
    """每 60 秒延長 visibility timeout，避免任務未完成就過期"""
    while not stop_event.is_set():
        sqs.change_message_visibility(
            QueueUrl=QUEUE_URL,
            ReceiptHandle=receipt_handle,
            VisibilityTimeout=120,  # 再給 2 分鐘
        )
        stop_event.wait(interval)

stop_event = threading.Event()
hb_thread = threading.Thread(target=heartbeat, args=(receipt_handle,), daemon=True)
hb_thread.start()

try:
    result = run_long_inference(payload)  # 跑幾分鐘
    sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=receipt_handle)
finally:
    stop_event.set()  # 停止 heartbeat
```

> **Python 類比**：就像 `threading.Lock` 的 timeout 機制——如果你持有 lock 太久，別人的等待就會超時。Visibility timeout 就是 SQS 替你設的「你最多可以拿著這筆訊息多久」。

---

## Dead Letter Queue（DLQ）

DLQ 是「失敗訊息的垃圾桶」。當一筆訊息被取走並失敗超過 N 次（maxReceiveCount），就會自動移入 DLQ，不再重試。

```
正常 Queue
    │
    ├─→ Worker 處理成功 → delete → 結束
    │
    └─→ Worker 失敗（不刪除）
            │ (重試 maxReceiveCount 次後)
            ▼
        Dead Letter Queue（DLQ）
            │
            └─→ 人工審查 / 告警 / 重新處理
```

```python
# 設定 DLQ 的 boto3 範例（通常用 CloudFormation/Terraform，但可以用 SDK）
import json

# 1. 建立 DLQ
dlq = sqs.create_queue(QueueName="inference-jobs-dlq")
dlq_arn = sqs.get_queue_attributes(
    QueueUrl=dlq["QueueUrl"],
    AttributeNames=["QueueArn"]
)["Attributes"]["QueueArn"]

# 2. 建立主 queue，設定 redrive policy
sqs.create_queue(
    QueueName="inference-jobs",
    Attributes={
        "RedrivePolicy": json.dumps({
            "deadLetterTargetArn": dlq_arn,
            "maxReceiveCount": "3",  # 失敗 3 次後移入 DLQ
        }),
        "VisibilityTimeout": "600",
    }
)

# 3. 監控 DLQ — DLQ 有訊息代表有任務一直失敗
# 設定 CloudWatch alarm：DLQ 訊息數 > 0 就告警
```

---

## SQS Client 建立

SQS client 就是一個「能跟 SQS 溝通的 HTTP client」，建立它只是設定，不會佔用連線資源。

> **Python 類比**：就像建立 `boto3.client("sqs")`，只是設定 region 和 credentials，不會真正發出任何請求。
>
> ```python
> import boto3
>
> # 建立 client — 只是設定，不佔資源
> sqs = boto3.client("sqs", region_name="us-east-1")
>
> # 每次操作才真正發出 HTTPS request
> response = sqs.receive_message(QueueUrl="https://sqs.us-east-1.amazonaws.com/...")
> ```

---

## MD5 校驗與 FIPS 合規

### MD5 是什麼

MD5 (Message-Digest Algorithm 5) 是一種雜湊演算法，把任意長度的資料變成固定長度的 128-bit「指紋」。

```python
import hashlib

print(hashlib.md5(b"Hello World").hexdigest())
# → b10a8db164e0754105b7a99be72e3fe5

print(hashlib.md5(b"Hello World!").hexdigest())
# → ed076287532e86365e841e92bfc50d8c
# 只差一個驚嘆號，結果完全不同
```

### SQS 用 MD5 做什麼

SQS 預設對訊息內容算 MD5，用來驗證傳輸過程中訊息沒有被損壞或竄改：

```
送出端：訊息 "Hello" → 算 MD5 → 連同訊息一起送出
                                    ↓
SQS 收到後：重新算 MD5 → 跟送來的比對 → 一樣就 OK，不一樣就拒絕
```

```python
# Python 類比：就像傳檔案時附上 checksum 驗證完整性
import hashlib

message = b"inference result: {score: 0.95}"
checksum = hashlib.md5(message).hexdigest()

# 送出時附上 checksum
payload = {"body": message, "md5": checksum}

# 接收方驗證
received_body = payload["body"]
assert hashlib.md5(received_body).hexdigest() == payload["md5"], "訊息損壞！"
```

### 為什麼要關掉（`md5=False`）

FIPS (Federal Information Processing Standards) 是美國政府的資安標準，它**禁止使用 MD5**，因為 MD5 已被認為不夠安全（容易被碰撞攻擊破解）。

```
在 FIPS 模式的環境中：
SQS SDK 想算 MD5 → 系統說「MD5 被禁用了」→ 直接報錯 → 服務掛掉
```

```python
# ❌ FIPS 環境下這樣會報錯
import hashlib
hashlib.md5(b"data")  # ValueError: [digital envelope routines] unsupported

# ✅ 解法：告訴 SDK 不要用 MD5
# boto3 SQS 對應設定：
import boto3
from botocore.config import Config

sqs = boto3.client(
    "sqs",
    config=Config(
        # boto3 預設不做 MD5 校驗，FIPS 環境不需要特別設定
        # 如果用舊版 SDK 有問題，可考慮設定 FIPS endpoint
    ),
    endpoint_url="https://sqs-fips.us-east-1.amazonaws.com",  # FIPS endpoint
)
# 訊息完整性改由 TLS（HTTPS 傳輸加密）來保障
```

---

## 小結

| 概念 | 說明 | Inference System 要點 |
|---|---|---|
| Queue | 生產者和消費者的緩衝 | inference job 的標準排隊機制 |
| 訊息生命週期 | sent → in-flight → deleted/back | 未刪除的訊息會重回 queue |
| Visibility Timeout | 訊息被取走後隱藏多久 | **必須大於任務最長執行時間** |
| DLQ | 失敗訊息的垃圾桶 | 一定要設，否則爛訊息永遠重試 |
| MD5 開啟（預設） | SDK 自動做 checksum 驗證 | 一般環境沒問題 |
| MD5 關閉 | FIPS 合規環境必須關閉 | 改靠 TLS 保障完整性 |
