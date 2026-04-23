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
        // 裡面知道對錯，但外層完全感知不到
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

> **Python 類比**：行為完全一樣
> ```python
> # ❌ 沒有 await（Python 會直接報 warning）
> data = fetch_data()   # coroutine 物件，不是結果
>
> # ✅ 有 await
> data = await fetch_data()  # 實際結果
> ```

## 什麼時候需要自己寫 `new Promise`？

| 情況 | 需要自己包嗎 |
|---|---|
| 現代 library（axios, fetch 等） | 不用，直接 `await` |
| `async function` | 不用，自動回傳 Promise |
| 舊式 callback API | **要**，手動包 Promise |

大部分情況不用自己寫，只有遇到舊的 callback 風格 API 才需要包。

## Promise.all — 並行等多個

`Promise.all` 讓多個非同步操作同時跑，全部完成後才繼續：

```js
// ❌ 串行（慢）— 每個都等上一個完成
const user = await fetchUser(id);
const orders = await fetchOrders(id);
const settings = await fetchSettings(id);
// 花費時間 = A + B + C

// ✅ 並行（快）— 全部同時跑
const [user, orders, settings] = await Promise.all([
    fetchUser(id),
    fetchOrders(id),
    fetchSettings(id),
]);
// 花費時間 ≈ max(A, B, C)
```

**注意**：如果其中一個 reject，Promise.all 會立即 reject，其他的結果都丟掉。

> **Python 類比**：`asyncio.gather()`
> ```python
> import asyncio
>
> # 串行（慢）
> user = await fetch_user(id)
> orders = await fetch_orders(id)
>
> # 並行（快）— 等同 Promise.all
> user, orders, settings = await asyncio.gather(
>     fetch_user(id),
>     fetch_orders(id),
>     fetch_settings(id),
> )
> ```

## Promise.allSettled — 並行但不因錯誤中斷

`Promise.allSettled` 和 `Promise.all` 的差別：**即使某個失敗，也等全部跑完，不會提前 reject**。

```js
const results = await Promise.allSettled([
    fetchUser(id),
    fetchOrders(id),   // 假設這個失敗了
    fetchSettings(id),
]);

// results 是每個操作的結果物件陣列
results.forEach(result => {
    if (result.status === "fulfilled") {
        console.log("成功:", result.value);
    } else {
        console.log("失敗:", result.reason);
    }
});
```

| | `Promise.all` | `Promise.allSettled` |
|---|---|---|
| 其中一個失敗 | 立即 reject，其他結果丟棄 | 等全部跑完，每個都有結果 |
| 適合場景 | 全部成功才有意義的操作 | 部分失敗也要繼續處理的場景 |
| Python 類比 | `asyncio.gather()` | `asyncio.gather(return_exceptions=True)` |

> **Python 類比**：
> ```python
> # return_exceptions=True → 等同 Promise.allSettled
> results = await asyncio.gather(
>     fetch_user(id),
>     fetch_orders(id),
>     fetch_settings(id),
>     return_exceptions=True,  # 不因錯誤中斷，例外也當作結果回傳
> )
>
> for result in results:
>     if isinstance(result, Exception):
>         print("失敗:", result)
>     else:
>         print("成功:", result)
> ```

## Promise.race — 最快的那個贏

`Promise.race` 只等最快完成的那一個，不管成功還是失敗：

```js
// 實作 timeout：fetchData 或 5 秒 timeout，看誰先
const result = await Promise.race([
    fetchData(),
    new Promise((_, reject) =>
        setTimeout(() => reject(new Error("Timeout")), 5000)
    ),
]);
```

> **Python 類比**：`asyncio.wait` 搭配 `FIRST_COMPLETED`，或直接用 `asyncio.wait_for` 加 timeout：
> ```python
> import asyncio
>
> # timeout 版本
> try:
>     result = await asyncio.wait_for(fetch_data(), timeout=5.0)
> except asyncio.TimeoutError:
>     print("超時了")
>
> # 多個任務取最快的
> done, pending = await asyncio.wait(
>     [fetch_data(), other_task()],
>     return_when=asyncio.FIRST_COMPLETED,
> )
> # 取消未完成的
> for task in pending:
>     task.cancel()
> ```

## 錯誤處理

```js
// 方式 1：try/catch（推薦，接近 Python 習慣）
async function fetchUser(id) {
    try {
        const user = await db.query("SELECT * FROM users WHERE id = ?", [id]);
        return user;
    } catch (err) {
        console.error("查詢失敗:", err);
        throw err;  // 再往上拋
    }
}

// 方式 2：.catch() 鏈式
fetchUser(id)
    .then(user => console.log(user))
    .catch(err => console.error(err));

// 方式 3：async/await + .catch()（快速 default 值）
const user = await fetchUser(id).catch(() => null);
if (!user) return;
```

> **Python 類比**：
> ```python
> # try/except 完全一樣
> async def fetch_user(id):
>     try:
>         user = await db.query("SELECT * FROM users WHERE id = %s", (id,))
>         return user
>     except Exception as err:
>         print(f"查詢失敗: {err}")
>         raise
> ```

## 事件迴圈心智模型

JS 和 Python 都是**單執行緒 + 事件迴圈**，核心概念相同：

```
┌─────────────────────────────────────────────────────────┐
│                    事件迴圈（Event Loop）                  │
│                                                         │
│  Task Queue: [request1, request2, request3, ...]       │
│                    ↓                                    │
│  執行 request1                                          │
│    └── await fetchDB()  ← 發出 I/O，暫停 request1       │
│                    ↓                                    │
│  切換執行 request2（不用等 request1）                     │
│    └── await fetchCache()  ← 發出 I/O，暫停 request2    │
│                    ↓                                    │
│  DB 回應了 → 喚醒 request1，繼續執行                      │
└─────────────────────────────────────────────────────────┘
```

| | Node.js | Python asyncio |
|---|---|---|
| 執行緒數 | 單執行緒 | 單執行緒 |
| 切換時機 | 遇到 `await` | 遇到 `await` |
| I/O 機制 | libuv（底層） | 作業系統 epoll/kqueue |
| 真正並行 | Worker Threads | `asyncio.run_in_executor` / `ProcessPoolExecutor` |

**關鍵點**：`await` 不是等待，是「讓出控制權，讓事件迴圈去跑別的事」。CPU 密集運算不能靠 `await` 解決（因為 CPU 一直占著不讓出），需要用 Worker Threads（JS）或 ProcessPoolExecutor（Python）。

## Python 類比總覽

```python
# JS callback ≈ 把結果丟給 function，Python 很少這樣寫
def read_file(path, callback):
    data = do_read(path)
    callback(data)

# JS await ≈ Python await（幾乎完全一樣）
result = await aiohttp.post(url, json=body)

# Promise.all ≈ asyncio.gather()
results = await asyncio.gather(task1(), task2(), task3())

# Promise.allSettled ≈ asyncio.gather(return_exceptions=True)
results = await asyncio.gather(task1(), task2(), return_exceptions=True)

# Promise.race + timeout ≈ asyncio.wait_for()
result = await asyncio.wait_for(task(), timeout=5.0)
```
