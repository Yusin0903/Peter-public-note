---
sidebar_position: 3
---

# JS 語法對照（vs Python）

快速對照表，讓 Python 開發者一眼看懂 JS/TS 語法。

## 變數宣告：let / const vs 直接賦值

```js
// JavaScript — 需要關鍵字
let x = 10;         // 可以重新賦值
const y = 20;       // 不能重新賦值（物件內部屬性還是可以改）
var z = 30;         // 舊式，有 function scope 問題，現在避免用

// TypeScript — 可以加型別
let name: string = "Alice";
const count: number = 42;
```

> **Python 類比**：
> ```python
> x = 10          # Python 直接賦值，沒有 let/const 概念
> y = 20          # Python 沒有 const，慣例用全大寫 CONSTANT = 20
> ```

| | JavaScript/TypeScript | Python |
|---|---|---|
| 可變變數 | `let x = 10` | `x = 10` |
| 常數 | `const x = 10`（真的不能重新賦值） | `X = 10`（只是慣例，不強制） |
| 廢棄寫法 | `var`（避免使用） | — |

## 箭頭函式 vs lambda / def

```js
// JavaScript 箭頭函式
const add = (a, b) => a + b;               // 單行，自動 return
const greet = (name) => `Hello, ${name}`;  // 單行
const process = (x) => {                   // 多行，需要明確 return
    const result = x * 2;
    return result;
};

// 也可以用傳統 function
function add(a, b) { return a + b; }
```

> **Python 類比**：
> ```python
> add = lambda a, b: a + b          # 單行 lambda，等同 JS 單行箭頭函式
> greet = lambda name: f"Hello, {name}"
>
> def process(x):                   # 多行用 def，等同 JS 多行箭頭函式
>     result = x * 2
>     return result
> ```

**重要差異**：JS `lambda` 可以多行（用 `{}`），Python `lambda` 只能單行。

## 解構賦值 vs 拆包（Unpacking）

```js
// 陣列解構
const [first, second, ...rest] = [1, 2, 3, 4, 5];
// first=1, second=2, rest=[3,4,5]

// 物件解構
const { name, age, ...others } = { name: "Alice", age: 30, city: "Taipei" };
// name="Alice", age=30, others={city:"Taipei"}

// 函式參數解構（非常常見！）
function greet({ name, age }) {
    console.log(`${name} is ${age}`);
}

// 重新命名
const { name: userName, age: userAge } = user;
```

> **Python 類比**：
> ```python
> # 序列拆包
> first, second, *rest = [1, 2, 3, 4, 5]
> # first=1, second=2, rest=[3,4,5]
>
> # dict 沒有直接的「解構」，通常這樣寫：
> user = {"name": "Alice", "age": 30, "city": "Taipei"}
> name, age = user["name"], user["age"]
>
> # 函式參數 dict 拆包（Python 較少這樣寫，通常用 **kwargs 或明確參數）
> def greet(name, age):
>     print(f"{name} is {age}")
> greet(**user)  # 展開 dict 當關鍵字參數
> ```

## Optional Chaining `?.` vs `getattr`

當你不確定某個值是否存在，想安全地存取深層屬性時：

```js
// ❌ 沒有 optional chaining — 可能 TypeError
const city = user.address.city;

// ✅ 有 optional chaining — 不存在時回傳 undefined
const city = user?.address?.city;
const len = user?.name?.length;

// 也可以用在函式呼叫
const result = obj?.method?.();

// 搭配陣列
const first = arr?.[0];
```

> **Python 類比**：
> ```python
> # getattr 加 default 值
> city = getattr(getattr(user, "address", None), "city", None)
>
> # 或用 try/except（Python 常見寫法）
> try:
>     city = user.address.city
> except AttributeError:
>     city = None
>
> # 如果用 dict，用 .get()
> city = user.get("address", {}).get("city")
> ```
> JS 的 `?.` 比 Python 的任何替代方案都簡潔許多。

## Nullish Coalescing `??` vs `or`

```js
// ?? — 只有 null 或 undefined 時才用預設值
const name = user.name ?? "Anonymous";
const timeout = config.timeout ?? 5000;

// 注意：?? 和 || 不同！
const value1 = 0 ?? "default";    // 0     （0 不是 null/undefined）
const value2 = 0 || "default";    // "default"（0 是 falsy）
const value3 = "" ?? "default";   // ""    （空字串不是 null/undefined）
const value4 = "" || "default";   // "default"（空字串是 falsy）
```

> **Python 類比**：
> ```python
> # Python 的 or 類似 JS 的 ||（falsy 就用預設值）
> name = user.name or "Anonymous"   # 空字串也會用預設值！
>
> # Python 沒有 ?? 的直接等價，要模擬 ?? 的行為：
> name = user.name if user.name is not None else "Anonymous"
>
> # 或用 walrus operator（Python 3.8+）
> name = x if (x := user.name) is not None else "Anonymous"
> ```
> **JS `??` 比 Python `or` 更嚴格**：只有 `null`/`undefined` 才觸發，不會被 `0`、`""` 觸發。

## Template Literals vs f-string

```js
const name = "Alice";
const age = 30;

// JavaScript template literal（用反引號 `）
const msg = `Hello, ${name}! You are ${age} years old.`;
const multiline = `
  第一行
  第二行
  第三行
`;

