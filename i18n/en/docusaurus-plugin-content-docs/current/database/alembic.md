---
sidebar_position: 1
---

# Alembic Workflow Guide

## Migrating from an Existing Database (e.g. SQLite)

If you already have an existing database, set up a baseline first:

```bash
alembic revision --autogenerate -m "initial migration"
alembic stamp head
```

## Initializing an Empty Database

Starting from scratch with a new database:

```bash
alembic init alembic
alembic revision --autogenerate -m "Initial version"
alembic upgrade head
```

## After Updating Models

When SQLAlchemy models change, generate a new migration and apply it:

```bash
alembic revision --autogenerate -m "Update models"
alembic upgrade head
```

## Rollback

Roll back one migration:

```bash
alembic downgrade -1
```
