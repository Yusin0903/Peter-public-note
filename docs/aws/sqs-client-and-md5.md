---
sidebar_position: 4
---

# SQS Client 基礎 & MD5/FIPS

## SQSClient

```typescript
const sqsClient = new SQSClient({ md5: false });
```

這是 AWS SDK 提供的底層 SQS 客戶端，就是一個「能跟 SQS 溝通的 HTTP client」。

- `md5: false` 是因為 FIPS 環境不支援 MD5，關掉才不會報錯。
- 它本身只會做 HTTP call，不帶任何業務邏輯。

## MD5 是什麼

MD5 (Message-Digest Algorithm 5) 是一種雜湊演算法，把任意長度的資料變成一個固定長度的 128-bit「指紋」。

```
"Hello World"  → MD5 → b10a8db164e0754105b7a99be72e3fe5
"Hello World!" → MD5 → ed076287532e86365e841e92bfc50d8c
                        ↑ 只差一個字，結果完全不同
```

## SQS 用 MD5 做什麼

SQS 預設會對訊息內容算 MD5，用來驗證傳輸過程中訊息沒有被損壞或竄改：

```
送出端：訊息 "Hello" → 算 MD5 → 連同訊息一起送出
                                    ↓
SQS 收到後：重新算 MD5 → 跟送來的比對 → 一樣就 OK，不一樣就拒絕
```

## 為什麼要關掉（md5: false）

FIPS (Federal Information Processing Standards) 是美國政府的資安標準，它禁止使用 MD5，因為 MD5 已經被認為不夠安全（容易被碰撞攻擊破解）。

```
在 FIPS 模式的環境中：
SQS SDK 想算 MD5 → 系統說「MD5 被禁用了」→ 直接報錯 → 服務掛掉
```

所以設 `md5: false` 就是跟 SDK 說「不要算 MD5 了」，讓它能在 FIPS 環境正常運作。訊息完整性改由 TLS（HTTPS 傳輸加密）來保障。