// 也可以嵌入表達式
const result = `${a} + ${b} = ${a + b}`;
const upper = `Name: ${name.toUpperCase()}`;
```

> **Python 類比**：
> ```python
> name = "Alice"
> age = 30
>
> # Python f-string（幾乎完全一樣）
> msg = f"Hello, {name}! You are {age} years old."
> multiline = """
>   第一行
>   第二行
>   第三行
> """
>
> result = f"{a} + {b} = {a + b}"
> upper = f"Name: {name.upper()}"
> ```
> 語法幾乎一樣，只是 JS 用反引號 `` ` ``，Python 用引號加 `f` 前綴。

## for...of vs for 迴圈

```js
// for...of — 遍歷值（最常用）
for (const item of items) {
    console.log(item);
}

// 搭配 entries() 取 index
for (const [index, item] of items.entries()) {
    console.log(index, item);
}

// for...in — 遍歷物件的 key（注意：不是用來遍歷陣列）
for (const key in obj) {
    console.log(key, obj[key]);
}
```

> **Python 類比**：
> ```python
> # for...of ≈ Python for
> for item in items:
>     print(item)
>
> # entries() ≈ enumerate()
> for index, item in enumerate(items):
>     print(index, item)
>
> # for...in 遍歷物件 key ≈ 遍歷 dict
> for key in obj:
>     print(key, obj[key])
> ```

## 三元運算子（Ternary Operator）

```js
// JavaScript — 條件 ? 成立值 : 不成立值
let desc = format === 'csv' ? fileName : '';
```

> **Python 類比**：
> ```python
> desc = file_name if format == 'csv' else ''
> ```

## `===` vs `==`

| 運算子 | 行為 | 建議 |
|---|---|---|
| `===`（strict） | 型別和值都要一樣 | JS 慣例幾乎都用這個 |
| `==`（loose） | 會自動轉型再比較 | 避免使用，容易踩坑 |

```js
1 === '1'   // false（型別不同）
1 == '1'    // true （'1' 被轉成 number）
0 == ''     // true  ← 陷阱
0 == false  // true  ← 陷阱
```

> **Python 類比**：Python 的 `==` 不會自動轉型，沒有這個問題。Python 的 `==` 等同 JS 的 `===`。

## `null` vs `undefined`

| | `null` | `undefined` |
|---|---|---|
| 意思 | 刻意設定為「沒有值」 | 未定義 / 沒有給值 |
| Python 類比 | `None` | 變數根本沒宣告 |

```js
// 常用來佔位，讓後面的參數位置不會錯亂
sendRequest(command, userId, null, path, body, undefined);
//                            ^^^^                ^^^^^^^^^
//                            auth 不需要          callback 不需要
```

> **Python 類比**：Python 只有 `None`，沒有「已宣告但沒值」的概念。Python 函式通常用 `None` 當預設值達到類似效果：
> ```python
> def send_request(command, user_id, auth=None, path=None, body=None, callback=None):
>     ...
> ```

## 型別宣告（TypeScript 專屬）

```ts
// 基本型別
let name: string = "Alice";
let count: number = 42;
let active: boolean = true;
let data: any = "anything";      // 任意型別（像 Python 不加型別標注）

// 複合型別
let ids: number[] = [1, 2, 3];
let pair: [string, number] = ["Alice", 30];  // tuple

// 物件型別（interface）
interface User {
    id: number;
    name: string;
    email?: string;    // ? 表示可選欄位
}

// 聯合型別
let result: string | null = null;
let status: "pending" | "success" | "failed" = "pending";  // 字串 literal 型別
```

> **Python 類比**：
> ```python
> from typing import Optional, Union, Literal
>
> name: str = "Alice"
> count: int = 42
> active: bool = True
> data: Any = "anything"
>
> ids: list[int] = [1, 2, 3]
> pair: tuple[str, int] = ("Alice", 30)
>
> # TypeScript interface ≈ Python dataclass 或 TypedDict
> from dataclasses import dataclass
> @dataclass
> class User:
>     id: int
>     name: str
>     email: Optional[str] = None
>
> result: Optional[str] = None
> status: Literal["pending", "success", "failed"] = "pending"
> ```

## 語法總覽對照表

| 概念 | JavaScript/TypeScript | Python |
|---|---|---|
| 變數宣告 | `let x = 10` / `const x = 10` | `x = 10` |
| 常數 | `const MAX = 100` | `MAX = 100`（慣例） |
| 單行函式 | `(x) => x * 2` | `lambda x: x * 2` |
| 多行函式 | `(x) => { ... return ... }` | `def f(x): ...` |
| 解構賦值 | `const [a, b] = arr` | `a, b = arr` |
| 物件解構 | `const { x, y } = obj` | `x, y = obj["x"], obj["y"]` |
| 安全屬性存取 | `obj?.prop?.sub` | `getattr(obj, "prop", None)` |
| 預設值（嚴格） | `x ?? "default"` | `x if x is not None else "default"` |
| 預設值（falsy） | `x \|\| "default"` | `x or "default"` |
| 字串插值 | `` `Hello ${name}` `` | `f"Hello {name}"` |
| 迴圈 | `for (const x of arr)` | `for x in arr:` |
| 帶 index 迴圈 | `for (const [i, x] of arr.entries())` | `for i, x in enumerate(arr):` |
| 遍歷物件 key | `for (const k in obj)` | `for k in obj:` |
| 三元運算子 | `cond ? a : b` | `a if cond else b` |
| 嚴格相等 | `===` | `==` |
| Null 型態 | `null` / `undefined` | `None` |
| 型別標注 | `name: string` | `name: str` |
| 可選欄位 | `email?: string` | `email: Optional[str] = None` |
