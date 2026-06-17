---
sidebar_position: 2
---

# Singleton vs Multiple Instances

## Singleton

Only one instance for the entire app — good for shared resources.

```python
class AppConfig:
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance.load_config()
        return cls._instance

config = AppConfig()  # whole app shares this one instance
```

## When to Use Singleton

| Scenario | Reason |
|----------|--------|
| Auth token management | All requests share one token, centralized refresh |
| Config management | Config only needs to be loaded once |
| Logger | Centralized log output |
| DB Connection Pool | Shared connection pool |

## When to Use Multiple Instances

| Scenario | Reason |
|----------|--------|
| Parallel data processors | Each processor handles its own data |
| Multiple different DB connections | Connect to different databases |
| Multiple API clients | Connect to different services or accounts |

```python
# Multiple instances — each processor is independent
class DataProcessor:
    def __init__(self, data):
        self.data = data

    def process(self):
        return f"Processing {self.data}"

processor1 = DataProcessor("dataset_A")
processor2 = DataProcessor("dataset_B")
```

## Summary

- **Singleton**: Shared resources, global state, configuration management
- **Multiple instances**: Parallel processing, resource isolation, different configurations
