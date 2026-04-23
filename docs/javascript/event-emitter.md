---
sidebar_position: 6
---

# EventEmitter 事件系統

EventEmitter 是 Node.js 的內建模組，不需要另外安裝。

```js
import EventEmitter from "node:events";  // node: 前綴代表是 Node.js 內建
```

## 基本用法

一個簡單的事件發布/訂閱系統：

```js
const emitter = new EventEmitter();

// 訂閱：聽到 "process" 事件就執行這個 function
emitter.on("process", () => {
  console.log("收到事件了！");
});

// 發布：觸發 "process" 事件
emitter.emit("process");
// → 印出 "收到事件了！"
```

> **Python 類比**：最接近的是簡單的 observer pattern（手刻），或第三方套件 `blinker`：
> ```python
> # 手刻版（最接近 EventEmitter 的結構）
> class EventEmitter:
>     def __init__(self):
>         self.listeners = {}
>
>     def on(self, event, callback):
>         self.listeners.setdefault(event, []).append(callback)
>
>     def emit(self, event, *args, **kwargs):
>         for cb in self.listeners.get(event, []):
>             cb(*args, **kwargs)
>
> emitter = EventEmitter()
> emitter.on("process", lambda: print("收到事件了！"))
> emitter.emit("process")
> ```

## 事件名稱是動態的

事件不需要預先定義，它是動態的。你 `emit` 什麼字串，`on` 監聽什麼字串，就配對上了。

```js
emitter.on("taskComplete", async () => { ... });
emitter.emit("taskComplete");

emitter.on("pizza", () => console.log("好吃"));
emitter.emit("pizza");  // → "好吃"
```

> **Python 類比**：就像 Python 的 dict，key 不用預先定義：
> ```python
> listeners = {}
> listeners["process"] = some_function
> listeners["shutdown"] = another_function
> ```

## `on` vs `once`

`once` 跟 `on` 的差別只有一個：只執行一次。

```js
// on — 每次 emit 都會執行
emitter.on("tick", () => console.log("hi"));
emitter.emit("tick");  // → "hi"
emitter.emit("tick");  // → "hi"（無限次）

// once — 只執行第一次，之後自動取消註冊
emitter.once("shutdown", () => console.log("bye"));
emitter.emit("shutdown");    // → "bye"
emitter.emit("shutdown");    // → （沒反應了）
```

> **Python 類比**：`threading.Event` 的 `wait()` 搭配 `set()` 可以做到類似的一次性觸發：
> ```python
> import threading
>
> shutdown_event = threading.Event()
>
> def on_shutdown():
>     shutdown_event.wait()   # 等待直到 set()
>     print("bye")
>
> threading.Thread(target=on_shutdown).start()
> shutdown_event.set()        # 觸發一次，之後 wait() 不再阻塞
> ```

## 傳遞資料給事件 handler

```js
// emit 時可以傳參數
emitter.on("jobDone", (jobId, result) => {
    console.log(`Job ${jobId} 完成，結果：${result}`);
});

emitter.emit("jobDone", "job-123", { status: "success" });
```

> **Python 類比**：
> ```python
> def on_job_done(job_id, result):
>     print(f"Job {job_id} 完成，結果：{result}")
>
> emitter.on("jobDone", on_job_done)
> emitter.emit("jobDone", "job-123", {"status": "success"})
> ```

## 用 EventEmitter 實現無限迴圈

用 EventEmitter 來做無限迴圈，比 `while (true)` 更容易控制並行和優雅關機：

```js
// 用 EventEmitter 的做法
emitter.on("process", async () => {
  await this.processNextJob();
  emitter.emit("process");  // 做完後再觸發自己
});
emitter.emit("process");    // 啟動第一次
```

> **Python 類比**：等價的 Python while 迴圈
> ```python
> async def run_loop():
>     while not should_exit:
>         await self.process_next_job()
> ```
> 用 EventEmitter 的好處是可以方便地啟動多條並行迴圈和優雅關機。

## 移除監聽器

```js
const handler = () => console.log("hi");

emitter.on("tick", handler);
// ... 之後想移除
emitter.off("tick", handler);         // 移除特定 handler
emitter.removeAllListeners("tick");   // 移除所有 tick 的 handler
emitter.removeAllListeners();         // 移除所有事件的所有 handler
```

