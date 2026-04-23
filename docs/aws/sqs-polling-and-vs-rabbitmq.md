---
sidebar_position: 5
---

# SQS 深度指南：Polling、可靠性保證與 RabbitMQ 比較

---

## SQS 不怕頻繁拉取

SQS 是 AWS 全託管服務，每秒能處理幾乎無限量的 API call：

```
你的 Worker 每 5 秒拉一次    → 對 SQS 來說根本不算什麼
就算 5 個 Pod 同時拉          → 每秒也才 1 次 request
SQS 能承受的                  → 每秒數千次以上
```

> **Python 類比**：就像你的 inference worker 用 `while True` loop 不斷問 queue 有沒有新任務，SQS 完全不在乎這個頻率。

---

## Short Polling vs Long Polling

### Short Polling

```python
import boto3
import time

sqs = boto3.client("sqs", region_name="us-east-1")
QUEUE_URL = "https://sqs.us-east-1.amazonaws.com/123456789/my-queue"

# Short Polling：馬上回應，沒有訊息也立刻返回空值
while True:
    response = sqs.receive_message(
        QueueUrl=QUEUE_URL,
        MaxNumberOfMessages=1,
        # 沒有 WaitTimeSeconds → short polling
    )
    messages = response.get("Messages", [])
    if messages:
        process(messages[0])
    else:
        time.sleep(5)  # 沒訊息就等 5 秒再問
```

```
Worker: 有訊息嗎？  →  SQS: 沒有  →  馬上回應（空值）
Worker: sleep 5 秒
Worker: 有訊息嗎？  →  SQS: 沒有  →  馬上回應
Worker: sleep 5 秒
Worker: 有訊息嗎？  →  SQS: 有！  →  回傳訊息
```

### Long Polling（加一個參數就能開）

```python
# Long Polling：SQS 幫你等，有訊息才回應（最多等 20 秒）
while True:
    response = sqs.receive_message(
        QueueUrl=QUEUE_URL,
        MaxNumberOfMessages=10,       # 一次最多拿 10 筆，提高吞吐量
        WaitTimeSeconds=20,           # ← 加這個就是 long polling
    )
    messages = response.get("Messages", [])
    if messages:
        process_batch(messages)
    # 不需要 sleep，SQS 已經幫你等了
```

```
Worker: 有訊息嗎？（我最多等 20 秒）
                     ↓
              SQS 等待中...
              SQS 等待中...
              第 8 秒有訊息進來了！→ 馬上回傳
```

### Long Polling 的好處

- **更即時**：訊息一進 queue 就能拿到，不用等 sleep 間隔
- **更省錢**：減少空的 API call 次數（SQS 按 request 數量計費）

```python
# 費用比較（假設 queue 大多是空的）：
# Short Polling：每 5 秒一次 = 每天 17,280 次 API call（大部分是空的）
# Long Polling：有訊息才真正算一次 = 大幅減少 API call 費用
```

---

## 訊息去重複（Standard Queue vs FIFO Queue）

SQS 有兩種 Queue 類型，對 inference system 的影響非常不同：

### Standard Queue（預設）

```
特性：
├── 幾乎無限吞吐量
├── At-least-once delivery（可能重複送達）← 重要！
└── Best-effort ordering（不保證順序）
```

### FIFO Queue

```
特性：
├── 保證順序（First-In-First-Out）
├── Exactly-once delivery（不重複）← 但有 TPS 限制
├── 最高 3,000 TPS（帶 batching 的情況）
└── 需要在訊息中加 MessageDeduplicationId
```

```python
# FIFO Queue 的去重複：同樣 MessageDeduplicationId 的訊息，
# 在 5 分鐘內只會被 deliver 一次
sqs.send_message(
    QueueUrl="https://sqs.us-east-1.amazonaws.com/123/my-queue.fifo",
    MessageBody=json.dumps({"job_id": "job_001", "payload": "..."}),
    MessageGroupId="inference-jobs",       # 同一 group 內保證順序
    MessageDeduplicationId="job_001",      # 同樣 ID 的訊息 5 分鐘內不重複
)

# Standard Queue 的去重複：沒有原生支援，需要自己做
# 通常用 DynamoDB conditional write：
try:
    table.put_item(
        Item={"job_id": "job_001", "status": "processing"},
        ConditionExpression="attribute_not_exists(job_id)",
    )
    # 成功 → 這是第一次處理，繼續
    run_inference(payload)
except ClientError as e:
    if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
        # 已經處理過，跳過（SQS 重複送達了同一筆訊息）
        logger.info("Duplicate message detected, skipping")
```

---

## At-Least-Once Delivery 與冪等性（Idempotency）

