---
sidebar_position: 5
---

# SQS Polling & vs RabbitMQ

## SQS Handles Frequent Polling Fine

SQS is an AWS fully managed service that can handle nearly unlimited API calls per second:

```
Your worker polls every 5 seconds    → barely registers for SQS
Even 5 pods polling simultaneously   → only 1 request/sec each
SQS can handle                       → thousands of requests/sec+
```

## Short Polling vs Long Polling

### Short Polling

```
Worker: Any messages?  →  SQS: Nope  →  returns immediately
Worker: sleep 5s
Worker: Any messages?  →  SQS: Nope  →  returns immediately
Worker: sleep 5s
Worker: Any messages?  →  SQS: Yes!  →  returns message
```

### Long Polling (one parameter to enable)

```
Worker: Any messages? (I'll wait up to 20 seconds)
                     ↓
              SQS waiting...
              SQS waiting...
              A message arrived at second 8! → returns immediately
```

```ts
// Just add WaitTimeSeconds to enable Long Polling
new ReceiveMessageCommand({
  QueueUrl: url,
  MaxNumberOfMessages: 1,
  WaitTimeSeconds: 20,     // ← add this
});
```

### Long Polling Benefits

- More real-time — messages are received as soon as they arrive, no waiting for sleep
- Cheaper — fewer empty API calls (SQS charges per request count)

## SQS vs RabbitMQ

|          | RabbitMQ (Push)  | SQS (Poll) |
|----------|------------------|------------|
| Latency  | Near real-time (~1ms) | Short Poll: up to 5s / Long Poll: near real-time |
| Throughput | Limited by connections | Nearly unlimited |
| Ops cost | You manage it | Zero |

## When to Choose Which

| Scenario | Recommendation |
|----------|----------------|
| Long-running tasks (minutes), latency-insensitive | SQS — no queue server to maintain |
| Need near-instant low latency (< 10ms) | RabbitMQ — push mode is more immediate |
| Need unlimited horizontal scaling | SQS — AWS handles it |
| AWS-native architecture | SQS — native integration with IAM, Lambda, CloudWatch |

The trade-off with SQS is eliminating queue server maintenance and scaling concerns — suitable for most task-processing scenarios.
