---
sidebar_position: 4
---

# TypeScript `as` 型別斷言 vs Pydantic 驗證

## `as` 型別斷言

只是告訴編譯器「我相信這個資料長這樣」，完全不會做驗證：

```ts
const message = JSON.parse(rawJson) as TaskMessage;
// JSON.parse → 把字串變成 JS 物件
// as TaskMessage → 只是告訴 TypeScript「幫我當作這個型別」
//                 不會檢查資料對不對，不會報錯
```

```
rawJson = '{"taskId": "abc", "payload": {...}}'
                    ↓
JSON.parse → { taskId: "abc", payload: {...} }   ← 純 JS 物件，沒有驗證
                    ↓
as TaskMessage → TypeScript 編譯器相信它有 taskId 和 payload 欄位
                 但如果實際沒有，runtime 才會爆
```

## Pydantic（Python）

真的會驗證資料，格式不對會報錯：

```python
class TaskMessage(BaseModel):
    taskId: str
    payload: Payload

# 會驗證！缺欄位或型別錯會馬上丟 ValidationError
message = TaskMessage.model_validate(json.loads(raw_json))
```

## 比較

|              | TypeScript `as`          | Pydantic               |
|--------------|--------------------------|------------------------|
| 驗證資料     | 不會                     | 會                     |
| runtime 保護 | 沒有                     | 有                     |
| 效果         | 只讓編譯器不報錯         | 真的確保資料正確       |
| 類比         | 貼標籤（不管裡面是什麼） | 過安檢（不合格就拒絕） |

## TypeScript 要做到像 Pydantic 一樣？用 zod

```ts
import { z } from "zod";

const TaskMessageSchema = z.object({
  taskId: z.string(),
  payload: PayloadSchema,
});

// 這樣才會真的驗證，類似 Pydantic
const message = TaskMessageSchema.parse(JSON.parse(rawJson));
```

**什麼時候用 `as`、什麼時候用 zod？**

| 情境 | 建議 |
|------|------|
| 訊息是自己系統送的，格式可以信任 | `as` 就夠了 |
| 資料來自外部 API、使用者輸入 | 用 zod 做驗證 |
