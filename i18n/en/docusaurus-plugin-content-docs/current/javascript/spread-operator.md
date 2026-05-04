---
sidebar_position: 5
---

# Spread Operator (`...`)

`...` is JavaScript/TypeScript's spread operator. It "unpacks" all properties of an object into another object.

## Example: Merging Config Objects

Say you have a base config and want to add extra fields in a subclass:

```ts
const createAwsConfig = (): AwsConfig => {
  return {
    ...createBaseConfig(),  // spread all shared config in
    type: "aws",            // add AWS-specific fields
    region: "us-east-1",
  };
};
```

This is equivalent to:

```js
// createBaseConfig() returns:
{
  env: "prod",
  db: { host: "...", port: 3306 },
  redis: { url: "..." },
  logLevel: "info",
}

// After spread, the final result becomes:
{
  env: "prod",              // ← from spread
  db: { host: "..." },     // ← from spread
  redis: { url: "..." },   // ← from spread
  logLevel: "info",        // ← from spread
  type: "aws",             // ← newly added
  region: "us-east-1",    // ← newly added
}
```

## Overriding Properties

Later properties override earlier ones:

```ts
const base = { color: "red", size: "M", weight: 100 };
const override = { ...base, color: "blue" };  // color is overridden
// → { color: "blue", size: "M", weight: 100 }
```

## Python Equivalent

```python
# Python uses ** for the same thing
base = create_base_config()
aws_config = {
    **base,           # ← equivalent to JS ...
    "type": "aws",
    "region": "us-east-1",
}
```

Same as Python's `**dict` unpacking — JS/TS just uses the `...` symbol.
