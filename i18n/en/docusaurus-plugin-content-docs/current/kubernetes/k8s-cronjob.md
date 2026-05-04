---
sidebar_position: 5
---

# CronJob

K8s CronJob is the cluster-native version of crontab — it triggers a Job (a container that runs to completion) on a schedule.

> **Python analogy**: Like using `APScheduler` or `crontab` to run a Python script on a schedule, but running inside the K8s cluster with retry logic and history tracking.

```python
# You might have done this before:
# crontab: "10 */1 * * *  python /app/cleanup.py"

# K8s CronJob equivalent:
# schedule: "10 */1 * * *"   → minute 10 of every hour
# backoffLimit: 3             → retry up to 3 times on failure (like tenacity)
# concurrencyPolicy: Forbid   → don't start new run if previous isn't done
```

---

## Configuration Example

```yaml
schedule: "10 */1 * * *"        # runs at minute 10 every hour
concurrencyPolicy: Forbid       # don't start new run if previous isn't done
successfulJobsHistoryLimit: 1   # keep only 1 successful run record
backoffLimit: 3                 # retry up to 3 times on failure
```

---

## concurrencyPolicy Options

| Value | Behaviour |
|---|---|
| `Forbid` | Skip this run if previous isn't done yet |
| `Allow` | Allow multiple Jobs to run concurrently (default) |
| `Replace` | Kill the previous run, start a new one |

```python
# Python analogy:

# Forbid = threading.Lock(), skip if can't acquire
import threading
lock = threading.Lock()
if not lock.acquire(blocking=False):
    print("Previous run still going, skipping this one")

# Allow = no lock, start a new thread every time
# Replace = cancel old task first, then start new (like asyncio.Task.cancel())
```

---

## Typical Use Cases

```python
# 1. Scheduled database backup
# schedule: "0 2 * * *"  → every day at 2am
python backup_database.py --target s3://my-bucket/

# 2. Expire old data cleanup
# schedule: "0 * * * *"  → every hour
python cleanup_expired_tokens.py --ttl 86400

# 3. Weekly report generation
# schedule: "30 8 * * 1"  → every Monday at 8:30am
python generate_weekly_report.py --send-email

# 4. Batch inference job
# schedule: "*/30 * * * *"  → every 30 minutes
python batch_inference.py --input s3://data/pending/ --output s3://data/results/
```
