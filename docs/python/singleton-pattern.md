---
sidebar_position: 2
---

# Singleton vs 多實例 設計模式

## Singleton（單例）

整個 app 只有一個 instance，適合共享資源。

```python
# 在模組層級建立一個 instance，import 時自動共用
class AppConfig:
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance.load_config()
        return cls._instance

config = AppConfig()  # 整個 app 共用這一個
```

## 何時用 Singleton

| 場景 | 原因 |
|------|------|
| 認證 Token 管理 | 所有請求共用同一個 token，集中管理刷新 |
| 設定管理（Config） | 設定只需載入一次 |
| Logger | 集中管理 log 輸出 |
| DB Connection Pool | 共用連線池 |

## 何時用多實例

| 場景 | 原因 |
|------|------|
| 並行資料處理器 | 每個處理器處理自己的資料 |
| 多個不同 DB 連線 | 連接不同資料庫 |
| 多個 API Client | 連接不同服務或不同帳號 |

```python
# 多實例 — 每個處理器獨立
class DataProcessor:
    def __init__(self, data):
        self.data = data

    def process(self):
        return f"Processing {self.data}"

processor1 = DataProcessor("dataset_A")
processor2 = DataProcessor("dataset_B")
```

## 總結

- **Singleton**：共享資源、全局狀態、配置管理
- **多實例**：並行處理、資源隔離、不同配置
