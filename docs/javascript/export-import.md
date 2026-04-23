---
sidebar_position: 1
---

# export / import 模組系統

## 基本概念：JS 預設 private，Python 預設 public

`export` 就是「讓這個函式可以被外部 import」。

```js
// 有 export → 外部可以 import
export const createUserRepo = () => { ... };
// import { createUserRepo } from "..." ✅

// 沒有 export → 只有這個檔案內部能用
const helperFunction = () => { ... };
// import { helperFunction } from "..." ❌ 找不到
```

> **Python 類比**：Python 預設全部都是 public，JS/TS 預設是 private，要加 `export` 才能被 import。
> Python 用 `_` 前綴當作「不建議外部用」的慣例，但不會真的擋住 import。

| | JavaScript/TypeScript | Python |
|---|---|---|
| 預設可見性 | 私有（需加 `export`） | 公開 |
| 限制外部存取 | 不加 `export` | 加 `_` 前綴（慣例） |
| 強制封裝 | 不加 `export` 就真的擋住 | 無法強制，只是慣例 |

## Named Export vs Default Export

JS 有兩種 export 方式，這是 Python 沒有的概念：

### Named Export（最常用）

```ts
// 一個檔案可以有多個 named export
export const createUserRepo = () => { ... };
export const createOrderRepo = () => { ... };
export type UserRepoOptions = { ... };

// import 時要用 {} 包起來，名稱要完全對上
import { createUserRepo, createOrderRepo } from "./repos";
```

> **Python 類比**：
> ```python
> # repos.py
> def create_user_repo(): ...
> def create_order_repo(): ...
>
> # main.py
> from repos import create_user_repo, create_order_repo
> ```
> 兩個幾乎一模一樣，只是 JS 要加 `export` 關鍵字。

### Default Export（一個檔案只能有一個）

```ts
// 一個檔案只能有一個 default export
export default class UserService { ... }

// import 時不用 {}，名稱可以自己取
import UserService from "./user-service";
import WhateverName from "./user-service";  // 也可以，同一個東西
```

> **Python 類比**：Python 沒有「default export」的概念，最接近的是把主要的 class 放在模組最上層，然後直接 import 整個模組：
> ```python
> # user_service.py
> class UserService: ...
>
> # main.py
> from user_service import UserService
> ```

### 混用範例（實際 codebase 常見）

```ts
// config.ts
export default class Config { ... }        // default export
export const DEFAULT_TIMEOUT = 5000;       // named export
export type ConfigOptions = { ... };       // named export（type）

// 使用端
import Config, { DEFAULT_TIMEOUT, type ConfigOptions } from "./config";
//     ^^^^^^  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
//     default  named
```

## Re-export（轉出口）

常見模式：用一個 `index.ts` 把多個模組集中管理，讓外部只需要從一個地方 import：

```ts
// repos/index.ts — 把內部模組全部集中轉出
export { createUserRepo } from "./user-repo";
export { createOrderRepo } from "./order-repo";
export type { UserRepo, OrderRepo } from "./types";

// 外部使用，不用知道內部結構
import { createUserRepo, createOrderRepo } from "./repos";
```

> **Python 類比**：
> ```python
> # repos/__init__.py
> from .user_repo import create_user_repo
> from .order_repo import create_order_repo
>
> # 外部使用
> from repos import create_user_repo, create_order_repo
> ```
> 兩者概念完全一樣！JS 的 `index.ts` = Python 的 `__init__.py`。

## Type-only Import（TypeScript 專屬）

```ts
// 只 import 型別，不會產生 runtime 程式碼
import type { UserRepo } from "./user-repo";

// 混合 import
import { createUserRepo, type UserRepo } from "./user-repo";
```

這對打包工具有優化效果：知道這個 import 只是型別，打包時可以安全移除。

> **Python 類比**：
> ```python
> from typing import TYPE_CHECKING
> if TYPE_CHECKING:
>     from user_repo import UserRepo  # 只在型別檢查時 import，runtime 不執行
> ```

## 常見路徑寫法

```ts
import { foo } from "./foo";         // 相對路徑（同目錄）
import { foo } from "../utils/foo";  // 相對路徑（上一層）
import { foo } from "@/utils/foo";   // 絕對路徑（@ 通常對應到 src/）
import { EventEmitter } from "events";     // node_modules 套件
import EventEmitter from "node:events";    // Node.js 內建模組（node: 前綴）
```

> **Python 類比**：
> ```python
> from .foo import foo            # 相對 import
> from ..utils.foo import foo     # 上一層相對 import
> from utils.foo import foo       # 絕對 import（加入 PYTHONPATH）
> import asyncio                  # 標準函式庫
> ```
