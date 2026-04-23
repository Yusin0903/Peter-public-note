---
sidebar_position: 4
---

# TypeScript 型別系統 vs Python 型別系統

## TypeScript `as` 型別斷言

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

> **Python 類比**：`as` 斷言類似 Python 的 `cast()`，只騙型別檢查器，不做真正驗證：
> ```python
> from typing import cast
>
> data = json.loads(raw_json)
> message = cast(TaskMessage, data)  # mypy 相信它，但 runtime 完全不驗證
> ```

## Pydantic（Python）— 真的會驗證

真的會驗證資料，格式不對會報錯：

```python
class TaskMessage(BaseModel):
    taskId: str
    payload: Payload

# 會驗證！缺欄位或型別錯會馬上丟 ValidationError
message = TaskMessage.model_validate(json.loads(raw_json))
```

## TypeScript `as` vs Pydantic 比較

|              | TypeScript `as`          | Pydantic               |
|--------------|--------------------------|------------------------|
| 驗證資料     | 不會                     | 會                     |
| runtime 保護 | 沒有                     | 有                     |
| 效果         | 只讓編譯器不報錯         | 真的確保資料正確       |
| 類比         | 貼標籤（不管裡面是什麼） | 過安檢（不合格就拒絕） |

## Zod — TypeScript 的 Pydantic

Zod 是 TypeScript 生態中最接近 Pydantic 的 runtime 驗證函式庫：

```ts
import { z } from "zod";

// 定義 schema（類似 Pydantic BaseModel）
const TaskMessageSchema = z.object({
    taskId: z.string(),
    payload: z.object({
        type: z.string(),
        data: z.unknown(),
    }),
    priority: z.number().optional(),        // 可選欄位
    status: z.enum(["pending", "done"]),    // 列舉型別
    createdAt: z.string().datetime(),       // 格式驗證
});

// 推導出 TypeScript 型別（不用寫兩次）
type TaskMessage = z.infer<typeof TaskMessageSchema>;

// parse — 驗證失敗丟錯誤（類似 Pydantic model_validate）
const message = TaskMessageSchema.parse(JSON.parse(rawJson));

// safeParse — 驗證失敗回傳 result 物件，不丟錯誤
const result = TaskMessageSchema.safeParse(JSON.parse(rawJson));
if (!result.success) {
    console.error("驗證失敗:", result.error);
} else {
    const message = result.data;
}
```

> **Python 類比**：
> ```python
> from pydantic import BaseModel
> from typing import Optional, Literal
> from datetime import datetime
>
> class TaskMessage(BaseModel):
>     taskId: str
>     payload: dict
>     priority: Optional[int] = None          # 可選欄位
>     status: Literal["pending", "done"]       # 列舉型別
>     createdAt: datetime                      # 格式驗證
>
> # parse ≈ model_validate（驗證失敗丟 ValidationError）
> message = TaskMessage.model_validate(json.loads(raw_json))
>
> # safeParse ≈ model_validate + try/except
> try:
>     message = TaskMessage.model_validate(json.loads(raw_json))
> except ValidationError as e:
>     print(f"驗證失敗: {e}")
> ```

### Zod vs Pydantic 功能對照

| 功能 | Zod (TypeScript) | Pydantic (Python) |
|------|-----------------|-------------------|
| 定義 schema | `z.object({...})` | `class M(BaseModel): ...` |
| 字串 | `z.string()` | `str` |
| 數字 | `z.number()` | `int` / `float` |
| 可選 | `z.string().optional()` | `Optional[str]` |
| 列舉 | `z.enum(["a", "b"])` | `Literal["a", "b"]` |
| 驗證並丟錯誤 | `.parse(data)` | `.model_validate(data)` |
| 驗證回傳結果 | `.safeParse(data)` | `try/except ValidationError` |
| 推導型別 | `z.infer<typeof Schema>` | 直接就是型別（`M` 本身） |
| 自訂驗證 | `.refine(fn)` | `@field_validator` |

## 什麼時候用 `as`、什麼時候用 Zod？

| 情境 | 建議 |
|------|------|
| 訊息是自己系統送的，格式可以信任 | `as` 就夠了 |
| 資料來自外部 API、使用者輸入、Kafka message | 用 Zod 做驗證 |
| 只需要型別提示，不需要 runtime 保護 | `as` |
| 需要錯誤訊息、格式轉換、預設值 | 用 Zod |

## TypeScript Interface vs Python 型別定義方式

TypeScript 有多種定義「資料形狀」的方式，對應到 Python 也有多種選擇：

### TypeScript Interface

```ts
interface User {
    id: number;
    name: string;
    email?: string;    // 可選
}

// Interface 可以繼承
interface AdminUser extends User {
    role: "admin";
    permissions: string[];
}
```

> **Python 類比**：TypedDict（只有結構定義，不驗證）
> ```python
> from typing import TypedDict, Optional
>
> class User(TypedDict):
>     id: int
>     name: str
>     email: Optional[str]   # 可選
>
> class AdminUser(User):
>     role: Literal["admin"]
>     permissions: list[str]
> ```

### TypeScript Type Alias

```ts
type Status = "pending" | "success" | "failed";
type UserId = number;
type UserOrAdmin = User | AdminUser;
```

> **Python 類比**：
> ```python
> from typing import Literal, Union
>
> Status = Literal["pending", "success", "failed"]
> UserId = int
> UserOrAdmin = Union[User, AdminUser]
> ```

### Interface vs Type vs Zod vs Pydantic 選擇指南

| 工具 | 用途 | Runtime 驗證 | Python 對應 |
|------|------|-------------|-------------|
| TypeScript `interface` | 定義形狀，給編譯器用 | 沒有 | `TypedDict` / `Protocol` |
| TypeScript `type` | 型別別名、聯合型別 | 沒有 | `TypeAlias` |
| Zod | Schema 定義 + runtime 驗證 | 有 | Pydantic `BaseModel` |
| `as` 斷言 | 告訴編譯器「相信我」 | 沒有 | `cast()` |

**推論**：如果你在 Python 習慣用 Pydantic，在 TypeScript 就用 Zod。兩者幾乎是一一對應的。
