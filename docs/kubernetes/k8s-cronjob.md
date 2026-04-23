---
sidebar_position: 5
---

# CronJob

K8s 的 CronJob 就是 crontab 的 K8s 版本，定時觸發一個 Job（跑完就停的容器）。

> **Python 類比**：就像用 `APScheduler` 或 `crontab` 定時執行 Python script，但在 K8s cluster 裡執行、有 retry 機制、有歷史紀錄。

```python
# 你以前可能這樣做：
# crontab: "10 */1 * * *  python /app/cleanup.py"

# K8s CronJob 等價：
# schedule: "10 */1 * * *"  → 每小時第 10 分鐘
# backoffLimit: 3            → 失敗最多重試 3 次（像 tenacity retry）
# concurrencyPolicy: Forbid  → 上一個還沒跑完就不啟動新的
```

---

## 設定範例

```yaml
schedule: "10 */1 * * *"        # 每小時第 10 分鐘執行
concurrencyPolicy: Forbid       # 上一次沒跑完不啟動新的
successfulJobsHistoryLimit: 1   # 只保留 1 個成功紀錄
failedJobsHistoryLimit: 3       # 保留 3 個失敗紀錄（方便 debug）
backoffLimit: 3                 # 失敗最多重試 3 次
```

---

## concurrencyPolicy 三種

| 值 | 行為 |
|---|---|
| `Forbid` | 上一次沒跑完，這次跳過 |
| `Allow` | 允許同時多個 Job 並發（預設） |
| `Replace` | 殺掉上一次，啟動新的 |

```python
# Python 類比：

# Forbid = threading.Lock() 搶不到就放棄
import threading
lock = threading.Lock()
if not lock.acquire(blocking=False):
    print("上次還沒跑完，跳過這次")

# Allow = 不管 lock，每次都開新 thread
# Replace = 先 cancel 舊 task，再開新的（像 asyncio.Task.cancel()）
```

**inference system 建議**：batch inference 用 `Forbid`，避免兩個 job 同時讀同一批資料造成重複處理。

---

## activeDeadlineSeconds — 強制 timeout

批次任務最怕跑到一半卡住（網路問題、資料異常），`activeDeadlineSeconds` 確保 Job 超時就直接砍掉，不會讓殭屍 Job 佔著 GPU 資源。

```yaml
spec:
  activeDeadlineSeconds: 3600   # 最多跑 1 小時，超過就強制終止
  backoffLimit: 2               # 失敗最多重試 2 次
```

```
Job 啟動
  │
  ├── 正常完成（< 3600s）→ 成功
  │
  └── 超過 3600s → K8s 強制終止 Pod + 標記 Job 為失敗
                   （不管 backoffLimit，直接死）
```

> **Python 類比**：
> ```python
> import signal
>
> def timeout_handler(signum, frame):
>     raise TimeoutError("Job exceeded deadline")
>
> # activeDeadlineSeconds = 3600 等同於：
> signal.signal(signal.SIGALRM, timeout_handler)
> signal.alarm(3600)  # 3600 秒後強制中斷
>
> try:
>     run_batch_inference()  # 正常跑
> except TimeoutError:
>     cleanup()              # K8s 會送 SIGTERM，給你清理的機會
> ```

**重要**：`activeDeadlineSeconds` 是整個 Job 的 deadline（包含重試時間），不是單次 Pod 的 timeout。如果你設 `activeDeadlineSeconds: 3600` 且 `backoffLimit: 3`，三次重試加起來超過 3600s 就整個 Job 終止。

---

## 資源限制 — batch job 的硬性規定

Batch job 不設資源限制非常危險：一個壞掉的 job 可能把整個 node 的 GPU/CPU 吃光，影響線上 inference service。

```yaml
spec:
  template:
    spec:
      containers:
        - name: batch-inference
          resources:
            requests:
              cpu: "2"
              memory: "8Gi"
              nvidia.com/gpu: "1"
            limits:
              cpu: "4"
              memory: "16Gi"
              nvidia.com/gpu: "1"   # GPU limits 必須 = requests
```

> **Python 類比**：
> ```python
> # 就像設 ulimit 防止 runaway process
> import resource
>
> # limits.memory = 16Gi
> resource.setrlimit(resource.RLIMIT_AS, (16 * 1024**3, 16 * 1024**3))
>
> # 或用 subprocess 的 preexec_fn 限制子 process 資源
> import subprocess
> subprocess.run(
>     ["python", "batch_inference.py"],
>     preexec_fn=lambda: resource.setrlimit(
>         resource.RLIMIT_AS, (16 * 1024**3, 16 * 1024**3)
>     )
> )
> ```

---

## 真實 Batch Inference CronJob YAML

每 30 分鐘從 S3 讀取 pending 資料，跑 inference，結果寫回 S3：

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: batch-inference
  namespace: inference
