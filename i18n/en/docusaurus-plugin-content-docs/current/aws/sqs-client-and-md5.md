---
sidebar_position: 4
---

# SQS Client Basics & MD5/FIPS

## SQSClient

```typescript
const sqsClient = new SQSClient({ md5: false });
```

This is the AWS SDK's low-level SQS client — essentially an "HTTP client that can talk to SQS."

- `md5: false` is needed because FIPS environments don't support MD5; disabling it prevents errors.
- The client itself only makes HTTP calls, no business logic included.

## What Is MD5

MD5 (Message-Digest Algorithm 5) is a hashing algorithm that turns data of any length into a fixed 128-bit "fingerprint."

```
"Hello World"  → MD5 → b10a8db164e0754105b7a99be72e3fe5
"Hello World!" → MD5 → ed076287532e86365e841e92bfc50d8c
                        ↑ one character difference, completely different result
```

## What SQS Uses MD5 For

SQS computes MD5 of message content by default to verify the message wasn't corrupted or tampered with during transmission:

```
Sender: message "Hello" → compute MD5 → send both together
                                           ↓
SQS receives: recompute MD5 → compare → match = OK, mismatch = reject
```

## Why Disable It (md5: false)

FIPS (Federal Information Processing Standards) is a US government security standard that prohibits MD5 because it is considered insecure (vulnerable to collision attacks).

```
In a FIPS-mode environment:
SQS SDK tries to compute MD5 → system says "MD5 is banned" → throws error → service crashes
```

Setting `md5: false` tells the SDK "don't compute MD5," allowing it to work in FIPS environments. Message integrity is then handled by TLS (HTTPS transport encryption).
