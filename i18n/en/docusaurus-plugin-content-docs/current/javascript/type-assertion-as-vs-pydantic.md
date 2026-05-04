---
sidebar_position: 4
---

# TypeScript `as` Type Assertion vs Pydantic Validation

## `as` Type Assertion

Only tells the compiler "I believe this data looks like this" — performs zero validation:

```ts
const message = JSON.parse(rawJson) as TaskMessage;
// JSON.parse → converts string to JS object
// as TaskMessage → just tells TypeScript "treat this as this type"
//                 doesn't check the data, won't throw an error
```

```
rawJson = '{"taskId": "abc", "payload": {...}}'
                    ↓
JSON.parse → { taskId: "abc", payload: {...} }   ← plain JS object, no validation
                    ↓
as TaskMessage → TypeScript compiler believes it has taskId and payload fields
                 but if it actually doesn't, it only blows up at runtime
```

## Pydantic (Python)

Actually validates the data — throws an error if the format is wrong:

```python
class TaskMessage(BaseModel):
    taskId: str
    payload: Payload

# Validates! Missing fields or wrong types immediately raise ValidationError
message = TaskMessage.model_validate(json.loads(raw_json))
```

## Comparison

|              | TypeScript `as`               | Pydantic               |
|--------------|-------------------------------|------------------------|
| Validates data | No                          | Yes                    |
| Runtime protection | None                    | Yes                    |
| Effect       | Just stops the compiler complaining | Actually ensures data is correct |
| Analogy      | Sticking a label (ignores contents) | Going through security (rejects non-conforming data) |

## Want Pydantic-like Validation in TypeScript? Use zod

```ts
import { z } from "zod";

const TaskMessageSchema = z.object({
  taskId: z.string(),
  payload: PayloadSchema,
});

// This actually validates, similar to Pydantic
const message = TaskMessageSchema.parse(JSON.parse(rawJson));
```

**When to use `as` vs zod?**

| Scenario | Recommendation |
|----------|----------------|
| Message is from your own system, format is trusted | `as` is sufficient |
| Data from external API, user input | Use zod for validation |
