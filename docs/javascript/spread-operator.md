---
sidebar_position: 5
---

# Spread Operator（`...` 展開運算子）

`...` 是 JavaScript/TypeScript 的 spread operator（展開運算子）。
它把一個物件或陣列的所有內容「攤平」複製到另一個物件或陣列裡。

> **Python 類比**：JS 的 `...` = Python 的 `**`（dict）或 `*`（list）

## 物件展開：合併設定物件

假設你有一個基礎設定，想在某個子類別加上額外欄位：

```ts
const createAwsConfig = (): AwsConfig => {
  return {
    ...createBaseConfig(),  // 把共用設定全部展開放進來
    type: "aws",            // 再加上 AWS 專屬的欄位
    region: "us-east-1",
  };
};
```

等於：

```js
// createBaseConfig() 回傳：
{
  env: "prod",
  db: { host: "...", port: 3306 },
  redis: { url: "..." },
  logLevel: "info",
}

// 加上 ...展開後，最終結果變成：
{
  env: "prod",              // ← 從 spread 來的
  db: { host: "..." },     // ← 從 spread 來的
  redis: { url: "..." },   // ← 從 spread 來的
  logLevel: "info",        // ← 從 spread 來的
  type: "aws",             // ← 新加的
  region: "us-east-1",    // ← 新加的
}
```

> **Python 類比**：
> ```python
> # Python 用 ** 做一樣的事
> base = create_base_config()
> aws_config = {
>     **base,           # ← 等同 JS 的 ...
>     "type": "aws",
>     "region": "us-east-1",
> }
> ```

## 覆蓋屬性

後面的屬性會覆蓋前面的：

```ts
const base = { color: "red", size: "M", weight: 100 };
const override = { ...base, color: "blue" };
// → { color: "blue", size: "M", weight: 100 }
```

> **Python 類比**：
> ```python
> base = {"color": "red", "size": "M", "weight": 100}
> override = {**base, "color": "blue"}
> # → {"color": "blue", "size": "M", "weight": 100}
> ```

## 陣列展開

`...` 也可以用在陣列（Python 的 `*`）：

```js
const a = [1, 2, 3];
const b = [4, 5, 6];

// 合併陣列
const merged = [...a, ...b];
// → [1, 2, 3, 4, 5, 6]

// 在特定位置插入
const withExtra = [0, ...a, 3.5, ...b, 7];
// → [0, 1, 2, 3, 3.5, 4, 5, 6, 7]

// 複製陣列（淺複製）
const copy = [...a];
```

> **Python 類比**：
> ```python
> a = [1, 2, 3]
> b = [4, 5, 6]
>
> merged = [*a, *b]           # 合併
> with_extra = [0, *a, 3.5, *b, 7]
> copy = [*a]                 # 淺複製，等同 a.copy()
> ```

## Rest 參數（收集剩餘）

`...` 也用來收集「剩餘的」元素（這時叫 rest parameter）：

```ts
// 函式：收集不定數量的參數
function sum(...numbers: number[]): number {
    return numbers.reduce((acc, n) => acc + n, 0);
}
sum(1, 2, 3, 4);  // → 10

// 解構：收集剩餘屬性
const { name, age, ...rest } = { name: "Alice", age: 30, city: "Taipei", job: "Engineer" };
// name="Alice", age=30, rest={city:"Taipei", job:"Engineer"}

// 陣列解構：收集剩餘元素
const [first, second, ...tail] = [1, 2, 3, 4, 5];
// first=1, second=2, tail=[3,4,5]
```

> **Python 類比**：
> ```python
> # 函式收集剩餘位置參數
> def sum_all(*numbers):
>     return sum(numbers)
> sum_all(1, 2, 3, 4)  # → 10
>
> # 序列拆包收集剩餘
> first, second, *tail = [1, 2, 3, 4, 5]
> # first=1, second=2, tail=[3,4,5]
>
> # dict 沒有直接的 rest destructuring，但可以這樣模擬：
> data = {"name": "Alice", "age": 30, "city": "Taipei"}
> name = data.pop("name")
> age = data.pop("age")
> rest = data  # 剩下的
> ```

## 淺複製 vs 深複製注意事項

Spread 只做**淺複製**（shallow copy）：

```ts
const original = { a: 1, nested: { b: 2 } };
const copy = { ...original };

copy.a = 99;            // ✅ 不影響 original
copy.nested.b = 99;     // ❌ 影響 original！（nested 是同一個參考）

console.log(original.nested.b);  // → 99
```

> **Python 類比**：Python 的 `{**d}` 和 `dict.copy()` 也是淺複製，行為完全相同：
> ```python
> import copy
>
> original = {"a": 1, "nested": {"b": 2}}
> shallow = {**original}           # 淺複製
> deep = copy.deepcopy(original)   # 深複製
>
> shallow["nested"]["b"] = 99      # 影響 original！
> deep["nested"]["b"] = 99         # 不影響 original
> ```

## 實際用途總覽

```ts
// 1. 不可變更新（Immutable update）— 推薦寫法
const newState = { ...oldState, count: oldState.count + 1 };

// 2. 合併多個設定
const config = { ...defaults, ...userConfig, ...envOverrides };

// 3. 函式呼叫展開陣列
Math.max(...numbers);   // 等同 Python 的 max(*numbers)

// 4. 複製再修改（避免直接改原物件）
const updatedUser = { ...user, name: "Bob" };
```

> **Python 類比**：
> ```python
> # 1. 不可變更新
> new_state = {**old_state, "count": old_state["count"] + 1}
>
> # 2. 合併多個設定（後面的 key 覆蓋前面的）
> config = {**defaults, **user_config, **env_overrides}
>
> # 3. 函式呼叫展開
> max(*numbers)
>
> # 4. 複製再修改
> updated_user = {**user, "name": "Bob"}
> ```
