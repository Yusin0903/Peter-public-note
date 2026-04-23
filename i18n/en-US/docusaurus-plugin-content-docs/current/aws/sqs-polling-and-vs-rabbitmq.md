---
sidebar_position: 5
---

# SQS Polling & vs RabbitMQ

## SQS Handles Frequent Polling Fine

SQS is AWS fully managed and can handle nearly unlimited API calls per second:

```
Your worker polls every 5 seconds    → barely registers for SQS
Even 5 pods polling simultaneously   → only 1 request/sec each
SQS can handle                       → thousands of requests/sec+
```

> **Python analogy**: Your inference worker runs a `while True` loop constantly asking the queue for new tasks — SQS doesn't care about the frequency.

---

## Short Polling vs Long Polling

### Short Polling

```python
import boto3, time

sqs = boto3.client("sqs", region_name="us-east-1")
QUEUE_URL = "https://sqs.us-east-1.amazonaws.com/123456789/my-queue"

# Short Polling: responds immediately, returns empty if no messages
while True:
    response = sqs.receive_message(
        QueueUrl=QUEUE_URL,
        MaxNumberOfMessages=1,
        # No WaitTimeSeconds → short polling
    )
    messages = response.get("Messages", [])
    if messages:
        process(messages[0])
    else:
        time.sleep(5)  # no messages, wait 5s and ask again
```

```
Worker: Any messages?  →  SQS: Nope  →  returns immediately (empty)
Worker: sleep 5s
Worker: Any messages?  →  SQS: Nope  →  returns immediately
Worker: sleep 5s
Worker: Any messages?  →  SQS: Yes!  →  returns message
```

### Long Polling (one parameter to enable)

```python
# Long Polling: SQS waits for you, responds as soon as a message arrives (up to 20s)
while True:
    response = sqs.receive_message(
        QueueUrl=QUEUE_URL,
        MaxNumberOfMessages=1,
        WaitTimeSeconds=20,   # ← add this for long polling
    )
    messages = response.get("Messages", [])
    if messages:
        process(messages[0])
    # No sleep needed — SQS already waited
```

```
Worker: Any messages? (I'll wait up to 20 seconds)
                     ↓
              SQS waiting...
              SQS waiting...
              Message arrived at second 8! → returns immediately
```

### Long Polling Benefits

- **More real-time**: messages received the moment they arrive, no sleep delay
- **Cheaper**: fewer empty API calls (SQS charges per request count)

```python
# Cost comparison (assuming queue is mostly empty):
# Short Polling: every 5s = 17,280 API calls/day (mostly empty)
# Long Polling:  only counts when a message actually arrives → far fewer API calls
```

---

## SQS vs RabbitMQ

| | RabbitMQ (Push) | SQS (Poll) |
|---|---|---|
| Latency | Near real-time (~1ms) | Short Poll: up to 5s / Long Poll: near real-time |
| Throughput | Limited by connections | Nearly unlimited |
| Ops cost | You manage it | Zero |

```python
# Python analogy:

# RabbitMQ (Push) = callback-based, broker pushes to you when message arrives
import pika
channel.basic_consume(queue="tasks", on_message_callback=process_message)
channel.start_consuming()  # broker pushes actively

# SQS (Poll) = you ask, like queue.get()
import queue
task_queue = queue.Queue()
while True:
    task = task_queue.get(timeout=20)  # wait up to 20s
    process(task)
```

---

## When to Choose Which

| Scenario | Recommendation |
|----------|----------------|
| Inference tasks (minute-scale processing, latency-insensitive) | SQS — no queue server to maintain |
| Need near-instant low latency (< 10ms) | RabbitMQ — push mode is more immediate |
| Need unlimited horizontal scaling | SQS — AWS handles it |
| AWS-native architecture | SQS — native integration with IAM, Lambda, CloudWatch |

```python
# Your Python inference system is a natural fit for SQS Long Polling:
# 1. Inference itself takes seconds to minutes — 10ms latency difference is negligible
# 2. No RabbitMQ cluster to maintain
# 3. Native AWS integration, IAM permissions are straightforward

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
