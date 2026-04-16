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

## Short Polling vs Long Polling

### Short Polling

```
Worker: 有訊息嗎？  →  SQS: 沒有  →  馬上回應
Worker: sleep 5秒
Worker: 有訊息嗎？  →  SQS: 沒有  →  馬上回應
Worker: sleep 5秒
Worker: 有訊息嗎？  →  SQS: 有！  →  回傳訊息
```

### Long Polling（加一個參數就能開）

```
Worker: 有訊息嗎？（我最多等 20 秒）
                     ↓
              SQS 等待中...
              SQS 等待中...
              第 8 秒有訊息進來了！ → 馬上回傳
```

```ts
// 只要加 WaitTimeSeconds 就能開啟 Long Polling
new ReceiveMessageCommand({
  QueueUrl: url,
  MaxNumberOfMessages: 1,
  WaitTimeSeconds: 20,     // ← 加這個
});
```

### Long Polling 的好處

- 更即時 — 訊息一進 queue 就能拿到，不用等 sleep
- 更省錢 — 減少空的 API call 次數（SQS 按 request 數量計費）

## SQS vs RabbitMQ

|          | RabbitMQ (Push)  | SQS (Poll) |
|----------|------------------|------------|
| 延遲     | 幾乎即時（~1ms） | Short Poll: 最慢 5 秒 / Long Poll: 幾乎即時 |
| 吞吐量   | 受限於連線數     | 幾乎無限 |
| 運維成本 | 要自己管         | 零 |

## 什麼時候選哪個

| 情境 | 建議 |
|------|------|
| 任務處理時間長（分鐘級），延遲不敏感 | SQS — 省去 queue server 維運 |
| 需要幾乎即時的低延遲（< 10ms） | RabbitMQ — Push 模式更即時 |
| 需要無限水平擴展 | SQS — AWS 幫你扛 |
| 雲端 AWS 架構 | SQS — 原生整合 IAM、Lambda、CloudWatch |

SQS 換來的是不用管 queue server、不用擔心擴縮，適合大部分的任務處理場景。
