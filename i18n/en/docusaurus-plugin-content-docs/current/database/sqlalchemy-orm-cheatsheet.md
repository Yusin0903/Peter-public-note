---
sidebar_position: 2
---

# SQLAlchemy 2.0 Async ORM Cheatsheet

## Basic Queries

| SQLAlchemy 2.0 Async ORM | Raw SQL |
|---|---|
| `select(Station)` | `SELECT * FROM station` |
| `select(Station.id, Station.name)` | `SELECT id, name FROM station` |
| `select(func.count())` | `SELECT COUNT(*) FROM station` |

## WHERE Conditions

| SQLAlchemy 2.0 Async ORM | Raw SQL |
|---|---|
| `select(Station).where(Station.id == 1)` | `SELECT * FROM station WHERE id = 1` |
| `select(Station).where(Station.is_active.is_(True))` | `SELECT * FROM station WHERE is_active IS TRUE` |
| `select(Station).where(~Station.is_deleted)` | `SELECT * FROM station WHERE NOT is_deleted` |
| `select(Station).where(Station.id.in_([1, 2, 3]))` | `SELECT * FROM station WHERE id IN (1, 2, 3)` |
| `select(Station).where(Station.name.like("%test%"))` | `SELECT * FROM station WHERE name LIKE '%test%'` |
| `select(Station).where(Station.value.is_(None))` | `SELECT * FROM station WHERE value IS NULL` |

## Multiple Conditions

| SQLAlchemy 2.0 Async ORM | Raw SQL |
|---|---|
| `select(Station).where(Station.name == "test", Station.is_deleted.is_(False))` | `SELECT * FROM station WHERE name = 'test' AND is_deleted IS FALSE` |
| `select(Station).where(or_(Station.id == 1, Station.name == "test"))` | `SELECT * FROM station WHERE id = 1 OR name = 'test'` |

## Ordering

| SQLAlchemy 2.0 Async ORM | Raw SQL |
|---|---|
| `select(Station).order_by(Station.id.asc())` | `SELECT * FROM station ORDER BY id ASC` |
| `select(Station).order_by(Station.id.desc())` | `SELECT * FROM station ORDER BY id DESC` |

## Pagination

| SQLAlchemy 2.0 Async ORM | Raw SQL |
|---|---|
| `select(Station).limit(10).offset(20)` | `SELECT * FROM station LIMIT 10 OFFSET 20` |

## Aggregation

| SQLAlchemy 2.0 Async ORM | Raw SQL |
|---|---|
| `select(func.count()).select_from(Station)` | `SELECT COUNT(*) FROM station` |
| `select(func.sum(Station.value))` | `SELECT SUM(value) FROM station` |
| `select(func.avg(Station.value))` | `SELECT AVG(value) FROM station` |

## Joins

| SQLAlchemy 2.0 Async ORM | Raw SQL |
|---|---|
| `select(Station).join(Group, Station.group_id == Group.id)` | `SELECT * FROM station JOIN group ON station.group_id = group.id` |
| `select(Station).outerjoin(Group, Station.group_id == Group.id)` | `SELECT * FROM station LEFT OUTER JOIN group ON ...` |

## UPDATE

Write operations are recommended using Core API (better readability and performance):

| SQLAlchemy 2.0 Core | Raw SQL |
|---|---|
| `update(Station).where(Station.id == id).values(group_id=0)` | `UPDATE station SET group_id = 0 WHERE id = :id` |

## Usage Recommendations

- **Read operations** (especially complex joins) → use ORM, simplifies code
- **Write operations** (insert/update/delete, especially high-frequency or bulk) → use Core API
- **Performance-critical paths** → use Core API
- **Complex business logic** → use ORM

## References

- [SQLAlchemy 2.0 Official Expressions Docs](https://docs.sqlalchemy.org/en/20/core/sqlelement.html)
- [SQLAlchemy 2.0 Official Query Guide](https://docs.sqlalchemy.org/en/20/orm/queryguide/select.html)