spec:
  schedule: "*/30 * * * *"         # 每 30 分鐘執行一次
  concurrencyPolicy: Forbid         # 上次沒跑完就跳過（避免重複處理）
  successfulJobsHistoryLimit: 3     # 保留 3 個成功紀錄
  failedJobsHistoryLimit: 5         # 保留 5 個失敗紀錄（方便 debug）

  jobTemplate:
    spec:
      activeDeadlineSeconds: 1800   # 最多跑 30 分鐘（等於 schedule 間隔）
      backoffLimit: 1               # 失敗只重試 1 次（避免浪費 GPU）

      template:
        metadata:
          labels:
            app: batch-inference
            job-type: scheduled
        spec:
          restartPolicy: OnFailure  # Job 必須設這個（不能用 Always）

          # 排程到 GPU node
          nodeSelector:
            accelerator: nvidia-gpu

          tolerations:
            - key: nvidia.com/gpu
              operator: Exists
              effect: NoSchedule

          # Init container：確認有待處理的資料才繼續
          initContainers:
            - name: check-pending-data
              image: amazon/aws-cli:2
              command:
                - sh
                - -c
                - |
                  COUNT=$(aws s3 ls s3://my-data/pending/ | wc -l)
                  echo "Pending files: $COUNT"
                  if [ "$COUNT" -eq 0 ]; then
                    echo "No pending data, exiting"
                    exit 1   # 讓 Job 標記為失敗，但不浪費 GPU 資源
                  fi
              env:
                - name: AWS_DEFAULT_REGION
                  value: us-west-2
              resources:
                requests:
                  cpu: "100m"
                  memory: "128Mi"
                limits:
                  cpu: "200m"
                  memory: "256Mi"

          containers:
            - name: batch-inference
              image: my-org/batch-inference:1.0.0
              command:
                - python
                - batch_inference.py
              args:
                - --input-prefix
                - s3://my-data/pending/
                - --output-prefix
                - s3://my-data/results/
                - --batch-size
                - "64"
                - --max-files
                - "1000"          # 限制每次處理量，避免超時

              env:
                - name: AWS_DEFAULT_REGION
                  value: us-west-2
                - name: CUDA_VISIBLE_DEVICES
                  value: "0"
                - name: MODEL_PATH
                  value: /opt/model

                # 從 Secret 注入 API key（不要直接寫在 YAML 裡）
                - name: OPENAI_API_KEY
                  valueFrom:
                    secretKeyRef:
                      name: inference-secrets
                      key: openai-api-key

              resources:
                requests:
                  nvidia.com/gpu: "1"
                  cpu: "4"
                  memory: "16Gi"
                limits:
                  nvidia.com/gpu: "1"
                  cpu: "8"
                  memory: "32Gi"

              volumeMounts:
                - name: shm
                  mountPath: /dev/shm

          volumes:
            - name: shm
              emptyDir:
                medium: Memory
                sizeLimit: 8Gi

          # Job 結束後 Pod 保留多久（方便 debug log）
          # 不設的話 Job 完成後 Pod 立刻消失，看不到 log
          # 注意：這個要在 jobTemplate.spec 層級設，不是 template.spec
```

```python
# 對應的 Python batch_inference.py 骨架：
import argparse
import boto3
import torch

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-prefix", required=True)
    parser.add_argument("--output-prefix", required=True)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--max-files", type=int, default=1000)
    args = parser.parse_args()

    s3 = boto3.client("s3")
    model = load_model("/opt/model")

    # 讀取 pending 資料
    files = list_s3_files(args.input_prefix, limit=args.max_files)

    for batch in chunked(files, args.batch_size):
        inputs = [load_from_s3(f) for f in batch]
        results = model.predict(inputs)

        for file, result in zip(batch, results):
            output_key = file.replace("pending/", "results/")
            s3.put_object(Key=output_key, Body=serialize(result))

        # 處理完後把 pending 標記為 done（移動或刪除）
        for f in batch:
            s3.copy_object(CopySource=f, Key=f.replace("pending/", "done/"))
            s3.delete_object(Key=f)

if __name__ == "__main__":
    main()
```

---

## 適合的使用場景

```python
# 1. 定時備份
# schedule: "0 2 * * *"  → 每天凌晨 2 點
python backup_database.py --target s3://my-bucket/

# 2. 定時清理過期資料
# schedule: "0 * * * *"  → 每小時
python cleanup_expired_tokens.py --ttl 86400

# 3. 定期產生報表
# schedule: "30 8 * * 1"  → 每週一早上 8:30
python generate_weekly_report.py --send-email

# 4. Inference batch job
# schedule: "*/30 * * * *"  → 每 30 分鐘執行一次 batch inference
python batch_inference.py --input s3://data/pending/ --output s3://data/results/
```
