---
sidebar_position: 1
---

# Alembic Workflow Guide

## 從既有資料庫遷移（如 SQLite）

如果已有現有的資料庫，先設定 baseline：

```bash
alembic revision --autogenerate -m "initial migration"
alembic stamp head
```

## 初始化空資料庫

新資料庫從零開始：

```bash
alembic init alembic
alembic revision --autogenerate -m "Initial version"
alembic upgrade head
```

## 更新 Model 後

SQLAlchemy model 有改動時，產生新的 migration 並套用：

```bash
alembic revision --autogenerate -m "Update models"
alembic upgrade head
```

## 降版（Rollback）

回滾一個 migration：

```bash
alembic downgrade -1
```
