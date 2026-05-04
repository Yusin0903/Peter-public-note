---
sidebar_position: 1
---

# Linux Permissions

## chmod Number Reference

```bash
chmod 644 file
```

| Position | Applies To |
|----------|-----------|
| First digit | Owner permissions |
| Second digit | Group permissions |
| Third digit | Others permissions |

| Value | Permission |
|-------|-----------|
| 4 | read (r) |
| 2 | write (w) |
| 1 | execute (x) |
| 0 | no permission (-) |

Examples:
```
644 = rw-r--r--   Owner can read/write, Group/Others read-only
700 = rwx------   Only Owner can read/write/execute
755 = rwxr-xr-x   Owner full access, Group/Others can read and execute
```

## Docker + Security Configuration Example

To prevent regular users from reading config files directly while still allowing Docker to mount them:

```
docker-compose.yml  → 700 (only owner can read/write/execute)
config directory/   → 600 (only owner can read/write)
data files inside   → 644 (owner read/write, others read-only)
```

Regular users can't read the config directly, but Docker containers can mount and use the data because they run with the appropriate user context.
