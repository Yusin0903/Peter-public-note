---
sidebar_position: 5
---

# SQS Polling 模式 & vs RabbitMQ

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
        MaxNumberOfMessages=1,
        WaitTimeSeconds=20,   # ← 加這個就是 long polling
    )
    messages = response.get("Messages", [])
    if messages:
        process(messages[0])
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

## SQS vs RabbitMQ

| | RabbitMQ (Push) | SQS (Poll) |
|---|---|---|
| 延遲 | 幾乎即時（~1ms） | Short Poll: 最慢 5 秒 / Long Poll: 幾乎即時 |
| 吞吐量 | 受限於連線數 | 幾乎無限 |
| 運維成本 | 要自己管 | 零 |

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
| Inference 任務（分鐘級處理時間，延遲不敏感） | SQS — 省去 queue server 維運 |
| 需要幾乎即時的低延遲（< 10ms） | RabbitMQ — Push 模式更即時 |
| 需要無限水平擴展 | SQS — AWS 幫你扛 |
| 雲端 AWS 架構 | SQS — 原生整合 IAM、Lambda、CloudWatch |

```python
# 你的 Python inference system 最適合 SQS Long Polling：
# 1. inference 本身就要幾秒到幾分鐘，10ms 延遲差距可以忽略
# 2. 不用自己維護 RabbitMQ cluster
# 3. AWS 原生整合，IAM 權限管理很方便

class InferenceWorker:
    def __init__(self, queue_url: str):
        self.sqs = boto3.client("sqs")
        self.queue_url = queue_url

    def run(self):
        while True:
            resp = self.sqs.receive_message(
                QueueUrl=self.queue_url,
                MaxNumberOfMessages=1,
                WaitTimeSeconds=20,   # long polling
            )
            for msg in resp.get("Messages", []):
                self.handle(msg)
                self.sqs.delete_message(
                    QueueUrl=self.queue_url,
                    ReceiptHandle=msg["ReceiptHandle"],
                )
```
