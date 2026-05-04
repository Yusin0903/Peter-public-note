---
sidebar_position: 3
---

# JS Syntax Reference (vs Python)

## Ternary Operator

```js
// JavaScript
let desc = format === 'csv' ? fileName : '';
//         condition          ? true value : false value

// Python
desc = file_name if format == 'csv' else ''
```

## `===` vs `==`

| Operator | Behavior | Recommendation |
|----------|----------|----------------|
| `===` (strict) | Type AND value must match | JS convention — almost always use this |
| `==` (loose) | Auto-converts type before comparing | Avoid — easy to hit unexpected behavior |

```js
1 === '1'   // false (different types)
1 == '1'    // true  ('1' is coerced to number)
0 == ''     // true  😱
0 == false  // true  😱
```

Python's `==` doesn't auto-coerce types — this problem doesn't exist there.

## `null` vs `undefined`

| | `null` | `undefined` |
|---|---|---|
| Meaning | Intentionally set to "no value" | Undeclared / no value assigned |
| Python analogy | `None` | Variable simply doesn't exist |

Commonly used as placeholders so positional arguments don't get misaligned:

```js
sendRequest(command, userId, null, path, body, undefined);
//                            ^^^^                ^^^^^^^^^
//                            auth not needed      callback not needed
```
