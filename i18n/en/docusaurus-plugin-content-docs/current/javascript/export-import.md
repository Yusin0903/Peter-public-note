---
sidebar_position: 1
---

# export / import Module System

`export` means "make this function available for external import."

```js
// With export → can be imported externally
export const createUserRepo = () => { ... };
// import { createUserRepo } from "..." ✅

// Without export → only usable within this file
const helperFunction = () => { ... };
// import { helperFunction } from "..." ❌ not found
```

## Python Equivalent

Python defaults to everything being public; JS/TS defaults to private — you need `export` to make something importable.

| | JavaScript/TypeScript | Python |
|---|---|---|
| Default visibility | Private (requires `export`) | Public |
| Restricting external access | Don't add `export` | Use `_` prefix (convention) |
