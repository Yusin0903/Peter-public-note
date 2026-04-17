---
sidebar_position: 2
---

# SQLAlchemy 2.0 Async ORM Cheatsheet

## 基本查詢

| SQLAlchemy 2.0 Async ORM           | Raw SQL                         |
| ---------------------------------- | ------------------------------- |
| `select(Station)`                  | `SELECT * FROM station`         |
| `select(Station.id, Station.name)` | `SELECT id, name FROM station`  |
| `select(func.count())`             | `SELECT COUNT(*) FROM station`  |
| `select(func.count(Station.id))`   | `SELECT COUNT(id) FROM station` |

## WHERE 條件

| SQLAlchemy 2.0 Async ORM                                    | Raw SQL                                                 |
| ----------------------------------------------------------- | ------------------------------------------------------- |
| `select(Station).where(Station.id == 1)`                    | `SELECT * FROM station WHERE id = 1`                    |
| `select(Station).where(Station.name == "test")`             | `SELECT * FROM station WHERE name = 'test'`             |
| `select(Station).where(Station.is_active.is_(True))`        | `SELECT * FROM station WHERE is_active IS TRUE`         |
| `select(Station).where(~Station.is_deleted)`                | `SELECT * FROM station WHERE NOT is_deleted`            |
| `select(Station).where(Station.id > 5)`                     | `SELECT * FROM station WHERE id > 5`                    |
| `select(Station).where(Station.id.in_([1, 2, 3]))`          | `SELECT * FROM station WHERE id IN (1, 2, 3)`           |
| `select(Station).where(Station.name.like("%test%"))`        | `SELECT * FROM station WHERE name LIKE '%test%'`        |
| `select(Station).where(Station.value.is_(None))`            | `SELECT * FROM station WHERE value IS NULL`             |
| `select(Station).where(Station.value.is_not(None))`         | `SELECT * FROM station WHERE value IS NOT NULL`         |

## 多條件查詢

| SQLAlchemy 2.0 Async ORM                                                                           | Raw SQL                                                             |
|------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------|
| `select(Station).where(Station.name == "test", Station.is_deleted.is_(False))`                      | `SELECT * FROM station WHERE name = 'test' AND is_deleted IS FALSE` |
| `select(Station).where(or_(Station.id == 1, Station.name == "test"))`                               | `SELECT * FROM station WHERE id = 1 OR name = 'test'`               |
| `select(Station).where(and_(Station.id > 5, Station.id < 10))`                                      | `SELECT * FROM station WHERE id > 5 AND id < 10`                    |

## 排序

| SQLAlchemy 2.0 Async ORM                                         | Raw SQL                                            |
|------------------------------------------------------------------|----------------------------------------------------|
| `select(Station).order_by(Station.id.asc())`                     | `SELECT * FROM station ORDER BY id ASC`            |
| `select(Station).order_by(Station.id.desc())`                    | `SELECT * FROM station ORDER BY id DESC`           |

## 分頁

| SQLAlchemy 2.0 Async ORM                   | Raw SQL                                    |
|--------------------------------------------|--------------------------------------------|
| `select(Station).limit(10)`                | `SELECT * FROM station LIMIT 10`           |
| `select(Station).offset(20)`               | `SELECT * FROM station OFFSET 20`          |
| `select(Station).limit(10).offset(20)`     | `SELECT * FROM station LIMIT 10 OFFSET 20` |

## 聚合

| SQLAlchemy 2.0 Async ORM                    | Raw SQL                            |
| ------------------------------------------- | ---------------------------------- |
| `select(func.count()).select_from(Station)` | `SELECT COUNT(*) FROM station`     |
| `select(func.sum(Station.value))`           | `SELECT SUM(value) FROM station`   |
| `select(func.avg(Station.value))`           | `SELECT AVG(value) FROM station`   |
| `select(func.max(Station.value))`           | `SELECT MAX(value) FROM station`   |
| `select(func.min(Station.value))`           | `SELECT MIN(value) FROM station`   |

## 連接查詢

| SQLAlchemy 2.0 Async ORM                                                 | Raw SQL                                                                              |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------ |
| `select(Station).join(Group, Station.group_id == Group.id)`              | `SELECT * FROM station JOIN group ON station.group_id = group.id`                    |
| `select(Station).outerjoin(Group, Station.group_id == Group.id)`         | `SELECT * FROM station LEFT OUTER JOIN group ON station.group_id = group.id`         |

## UPDATE

寫入操作建議用 Core API（可讀性高、效能好）：

| SQLAlchemy 2.0 Core                                                          | Raw SQL                                                   |
| ---------------------------------------------------------------------------- | --------------------------------------------------------- |
| `update(Station).where(Station.id == id).values(group_id=0)`                | `UPDATE station SET group_id = 0 WHERE id = :id`          |

## 使用建議

- **讀取操作**（特別是複雜關聯查詢）→ 用 ORM，簡化程式碼
- **寫入操作**（insert/update/delete，特別是高頻或批量）→ 用 Core API
- **效能關鍵路徑** → 用 Core API
- **業務邏輯複雜** → 用 ORM

## Reference

- [SQLAlchemy 2.0 官方 Expressions 文檔](https://docs.sqlalchemy.org/en/20/core/sqlelement.html)
- [SQLAlchemy 2.0 官方 Query Guide](https://docs.sqlalchemy.org/en/20/orm/queryguide/select.html)
