---
sidebar_position: 4
---

# K8s Storage: StorageClass / PVC / PV

## Three-Layer Relationship

```
StorageClass (specification template)
  → Defines "how to create disks" (type, provisioner, reclaim policy)
  → Only a few per cluster, shared by all pods

PVC — PersistentVolumeClaim (request form)
  → Pod says "I need a 500Gi gp3 disk"
  → Each pod that needs storage gets its own PVC

PV — PersistentVolume (the actual disk)
  → K8s auto-creates this when it receives a PVC
  → Maps to a real cloud disk (AWS EBS, GCP PD, etc.)
```

> **Python analogy**:
> ```python
> # StorageClass = dataclass defining disk specs
> @dataclass
> class StorageClass:
>     name: str = "gp3"
>     provisioner: str = "ebs.csi.aws.com"
>     iops: int = 3000
>
> # PVC = calling open() to request a file resource
> # pvc = open("/data/myfile", "w")  # request disk resource
>
> # PV = the file descriptor the OS actually allocates
> # You don't operate the fd directly — K8s handles it
> ```
>
> More simply:
> - `StorageClass` = restaurant menu (defines available disk specs)
> - `PVC` = order slip (customer: "I want the gp3 combo, 500Gi")
> - `PV` = the dish that comes out of the kitchen (the actual volume)

---

## StorageClass Example

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
volumeBindingMode: WaitForFirstConsumer  # wait until pod is scheduled (same AZ)
allowVolumeExpansion: true
reclaimPolicy: Retain                    # keep volume after pod deletion
```

---

## PVC Example

```yaml
volumeClaimTemplate:
  spec:
    storageClassName: gp3
    resources:
      requests:
        storage: 500Gi
```

---

## Full Creation Flow

```
1. StorageClass "gp3" exists (defines disk spec)
2. StatefulSet declares PVC: storageClassName: gp3, storage: 500Gi
3. K8s scheduler places pod on node-1 (us-west-2a)
4. WaitForFirstConsumer → volume creation starts NOW
   K8s reads PVC → finds StorageClass "gp3" → calls provisioner
   → Cloud API creates 500Gi disk (same AZ)
5. K8s creates PV, binds PVC ↔ PV ↔ actual disk
6. Disk mounted to node → pod can read/write
```

```python
# Python analogy: the whole flow is like a context manager
class StorageProvisioner:
    def __enter__(self):
        self.volume = aws.create_ebs_volume(size="500Gi", type="gp3")
        self.volume.attach(node=scheduler.current_node)
        return self.volume

    def __exit__(self, *args):
        if self.reclaim_policy == "Retain":
            pass           # keep the disk (reclaimPolicy: Retain)
        else:
            self.volume.delete()   # delete it (reclaimPolicy: Delete)

with StorageProvisioner() as vol:
    write_data(vol, "/data/metrics.db")
# Pod ends → reclaimPolicy decides the disk's fate
```

---

## Lifecycle

| Event | PVC | PV | Actual Disk |
|---|---|---|---|
| Pod created | Created | Auto-created | Cloud auto-creates |
| Pod restarts | Unchanged | Unchanged | Unchanged (data preserved) |
| Pod moves to another node (same AZ) | Unchanged | Unchanged | Detach + reattach |
| Pod deleted | Deleted | Depends on reclaimPolicy | Retain → kept / Delete → removed |

---

## reclaimPolicy

```
Retain  → Pod deleted, disk stays, data preserved (databases, TSDB)
Delete  → Pod deleted, disk auto-deleted (temporary cache)
```

```python
# Python analogy:
# Retain = tempfile.NamedTemporaryFile(delete=False)  # manage cleanup yourself
# Delete = tempfile.NamedTemporaryFile(delete=True)   # auto-cleaned up
```

---

## volumeBindingMode

```
Immediate           → Disk created when PVC is created
                       Problem: might be in a different AZ → mount fails
WaitForFirstConsumer → Disk created after pod is scheduled
                       Ensures disk and pod are in the same AZ ✓
```

> **Why AZ matters**: AWS EBS volumes are AZ-scoped. A disk created in `us-west-2a` cannot be mounted on a machine in `us-west-2b`.

---

## Cloud Disk vs Node Local Disk

| | Cloud Disk (EBS) | Node Local Disk |
|---|---|---|
| Nature | Independent network-attached disk | Node's built-in root disk |
| Node deleted | Disk survives | Data lost |
| Pod moves | Can reattach to another Node | Cannot |
| Best for | Data that must persist | Temporary cache |

```python
# Python analogy:
# Cloud disk (EBS) = external USB drive — unplug and plug into another machine, data intact
# Node local disk  = /tmp — gone after reboot
```

---

## IOPS vs Throughput

```
IOPS = I/O Operations Per Second
  → Matters for: frequent small writes (e.g., real-time metrics — tiny per write, high frequency)

Throughput = Data transfer rate (MiB/s)
  → Matters for: large sequential reads (e.g., querying history — scanning GBs at once)
```

```python
# Impact on a Python inference system:

# High IOPS scenario: write each inference result to DB immediately
for i in range(1000):
    with open(f"/data/result_{i}.json", "w") as f:
        f.write('{"score": 0.95}')  # small per write, many writes → IOPS bottleneck

# High Throughput scenario: read a large embedding file at once
with open("/data/embeddings.npy", "rb") as f:
    data = f.read()  # reading GBs at once → Throughput bottleneck
```

---

## AWS EBS gp2 vs gp3

| | gp2 | gp3 |
|---|---|---|
| Price/GiB/month | $0.10 | $0.08 (20% cheaper) |
| IOPS | Tied to capacity (3 IOPS/GiB) | Fixed 3000 baseline (any size) |
| Throughput | Up to 250 MiB/s | 125 MiB/s baseline, up to 1000 MiB/s |
| IOPS adjustable | No — must add capacity | Yes — independently adjustable, up to 16000 |

gp3 is better than gp2 in almost every scenario. AWS recommends gp3 for all new workloads.

**gp2 pain point**: To get 3000 IOPS you must provision 1000GiB (wasting space and money). gp3 gives 3000 IOPS regardless of volume size.
