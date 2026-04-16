---
sidebar_position: 2
---

# Promise & async/await

## 為什麼需要 Promise？

JS 早期只有 callback 風格處理非同步，結果被鎖在 callback 裡面，外層拿不到：

```js
// callback 風格 — 外層拿不到結果
function upload() {
    runRestAPI(..., function(err, data) {
        // 裡面知道對錯
    });
    // 外面拿不到，不知道成功還失敗
}
```

Promise 讓外層可以用 `await` 等結果：

```js
// Promise 風格 — 外層可以接結果
async function upload() {
    let result = await new Promise((resolve) => {
        runRestAPI(..., (err, data) => resolve({ err, data }));
    });
    if (result.err) { /* 外層知道錯了 */ }
}
```

## await 的行為

- `await` 後面一定要接 Promise
- `await` 會等這個非同步操作完成，但**不會卡住整個 server**，其他 request 照常處理
- 不寫 `await` 的話，拿到的是 `Promise { <pending> }` 空殼，不是實際結果

```js
// ❌ 沒有 await
let data = fetchData();   // Promise { <pending> }

// ✅ 有 await
let data = await fetchData();  // 實際結果
```

## 什麼時候需要自己寫 `new Promise`？

| 情況 | 需要自己包嗎 |
|---|---|
| 現代 library（axios, fetch 等） | 不用，直接 `await` |
| `async function` | 不用，自動回傳 Promise |
| 舊式 callback API | **要**，手動包 Promise |

大部分情況不用自己寫，只有遇到舊的 callback 風格 API 才需要包。

## Python 類比

```python
# JS callback ≈ 把結果丟給 function，沒有 return（Python 很少這樣寫）
def read_file(path, callback):
    data = do_read(path)
    callback(data)

# JS await ≈ Python await
result = await aiohttp.post(url, json=body)
```
