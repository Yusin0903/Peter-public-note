---
sidebar_position: 6
---

# EventEmitter

EventEmitter is a Node.js built-in module — no installation needed.

```js
import EventEmitter from "node:events";  // node: prefix means Node.js built-in
```

## Basic Usage

A simple publish/subscribe event system:

```js
const emitter = new EventEmitter();

// Subscribe: run this function when "process" event is heard
emitter.on("process", () => {
  console.log("Event received!");
});

// Publish: trigger the "process" event
emitter.emit("process");
// → prints "Event received!"
```

## Event Names Are Dynamic

Events don't need to be predefined — they're dynamic. Whatever string you `emit`, whatever string you `on` listens for, they match.

```js
// Event names are just strings, add them anytime
emitter.on("taskComplete", async () => { ... });
emitter.emit("taskComplete");

// You can name them anything
emitter.on("pizza", () => console.log("delicious"));
emitter.emit("pizza"); // → "delicious"
```

Like a Python dict — keys don't need to be predefined:

```python
listeners = {}
listeners["process"] = some_function   # add anytime
listeners["shutdown"] = another_function
```

## `on` vs `once`

`once` is identical to `on` with one difference: it only fires once.

```js
// on — fires every time emit is called
emitter.on("tick", () => console.log("hi"));
emitter.emit("tick");  // → "hi"
emitter.emit("tick");  // → "hi"
emitter.emit("tick");  // → "hi" (unlimited times)

// once — fires only the first time, then auto-unregisters
emitter.once("shutdown", () => console.log("bye"));
emitter.emit("shutdown");    // → "bye"
emitter.emit("shutdown");    // → (nothing)
```

## Using EventEmitter for an Infinite Loop

EventEmitter makes infinite loops easier to control for concurrency and graceful shutdown than `while (true)`:

```js
// EventEmitter approach
emitter.on("process", async () => {
  await this.processNextJob();
  emitter.emit("process");  // trigger self again after finishing
});
emitter.emit("process");    // kick off the first iteration

// Equivalent Python while loop
while not should_exit:
    await self.process_next_job()
```

Both achieve the same result. The EventEmitter approach makes it easier to manage multiple concurrent loops and graceful shutdown.

## Python Equivalent

Python has no direct built-in equivalent, but the concept is straightforward:

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
