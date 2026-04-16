---
sidebar_position: 1
---

# export / import 模組系統

`export` 就是「讓這個函式可以被外部 import」。

```js
// 有 export → 外部可以 import
export const createUserRepo = () => { ... };
// import { createUserRepo } from "..." ✅

// 沒有 export → 只有這個檔案內部能用
const helperFunction = () => { ... };
// import { helperFunction } from "..." ❌ 找不到
```

## Python 等價

Python 預設全部都是 public，JS/TS 預設是 private，要加 `export` 才能被 import。

| | JavaScript/TypeScript | Python |
|---|---|---|
| 預設可見性 | 私有（需加 `export`） | 公開 |
| 限制外部存取 | 不加 `export` | 加 `_` 前綴（慣例） |
