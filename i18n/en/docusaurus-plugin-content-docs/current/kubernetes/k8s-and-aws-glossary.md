---
sidebar_position: 3
---

# K8s & AWS Glossary

---

## Kubernetes Core

| Term | One-liner | Analogy |
|---|---|---|
| **Pod** | Smallest deployable unit, runs one or more containers | A process on a machine |
| **Deployment** | Manages Pod replicas and update strategy | "Run 3 copies of this service" |
| **StatefulSet** | Stateful Deployment, each Pod has fixed name and disk | Database instances |
| **Service** | Stable internal IP/DNS for a group of Pods | Reception desk |
| **Ingress** | L7 routing rules (host/path → Service) | Building directory sign |
| **Namespace** | Virtual resource isolation group | Different floors in an office |
| **ConfigMap** | Stores config files (non-secret) | Shared folder config |
| **Secret** | Stores sensitive data (passwords, tokens) | Config in a safe |
| **PVC** | PersistentVolumeClaim — Pod's disk request | Requesting a hard drive from IT |
| **PV** | PersistentVolume — The actual disk | The hard drive IT gives you |
| **StorageClass** | Disk specification template | Hard drive model catalog |
| **CRD** | CustomResourceDefinition — custom resource types | Teaching K8s to recognize new things |
| **Operator** | Controller that auto-manages CRDs | A robot watching CRDs and acting on changes |
| **DaemonSet** | Runs one Pod on every Node | An agent installed on every machine |
| **Node** | A machine in the K8s cluster | A computer in the office |
| **Helm** | K8s package manager | Like pip/npm |
| **kubectl** | K8s CLI tool | Like aws cli |

---

## AWS Basics

| Term | One-liner |
|---|---|
| **EKS** | Elastic Kubernetes Service — AWS-managed K8s |
| **EC2** | Elastic Compute Cloud — Virtual machines |
| **EBS** | Elastic Block Store — Network-attached disks |
| **ALB** | Application Load Balancer — L7 load balancing |
| **ECR** | Elastic Container Registry — Docker image storage |
| **IAM** | Identity and Access Management — Permissions |
| **ACM** | AWS Certificate Manager — SSL/TLS certificates |
| **Secrets Manager** | Centralized password and token management |
| **S3** | Simple Storage Service — Object storage |
| **Route53** | DNS service |
| **VPC** | Virtual Private Cloud — Virtual network |
| **Transit Gateway** | Cross-VPC / cross-Region network routing |

---

## Terraform

| Term | One-liner |
|---|---|
| **Terraform** | IaC tool, define cloud resources in HCL |
| **Provider** | Bridge between Terraform and cloud APIs |
| **Module** | Reusable package of related resources |
| **State** | Terraform's record of managed resources |
| **Plan** | Preview changes |
| **Apply** | Execute changes |
| **Terragrunt** | Terraform wrapper for multi-environment code reuse |

---

## Monitoring

| Term | One-liner |
|---|---|
| **Prometheus** | Open-source monitoring, pull-based metrics collection |
| **remote_write** | Standard API for Prometheus to push metrics to remote storage |
| **external_labels** | Fixed labels added to all metrics (region, cluster) |
| **PromQL** | Prometheus query language |
| **Grafana** | Visualization dashboard tool |
| **Datasource** | Grafana's connection config to a data source |
| **Cardinality** | Number of unique time series in metrics |
