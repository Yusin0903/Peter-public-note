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

## 事件名稱是動態的

事件不需要預先定義，它是動態的。你 `emit` 什麼字串，`on` 監聽什麼字串，就配對上了。

```js
// 事件名稱只是字串，隨時可以新增
emitter.on("taskComplete", async () => { ... });
emitter.emit("taskComplete");

// 你甚至可以隨便取名
emitter.on("pizza", () => console.log("好吃"));
emitter.emit("pizza"); // → "好吃"
```

就像 Python 的 dict，key 不用預先定義：

```python
listeners = {}
listeners["process"] = some_function   # 隨時加
listeners["shutdown"] = another_function  # 隨時加
```

## `on` vs `once`

`once` 跟 `on` 的差別只有一個：只執行一次。

```js
// on — 每次 emit 都會執行
emitter.on("tick", () => console.log("hi"));
emitter.emit("tick");  // → "hi"
emitter.emit("tick");  // → "hi"
emitter.emit("tick");  // → "hi"（無限次）

// once — 只執行第一次，之後自動取消註冊
emitter.once("shutdown", () => console.log("bye"));
emitter.emit("shutdown");    // → "bye"
emitter.emit("shutdown");    // → （沒反應了）
```

## 用 EventEmitter 實現無限迴圈

用 EventEmitter 來做無限迴圈，比 `while (true)` 更容易控制並行和優雅關機：

```js
// 用 EventEmitter 的做法
emitter.on("process", async () => {
  await this.processNextJob();
  emitter.emit("process");  // 做完後再觸發自己
});
emitter.emit("process");    // 啟動第一次

// 等價的 Python while 迴圈
while not should_exit:
    await self.process_next_job()
```

兩種寫法效果一樣，用 EventEmitter 的好處是可以方便地控制多條並行迴圈和優雅關機。

## Python 等價

Python 沒有內建等價的，但概念很簡單：

```python
class EventEmitter:
    def __init__(self):
        self.listeners = {}

    def on(self, event, callback):
        self.listeners.setdefault(event, []).append(callback)

    def emit(self, event):
        for callback in self.listeners.get(event, []):
            callback()
```
