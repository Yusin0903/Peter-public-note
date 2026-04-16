---
sidebar_position: 3
---

# 從 DynamoDB 動態取得 Service Token

## 概念

把 token 存在 DynamoDB，讓服務在 runtime 動態讀取，而不是寫死在環境變數裡。

```ts
const serviceTokenProvider = new ServiceTokenProvider({
  ddbClient,
  tableName: `my-service-${config.env}-config`,
  //                        ↑
  //          config.env = "prod" → "my-service-prod-config"
});
```

## 為什麼需要 Service Token

Worker 送資料到外部 API 時，需要一個 token 證明身份：

```
Worker 要呼叫外部 API
  │
  │ 「你是誰？給我看 token」
  │
  ▼
serviceTokenProvider.getServiceToken()
  │
  │ 去 DynamoDB 查 config 設定
  │
  ▼
拿到 token → 帶著 token 呼叫 API → 送出請求
```

## 為什麼不直接把 token 放環境變數？

| 方式 | 優點 | 缺點 |
|---|---|---|
| 環境變數 | 簡單 | 換 token 要重新部署 Pod |
| DynamoDB | 動態讀取 | 換 token 只要改 DB，不用重新部署 |

Token 可能會定期輪換（rotate），放 DynamoDB 就能不重啟服務的情況下換掉 token。

## 實作模式

```ts
class ServiceTokenProvider {
  constructor(private readonly ddbClient: DynamoDBClient, private readonly tableName: string) {}

  async getServiceToken(): Promise<string> {
    const result = await this.ddbClient.send(
      new GetItemCommand({
        TableName: this.tableName,
        Key: { id: { S: 'service_token' } },
      }),
    );
    return result.Item?.token?.S ?? '';
  }
}
```

這樣每次需要 token 時都是從 DynamoDB 讀取最新值，token 輪換後不需要重啟服務。
