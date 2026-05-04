---
sidebar_position: 2
---

# Promise & async/await

## Why Do We Need Promises?

Early JS used callbacks for async operations, but results were trapped inside the callback — the outer scope couldn't access them:

```js
// callback style — outer scope can't get the result
function upload() {
    runRestAPI(..., function(err, data) {
        // knows success/failure in here
    });
    // outer scope doesn't know, can't tell if it succeeded or failed
}
```

Promises let the outer scope `await` the result:

```js
// Promise style — outer scope can receive the result
async function upload() {
    let result = await new Promise((resolve) => {
        runRestAPI(..., (err, data) => resolve({ err, data }));
    });
    if (result.err) { /* outer scope knows it failed */ }
}
```

## How `await` Behaves

- `await` must be followed by a Promise
- `await` waits for the async operation to complete, but **doesn't block the whole server** — other requests keep being handled
- Without `await`, you get `Promise { <pending> }` — a shell, not the actual result

```js
// ❌ no await
let data = fetchData();   // Promise { <pending> }

// ✅ with await
let data = await fetchData();  // actual result
```

## When Do You Need to Write `new Promise` Yourself?

| Situation | Need to wrap? |
|-----------|---------------|
| Modern library (axios, fetch, etc.) | No, just `await` it |
| `async function` | No, automatically returns a Promise |
| Old-style callback API | **Yes**, wrap manually |

Most of the time you don't need to write it yourself — only when dealing with legacy callback-style APIs.

## Python Analogy

```python
# JS callback ≈ passing results to a function, no return (rare in Python)
def read_file(path, callback):
    data = do_read(path)
    callback(data)

# JS await ≈ Python await
result = await aiohttp.post(url, json=body)
```
