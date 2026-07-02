---
sidebar_position: 1
---

# Kubernetes Core Concepts

Kubernetes is not just a container runner. It is a distributed control system that keeps pushing actual cluster state toward declared desired state:

1. Users declare desired state through the API.
2. `kube-apiserver` validates the request and stores it in `etcd`.
3. The scheduler and controllers watch the API and reconcile current state toward desired state.
4. kubelet on each worker node creates Pods, mounts volumes, and reports status.

## Navigation

| Topic | Content |
|-------|---------|
| [Ingress & Service](./k8s-ingress-and-service) | How requests flow from outside into Pods, 3 Service types, internal DNS |
| [Workload Types](./k8s-workloads) | Deployment / StatefulSet / DaemonSet / Job / CronJob — which to pick |
| [Storage](./k8s-storage) | StorageClass / PVC / PV three-layer model, gp2 vs gp3, IOPS vs Throughput |
| [CronJob](./k8s-cronjob) | Scheduled task config, concurrencyPolicy, typical use cases |
| [Observability](./k8s-observability) | Pod log queries, multi-replica log problem, EKS vs Lambda selection |

---

## Control Plane Components

| Component | What it does | Key point |
|-----------|--------------|-----------|
| `kube-apiserver` | Kubernetes API entry point | Every read and write goes through it; kubectl, controllers, scheduler, and kubelets are API clients |
| `etcd` | Distributed key-value store | Stores cluster state; do not bypass the API server and edit etcd directly |
| `kube-scheduler` | Chooses nodes for Pods without a node | Filters feasible nodes, scores them, then binds the Pod to one node |
| `kube-controller-manager` | Runs built-in controllers | Deployment, ReplicaSet, Job, Node, and other controllers run reconcile loops |
| `cloud-controller-manager` | Integrates with cloud resources | Handles cloud-provider behavior such as load balancers, nodes, routes, and volumes |

---

## Worker Node Components

| Component | What it does | Key point |
|-----------|--------------|-----------|
| `kubelet` | Main node agent | Watches Pods assigned to its node, asks the container runtime to start containers, and reports Pod status |
| container runtime | Runs containers | Common examples are containerd and CRI-O |
| `kube-proxy` | Implements Service traffic rules | Maintains iptables / IPVS / nftables rules on each node |

---

## Core Data Flow

```
kubectl apply -f deployment.yaml
  ↓
kube-apiserver
  - authentication / authorization / admission
  - validate object
  - persist desired state
  ↓
etcd
  - stores Deployment object
  ↓
Deployment controller
  - sees Deployment wants 3 replicas
  - creates / updates ReplicaSet
  ↓
ReplicaSet controller
  - sees ReplicaSet wants 3 Pods
  - creates missing Pods
  ↓
kube-scheduler
  - watches Pods with no nodeName
  - picks a node
  - writes binding through API server
  ↓
kubelet on that node
  - sees Pod assigned to itself
  - asks container runtime to start containers
  - reports Pod status back through API server
```

---

## Controller Mental Model

Controllers are not one-shot scripts. They are loops:

```python
while True:
    desired_state = watch_api_server()
    current_state = observe_cluster_or_external_system()

    if current_state != desired_state:
        make_one_small_change()
```

Kubernetes is built around declaring state and letting controllers continuously correct drift. If a Pod dies, a node disappears, or replica count is wrong, a controller notices and moves the cluster back toward the desired state.

---

## Scheduler Mental Model

The scheduler does not start Pods. It only decides which node a Pod should run on:

1. Watch Pods where `spec.nodeName` is empty.
2. Filter out nodes that cannot run the Pod because of resources, labels, taints, or volume constraints.
3. Score remaining nodes by resource spread, affinity, topology, and scheduling policy.
4. Bind the Pod by writing the selected node through the API server.

After binding, kubelet on that node starts the containers.

---

## Quick Reference

For detailed K8s glossary see [K8s Glossary](./k8s-glossary).