**Standard Queue 保證 at-least-once，不保證 exactly-once。** 這代表你的 inference handler 可能收到同一筆訊息兩次。

> **Python 類比**：就像你的函式可能被呼叫兩次，你必須確保呼叫兩次和一次的結果相同。
>
> ```python
> # ❌ 非冪等：呼叫兩次會計費兩次、結果不同
> def process_payment(amount):
>     charge_credit_card(amount)  # 被呼叫兩次 → 扣款兩次！
>
> # ✅ 冪等：呼叫兩次和一次的最終狀態相同
> def process_payment(amount, idempotency_key):
>     if payment_already_done(idempotency_key):
>         return "already processed"
>     charge_credit_card(amount)
>     mark_as_done(idempotency_key)
> ```

```python
# Inference handler 的冪等性設計
import boto3
from botocore.exceptions import ClientError
import json

dynamodb = boto3.resource("dynamodb")
results_table = dynamodb.Table("inference-results")

def idempotent_inference_handler(sqs_message: dict) -> None:
    """
    冪等的 inference handler：
    同一個 job_id 不管被呼叫幾次，只會真正執行一次推理。
    """
    body = json.loads(sqs_message["Body"])
    job_id = body["job_id"]

    # 嘗試用 conditional write 搶「處理權」
    try:
        results_table.put_item(
            Item={"job_id": job_id, "status": "processing"},
            ConditionExpression="attribute_not_exists(job_id)",
        )
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            # 這個 job 已經被另一個 worker 處理（或正在處理）
            # 直接刪除這筆 SQS 訊息，不重複執行
            return
        raise

    # 到這裡代表我們拿到了這個 job 的「鎖」
    try:
        result = run_inference(body["payload"])  # 實際推理
        results_table.update_item(
            Key={"job_id": job_id},
            UpdateExpression="SET #s = :done, result = :result",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={
                ":done": "done",
                ":result": result,
            },
        )
    except Exception:
        # 推理失敗，把 DynamoDB 的狀態改回去，讓 SQS 重試
        results_table.delete_item(Key={"job_id": job_id})
        raise  # 不刪除 SQS 訊息 → visibility timeout 後重試
```

---

## 完整的 InferenceWorker 實作

這是一個生產等級的 InferenceWorker，包含：
- Long polling
- Visibility timeout heartbeat
- 正確的 error handling
- DLQ awareness
- 冪等性

