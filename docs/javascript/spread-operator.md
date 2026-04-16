---
sidebar_position: 5
---

# Spread Operator（`...` 展開運算子）

`...` 是 JavaScript/TypeScript 的 spread operator（展開運算子）。
它把一個物件的所有屬性「攤平」複製到另一個物件裡。

## 範例：合併設定物件

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

## 覆蓋屬性

後面的屬性會覆蓋前面的：

```ts
const base = { color: "red", size: "M", weight: 100 };
const override = { ...base, color: "blue" };  // color 被覆蓋
// → { color: "blue", size: "M", weight: 100 }
```

## Python 等價寫法

```python
# Python 用 ** 做一樣的事
base = create_base_config()
aws_config = {
    **base,           # ← 等同 JS 的 ...
    "type": "aws",
    "region": "us-east-1",
}
```

就是 Python 的 `**dict` 解包，只是 JS/TS 用 `...` 這個符號。