> **Python 類比**（手刻版）：
> ```python
> emitter.listeners["tick"].remove(handler)
> emitter.listeners.pop("tick", None)
> emitter.listeners.clear()
> ```

## Python pubsub 模式對照

Python 有幾種常見的 pub/sub 方式，各有適用場景：

### threading.Event — 簡單的一次性信號

```python
import threading

event = threading.Event()

# 等待信號（blocking）
def worker():
    event.wait()        # 阻塞直到 set()
    print("收到信號，開始工作")

t = threading.Thread(target=worker)
t.start()

event.set()             # 發送信號
event.clear()           # 重置（可以再次 wait）
```

適合：執行緒間的一次性或可重置信號。不適合多個 listener。

### asyncio.Event — 協程版本

```python
import asyncio

event = asyncio.Event()

async def worker():
    await event.wait()  # 非阻塞等待
    print("收到信號")

async def main():
    asyncio.create_task(worker())
    await asyncio.sleep(1)
    event.set()         # 觸發所有等待的協程

asyncio.run(main())
```

適合：asyncio 環境中協程間的同步。

### 簡單 Observer Pattern — 最接近 EventEmitter

```python
from collections import defaultdict
from typing import Callable

class EventEmitter:
    def __init__(self):
        self._listeners: dict[str, list[Callable]] = defaultdict(list)

    def on(self, event: str, callback: Callable):
        self._listeners[event].append(callback)

    def once(self, event: str, callback: Callable):
        def wrapper(*args, **kwargs):
            callback(*args, **kwargs)
            self.off(event, wrapper)
        self._listeners[event].append(wrapper)

    def off(self, event: str, callback: Callable):
        self._listeners[event].remove(callback)

    def emit(self, event: str, *args, **kwargs):
        for cb in self._listeners[event][:]:  # 複製一份避免 iteration 問題
            cb(*args, **kwargs)
```

### blinker — Python 較正式的 pub/sub 套件

```python
from blinker import signal

# 定義信號
task_done = signal("task-done")

# 訂閱
@task_done.connect
def on_task_done(sender, job_id, result):
    print(f"任務完成: {job_id}")

# 發送
task_done.send(None, job_id="job-123", result={"status": "success"})
```

### 各方案比較

| 方案 | 適用場景 | 多個 listener | async 支援 |
|------|---------|--------------|-----------|
| `threading.Event` | 執行緒間信號 | 不適合 | 否 |
| `asyncio.Event` | 協程間同步 | 不適合 | 是 |
| 手刻 Observer | 一般 pub/sub | 是 | 需自己實作 |
| `blinker` | Python 正式 pub/sub | 是 | 部分 |
| Node.js `EventEmitter` | Node.js 各處 | 是 | 是（async handler） |

## EventEmitter vs 直接呼叫函式

什麼時候該用 EventEmitter，什麼時候直接呼叫函式？

```
直接呼叫（適合）：
  A 知道要呼叫 B，且 A 和 B 是緊密耦合的
  例：controller 呼叫 service

EventEmitter（適合）：
  A 不知道（也不在乎）誰會處理
  多個地方需要對同一件事做反應
  例：job 完成後要通知 logger、webhook、cache 更新...
```

```js
// ❌ 直接呼叫 — 耦合太緊
class JobWorker {
    async processJob(job) {
        await job.run();
        await logger.log(job.id);          // JobWorker 要知道 logger
        await webhookService.notify(job);  // JobWorker 要知道 webhookService
        await cacheService.invalidate(job);// JobWorker 要知道 cacheService
    }
}

// ✅ EventEmitter — 解耦
class JobWorker {
    async processJob(job) {
        await job.run();
        this.emit("jobComplete", job);     // 只發事件，不管誰處理
    }
}

emitter.on("jobComplete", (job) => logger.log(job.id));
emitter.on("jobComplete", (job) => webhookService.notify(job));
emitter.on("jobComplete", (job) => cacheService.invalidate(job));
```

> **Python 類比**：這和 Django 的 `Signal` 或 Flask 的 `blinker` 訊號系統的設計哲學完全相同。
