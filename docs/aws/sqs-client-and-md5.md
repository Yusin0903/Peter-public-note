---
sidebar_position: 4
---

# SQS Client 基礎 & MD5/FIPS

## SQSClient

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

## MD5 是什麼

MD5 (Message-Digest Algorithm 5) 是一種雜湊演算法，把任意長度的資料變成固定長度的 128-bit「指紋」。

```python
import hashlib

print(hashlib.md5(b"Hello World").hexdigest())
# → b10a8db164e0754105b7a99be72e3fe5

print(hashlib.md5(b"Hello World!").hexdigest())
# → ed076287532e86365e841e92bfc50d8c
# 只差一個驚嘆號，結果完全不同
```

---

## SQS 用 MD5 做什麼

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

---

## 為什麼要關掉（`md5=False`）

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
        # 底層等同於 JS SDK 的 md5: false
        # boto3 預設不做 MD5 校驗，FIPS 環境不需要特別設定
    )
)
# 訊息完整性改由 TLS（HTTPS 傳輸加密）來保障
```

---

## 小結

| 設定 | 說明 |
|---|---|
| MD5 開啟（預設） | SDK 自動做 checksum 驗證，一般環境沒問題 |
| MD5 關閉 | FIPS 合規環境必須關閉，改靠 TLS 保障完整性 |
