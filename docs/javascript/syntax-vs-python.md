---
sidebar_position: 3
---

# JS 語法對照（vs Python）

## 三元運算子（Ternary Operator）

```js
// JavaScript
let desc = format === 'csv' ? fileName : '';
//         條件              ? 成立值   : 不成立值

// Python
desc = file_name if format == 'csv' else ''
```

## `===` vs `==`

| 運算子 | 行為 | 建議 |
|---|---|---|
| `===`（strict） | 型別和值都要一樣 | JS 慣例幾乎都用這個 |
| `==`（loose） | 會自動轉型再比較 | 避免使用，容易踩坑 |

```js
1 === '1'   // false（型別不同）
1 == '1'    // true （'1' 被轉成 number）
0 == ''     // true  😱
0 == false  // true  😱
```

Python 的 `==` 不會自動轉型，沒有這個問題。

## `null` vs `undefined`

| | `null` | `undefined` |
|---|---|---|
| 意思 | 刻意設定為「沒有值」 | 未定義 / 沒有給值 |
| Python 類比 | `None` | 變數根本沒宣告 |

常用來佔位，讓後面的參數位置不會錯亂：

```js
sendRequest(command, userId, null, path, body, undefined);
//                            ^^^^                ^^^^^^^^^
//                            auth 不需要          callback 不需要
```
