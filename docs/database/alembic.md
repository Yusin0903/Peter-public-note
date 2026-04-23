---
sidebar_position: 1
---

# Alembic 完整工作指南

## 心智模型：Alembic 如何追蹤版本

Alembic 在資料庫裡維護一張叫 `alembic_version` 的表，只有一欄 `version_num`，記錄當前 schema 的版本 hash。

```sql
-- 查看當前版本
SELECT version_num FROM alembic_version;
-- 輸出: a3b4c5d6e7f8
```

每個 migration 檔案（`alembic/versions/xxx_description.py`）都有 `revision`（自己的 hash）和 `down_revision`（前一個版本的 hash），串成一條版本鏈。

```
None → a1b2c3 → d4e5f6 → a3b4c5 (head)
```

> **Python 類比**：想像成 Git commit history。每個 migration 就是一個 commit，有 SHA 和 parent SHA。`alembic upgrade head` 等同於 `git checkout main`，`alembic downgrade -1` 等同於 `git revert HEAD~1`。

```python
# alembic/versions/a3b4c5d6e7f8_add_inference_results.py
revision = 'a3b4c5d6e7f8'
down_revision = 'd4e5f6g7h8i9'  # 指向前一個版本
branch_labels = None
depends_on = None

def upgrade() -> None:
    op.create_table('inference_results', ...)

def downgrade() -> None:
    op.drop_table('inference_results')
```

---

## 常用指令速查表

```bash
# 查看當前資料庫版本
alembic current

# 查看完整版本歷史（所有 revision）
alembic history
alembic history --verbose  # 含詳細資訊

# 產生新 migration（自動偵測 model 變更）
alembic revision --autogenerate -m "Add inference_results table"

# 產生空白 migration（手動寫 upgrade/downgrade）
alembic revision -m "Custom data migration"

# 升版到最新
alembic upgrade head

# 升版到指定版本
alembic upgrade a3b4c5d6

# 升版 N 個版本
alembic upgrade +2

# 降版一個
alembic downgrade -1

# 降版到指定版本
alembic downgrade d4e5f6g7

# 降版到最初（全部回滾）
alembic downgrade base

# 標記版本（不真正執行 migration，只更新 alembic_version）
alembic stamp head
alembic stamp a3b4c5d6

# 顯示 upgrade 會執行哪些 SQL（不真正執行）
alembic upgrade head --sql
```

---

## 初始化流程

### 新專案從零開始

```bash
alembic init alembic
alembic revision --autogenerate -m "Initial schema"
alembic upgrade head
```

### 從既有資料庫遷移（如 SQLite）

如果資料庫已存在且 schema 已建好，只需標記 baseline，不重複建表：

```bash
alembic revision --autogenerate -m "baseline"
# 確認產生的 migration 無誤後：
alembic stamp head  # 告訴 Alembic「現在的 DB 就是 head」
```

---

## autogenerate 的盲點（重要！）

`--autogenerate` 會比對 SQLAlchemy model 和實際資料庫 schema，但**有幾類東西它偵測不到**，這些需要手動寫 migration：

| 偵測不到的項目 | 說明 | 手動處理方式 |
|---|---|---|
| 自訂 PostgreSQL type（如 `ENUM`） | SA 無法自動比較 | 手動 `op.execute("CREATE TYPE ...")` |
| PostgreSQL Sequence | 序列不在 SA metadata | 手動 `op.execute("CREATE SEQUENCE ...")` |
| `CHECK CONSTRAINT` | 部分版本不支援自動偵測 | 手動 `op.create_check_constraint(...)` |
| 預存程序 / Function / Trigger | SA 不管理這些物件 | 手動 `op.execute(...)` |
| 部分 index 選項（如 `WHERE` 條件）| Partial index | 手動 `op.create_index(..., postgresql_where=...)` |

> **結論**：autogenerate 很好用，但每次產生 migration 後一定要 **review 內容**，再執行。

---

## 資料遷移模式（Data Migration）

Schema migration 改的是表結構，Data migration 改的是資料本身。Alembic 兩者都能做。

