---
sidebar_position: 3
---

# Dynamically Fetching Service Tokens from DynamoDB

## Concept

Store the token in DynamoDB so services can read it dynamically at runtime, rather than hardcoding it in environment variables.

```ts
const serviceTokenProvider = new ServiceTokenProvider({
  ddbClient,
  tableName: `my-service-${config.env}-config`,
  //                        ↑
  //          config.env = "prod" → "my-service-prod-config"
});
```

## Why a Service Token Is Needed

When a worker sends data to an external API, it needs a token to prove its identity:

```
Worker wants to call external API
  │
  │ "Who are you? Show me a token"
  │
  ▼
serviceTokenProvider.getServiceToken()
  │
  │ Query DynamoDB for config
  │
  ▼
Get token → attach token to API call → send request
```

## Why Not Just Put the Token in an Environment Variable?

| Approach | Pros | Cons |
|----------|------|------|
| Environment variable | Simple | Rotating the token requires redeploying the Pod |
| DynamoDB | Dynamic read | Rotating the token only requires updating the DB, no redeploy |

Tokens may be rotated periodically. Storing in DynamoDB means the token can be swapped without restarting the service.

## Implementation Pattern

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

Every time a token is needed, the latest value is read from DynamoDB. After token rotation, no service restart is required.
