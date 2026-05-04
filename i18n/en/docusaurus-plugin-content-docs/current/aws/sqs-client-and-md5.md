---
sidebar_position: 4
---

# SQS Client Basics & MD5/FIPS

## SQSClient

An SQS client is just an "HTTP client that can talk to SQS." Creating it is just configuration — no connection overhead.

> **Python analogy**: Like creating `boto3.client("sqs")` — just sets region and credentials, no actual request is sent.
>
> ```python
> import boto3
>
> # Creating the client — just config, no resource usage
> sqs = boto3.client("sqs", region_name="us-east-1")
>
> # Each operation sends an actual HTTPS request
> response = sqs.receive_message(QueueUrl="https://sqs.us-east-1.amazonaws.com/...")
> ```

---

## What Is MD5

MD5 (Message-Digest Algorithm 5) is a hashing algorithm that turns data of any length into a fixed 128-bit "fingerprint."

```python
import hashlib

print(hashlib.md5(b"Hello World").hexdigest())
# → b10a8db164e0754105b7a99be72e3fe5

print(hashlib.md5(b"Hello World!").hexdigest())
# → ed076287532e86365e841e92bfc50d8c
# One character difference, completely different result
```

---

## What SQS Uses MD5 For

SQS computes MD5 of message content by default to verify nothing was corrupted or tampered with during transmission:

```
Sender: message "Hello" → compute MD5 → send both together
                                           ↓
SQS receives: recompute MD5 → compare → match = OK, mismatch = reject
```

```python
# Python analogy: like attaching a checksum when sending a file
import hashlib

message = b"inference result: {score: 0.95}"
checksum = hashlib.md5(message).hexdigest()

payload = {"body": message, "md5": checksum}

# Receiver verifies
received_body = payload["body"]
assert hashlib.md5(received_body).hexdigest() == payload["md5"], "Message corrupted!"
```

---

## Why Disable It (`md5=False`)

FIPS (Federal Information Processing Standards) is a US government security standard that **prohibits MD5** because it is considered insecure (vulnerable to collision attacks).

```
In a FIPS-mode environment:
SQS SDK tries to compute MD5 → system says "MD5 is banned" → throws error → service crashes
```

```python
# ❌ In FIPS environments this throws
import hashlib
hashlib.md5(b"data")  # ValueError: [digital envelope routines] unsupported

# ✅ Solution: tell the SDK not to use MD5
# boto3's SQS client doesn't do MD5 verification by default,
# so FIPS environments don't need special configuration.
# Message integrity is instead provided by TLS (HTTPS transport encryption).
```

---

## Summary

| Setting | Behaviour |
|---|---|
| MD5 enabled (default) | SDK auto-verifies checksum — fine for standard environments |
| MD5 disabled | Required for FIPS-compliant environments; TLS handles integrity instead |