**範例：為推論服務新增 `model_version` 欄位，並為舊資料填入預設值**

```python
# alembic/versions/b1c2d3_add_model_version.py
from alembic import op
import sqlalchemy as sa
from sqlalchemy.sql import table, column

def upgrade() -> None:
    # 1. 新增欄位（允許 null，先不設 NOT NULL）
    op.add_column('inference_results',
        sa.Column('model_version', sa.String(50), nullable=True)
    )

    # 2. 用 bulk update 填入預設值（不要用 ORM，直接用 Core）
    inference_results = table(
        'inference_results',
        column('model_version', sa.String)
    )
    op.execute(
        inference_results.update().values(model_version='v1.0.0')
    )

    # 3. 設為 NOT NULL（資料已有值，安全了）
    op.alter_column('inference_results', 'model_version', nullable=False)


def downgrade() -> None:
    op.drop_column('inference_results', 'model_version')
```

> **Python 類比**：資料遷移就像 Python 的 list comprehension，先把所有元素讀出來，套用轉換函式，再寫回去。差別是 Alembic 在資料庫層做，不用把資料拉到 Python。

**大量資料的資料遷移（分批處理）**

```python
def upgrade() -> None:
    op.add_column('inference_results',
        sa.Column('score_normalized', sa.Float, nullable=True)
    )

    # 分批更新，避免鎖表太久
    connection = op.get_bind()
    batch_size = 1000

    while True:
        result = connection.execute(
            sa.text("""
                UPDATE inference_results
                SET score_normalized = score / 100.0
                WHERE score_normalized IS NULL
                LIMIT :batch_size
                RETURNING id
            """),
            {"batch_size": batch_size}
        )
        if result.rowcount == 0:
            break
```

---

## 在 Kubernetes 執行 Migration

**推薦做法：用 init container 或 Job**

不要讓應用程式在啟動時自動執行 migration，這在多副本部署下會有 race condition。

### 方法一：Init Container（推薦，簡單）

```yaml
# deployment.yaml
spec:
  initContainers:
    - name: db-migrate
      image: your-app:latest
      command: ["alembic", "upgrade", "head"]
      env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: url
  containers:
    - name: app
      image: your-app:latest
      # ... 正常的 app container
```

Init container 必須成功退出，主 container 才會啟動。自動保證「migration 先於 app」。

### 方法二：Kubernetes Job（推薦，可審計）

```yaml
# migration-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration-v2-3-0
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: your-app:v2.3.0
          command: ["alembic", "upgrade", "head"]
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: db-secret
                  key: url
  backoffLimit: 3
```

在 CI/CD pipeline 中先 apply Job，等待完成後再 apply Deployment：

```bash
kubectl apply -f migration-job.yaml
kubectl wait --for=condition=complete job/db-migration-v2-3-0 --timeout=300s
kubectl apply -f deployment.yaml
```

> **Python 類比**：Init container 就像 Python 的 `__init__` 方法，保證在業務邏輯執行前先完成初始化。Kubernetes Job 則像是 CI 裡的 `pytest` step，獨立執行、有審計紀錄、失敗就停止後續部署。

### 錯誤排查

```bash
# 查看 migration job 的 log
kubectl logs job/db-migration-v2-3-0

# 如果 migration 失敗，手動降版
kubectl run alembic-rollback --image=your-app:latest --restart=Never \
  --env="DATABASE_URL=..." \
  -- alembic downgrade -1
```

---

## 多環境 alembic.ini 設定

```ini
# alembic.ini
[alembic]
script_location = alembic
# 從環境變數讀取，不要 hardcode 密碼
sqlalchemy.url = %(DB_URL)s
```

```python
# alembic/env.py
import os
from alembic import context

config = context.config
config.set_main_option("sqlalchemy.url", os.environ["DATABASE_URL"])
```

---

## Reference

- [Alembic 官方文件](https://alembic.sqlalchemy.org/en/latest/)
- [Auto-generating Migrations](https://alembic.sqlalchemy.org/en/latest/autogenerate.html)
- [Alembic Cookbook](https://alembic.sqlalchemy.org/en/latest/cookbook.html)