```python
import boto3
import json
import logging
import signal
import threading
import time
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)


class InferenceWorker:
    """
    生產等級的 SQS Inference Worker。

    特性：
    - Long polling：減少 API call 費用
    - Visibility timeout heartbeat：避免長任務被重新投遞
    - 優雅關閉（graceful shutdown）：SIGTERM 後等當前任務完成
    - DLQ awareness：記錄 ApproximateReceiveCount 方便除錯
    """

    def __init__(
        self,
        queue_url: str,
        visibility_timeout: int = 600,   # 10 分鐘，inference 任務要夠長
        max_messages: int = 1,           # inference 通常一次處理一筆
        region: str = "us-east-1",
    ):
        self.sqs = boto3.client("sqs", region_name=region)
        self.queue_url = queue_url
        self.visibility_timeout = visibility_timeout
        self.max_messages = max_messages
        self._running = True

        # 設定 SIGTERM handler（K8s 停止 Pod 時發送）
        signal.signal(signal.SIGTERM, self._handle_shutdown)
        signal.signal(signal.SIGINT, self._handle_shutdown)

    def _handle_shutdown(self, signum, frame):
        logger.info("收到停止訊號，等待當前任務完成後退出...")
        self._running = False

    def run(self):
        """主迴圈：持續拉取並處理訊息"""
        logger.info(f"InferenceWorker 啟動，監聽：{self.queue_url}")

        while self._running:
            try:
                response = self.sqs.receive_message(
                    QueueUrl=self.queue_url,
                    MaxNumberOfMessages=self.max_messages,
                    WaitTimeSeconds=20,                    # long polling
                    VisibilityTimeout=self.visibility_timeout,
                    AttributeNames=["ApproximateReceiveCount"],  # DLQ 除錯用
                )

                for msg in response.get("Messages", []):
                    self._process_message(msg)

            except Exception as e:
                logger.error(f"Polling 發生錯誤：{e}")
                time.sleep(5)  # 短暫等待後重試，避免錯誤循環

        logger.info("InferenceWorker 已優雅關閉")

    def _process_message(self, msg: dict):
        """處理單筆訊息，包含 heartbeat 和 error handling"""
        receipt_handle = msg["ReceiptHandle"]
        receive_count = int(msg.get("Attributes", {}).get("ApproximateReceiveCount", 1))

        # 如果訊息已經重試多次，記錄警告（可能即將進入 DLQ）
        if receive_count > 2:
            logger.warning(
                f"訊息重試次數偏高（{receive_count} 次），"
                f"MessageId={msg['MessageId']}，可能即將移入 DLQ"
            )

        # 啟動 heartbeat：每 60 秒延長 visibility timeout
        stop_heartbeat = threading.Event()
        heartbeat_thread = threading.Thread(
            target=self._heartbeat,
            args=(receipt_handle, stop_heartbeat),
            daemon=True,
        )
        heartbeat_thread.start()

        try:
            body = json.loads(msg["Body"])
            logger.info(f"開始處理 job_id={body.get('job_id')}")

            self.handle(body)  # 子類別覆寫這個方法

            # 成功才刪除訊息
            self.sqs.delete_message(
                QueueUrl=self.queue_url,
                ReceiptHandle=receipt_handle,
            )
            logger.info(f"成功處理並刪除訊息，job_id={body.get('job_id')}")

        except Exception as e:
            logger.error(
                f"處理訊息失敗（receive_count={receive_count}）：{e}",
                exc_info=True,
            )
            # 不刪除訊息 → visibility timeout 後重回 queue → 重試
            # 超過 maxReceiveCount 後自動移入 DLQ

        finally:
            stop_heartbeat.set()  # 停止 heartbeat

    def _heartbeat(self, receipt_handle: str, stop_event: threading.Event):
        """定期延長 visibility timeout，避免長任務被重新投遞"""
        heartbeat_interval = self.visibility_timeout // 2  # 一半時間就延長

        while not stop_event.wait(heartbeat_interval):
            try:
                self.sqs.change_message_visibility(
                    QueueUrl=self.queue_url,
                    ReceiptHandle=receipt_handle,
                    VisibilityTimeout=self.visibility_timeout,
                )
                logger.debug("Visibility timeout 已延長")
            except ClientError as e:
                # 如果訊息已被刪除或過期，這裡會報錯，直接停止
                logger.warning(f"Heartbeat 失敗（訊息可能已被刪除）：{e}")
                break

    def handle(self, body: dict):
        """覆寫這個方法實作你的 inference 邏輯"""
        raise NotImplementedError


# 使用方式：繼承並實作 handle()
class MyInferenceWorker(InferenceWorker):
    def handle(self, body: dict):
        job_id = body["job_id"]
        image_url = body["image_url"]

        # 實際推理邏輯
        result = run_model(image_url)

        # 儲存結果到 S3 或 DynamoDB
        save_result(job_id, result)


if __name__ == "__main__":
    worker = MyInferenceWorker(
        queue_url="https://sqs.us-east-1.amazonaws.com/123456789/inference-jobs",
        visibility_timeout=600,  # 10 分鐘
    )
    worker.run()
```

---

## SQS vs RabbitMQ

| | RabbitMQ (Push) | SQS (Poll) |
|---|---|---|
| 延遲 | 幾乎即時（~1ms） | Short Poll: 最慢 5 秒 / Long Poll: 幾乎即時 |
| 吞吐量 | 受限於連線數 | 幾乎無限 |
| 運維成本 | 要自己管 | 零 |
| 去重複 | 靠 broker 保證 | Standard: 需自己實作；FIFO: 原生支援 |
| 訊息順序 | 可設定 | Standard: 不保證；FIFO: 保證 |

```python
# Python 類比：

# RabbitMQ (Push) = callback-based，訊息進來 broker 主動推給你
# 像 asyncio event loop 的 callback
import pika
channel.basic_consume(queue="tasks", on_message_callback=process_message)
channel.start_consuming()  # broker 主動推

# SQS (Poll) = 你主動問，像 queue.get()
import queue
task_queue = queue.Queue()
while True:
    task = task_queue.get(timeout=20)  # 等最多 20 秒
    process(task)
```

---

## 什麼時候選哪個

| 情境 | 建議 |
|---|---|
| Inference 任務（分鐘級處理時間，延遲不敏感） | **SQS — 首選**，省去 queue server 維運 |
| 需要幾乎即時的低延遲（< 10ms） | RabbitMQ — Push 模式更即時 |
| 需要無限水平擴展 | SQS — AWS 幫你扛 |
| 雲端 AWS 架構 | SQS — 原生整合 IAM、Lambda、CloudWatch |
| 需要複雜 routing（exchange、binding） | RabbitMQ — SQS 的 routing 非常簡單 |

**結論：對 Python inference system，永遠選 SQS + Long Polling。** Inference 任務本身就要幾秒到幾分鐘，1ms vs 100ms 的延遲差距可以完全忽略。你的時間應該花在模型優化，不是 queue server 維運。
