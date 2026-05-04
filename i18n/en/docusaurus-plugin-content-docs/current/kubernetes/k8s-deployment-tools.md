---
sidebar_position: 4
---

# K8s Deployment Tools & Terraform

---

## Terraform Is Not a K8s Deployment Tool

Terraform is an **infrastructure management tool**. K8s is just one of many things it can manage.

### What Terraform Can Manage

```
AWS       → VPC, EKS, EC2, RDS, S3, IAM, Route53, ALB...
Azure     → AKS, VM, Storage, AD...
GCP       → GKE, Compute, Cloud SQL...
K8s       → Helm release, kubectl manifest, namespace...
Others    → GitHub repo, Datadog monitor, PagerDuty,
            Cloudflare DNS, Vault secrets...
```

Basically anything with an API can be managed by Terraform.

---

## K8s Deployment Tools Comparison

| Tool | Purpose | Best For |
|---|---|---|
| **Terraform + Helm** | Manage infra + deploy apps together | Ops/Platform teams |
| **Helm** standalone | K8s app deployment | K8s only, no cloud resources |
| **ArgoCD / FluxCD** | GitOps — git push auto-deploys to K8s | Continuous deployment, app teams |
| **kubectl** | Manual YAML apply | Debugging, learning |
| **Kustomize** | YAML overlay for multi-env | When you don't want Helm templates |
| **Pulumi** | Write infra in Python/TypeScript | When you don't want to learn HCL |

---

## Terraform + Helm Together

```
Terraform manages:
  → K8s cluster itself (EKS / AKS / GKE)
  → Cloud resources (Load Balancer, IAM, Secrets, Storage...)
  → Calls Helm to deploy apps

Helm manages:
  → Apps inside K8s (Deployment, Service, ConfigMap, RBAC...)
```

If you only use Helm — you can deploy apps to K8s, but who creates the K8s cluster? Load Balancer? Secrets?

**Terraform manages the full stack (cloud + K8s), Helm only manages apps inside K8s.**

---

## Helm Chart vs Manual YAML

### Helm chart — pre-built YAML for you

```
Manual:
  Hand-write Deployment YAML
  Hand-write Service YAML
  Hand-write ServiceAccount + RBAC YAML
  kubectl apply -f one by one

Helm:
  Chart already contains all YAML templates
  Just fill in values (image tag, replica count...)
  helm install does everything at once
```

### kubectl_manifest — still write YAML yourself

```hcl
# Inside Terraform, but the YAML is yours
yaml_body = <<-YAML
  apiVersion: apps/v1
  kind: Deployment
  ...
YAML
```

### Comparison

| | Manual kubectl | Terraform + Helm |
|---|---|---|
| Complex components | Write 20+ YAML files yourself | Helm chart pre-built, fill values |
| Simple resources | `kubectl apply -f` | `kubectl_manifest` (still write YAML) |
| Version control | Manage YAML files manually | git + Terraform state auto-tracking |
| Multi-env | Copy YAML per env and modify | Same code, different inputs |
| Rollback | Apply old YAML | Terraform state tracks, auto diff |

**Terraform's value is not "writing YAML for you" — it's state management + multi-env + version control + dependency ordering.**

---

## How Helm `set {}` Becomes YAML

Helm's `set` uses `.` and `[0]` to represent YAML hierarchy. Terraform's `set` blocks are assembled by Helm into complete K8s YAML.

### Example: extraSecretMounts

What you write in Terraform:

```hcl
set {
  name  = "server.extraSecretMounts[0].name"
  value = "my-secret"
}
set {
  name  = "server.extraSecretMounts[0].secretName"
  value = "k8s-secret-name"
}
set {
  name  = "server.extraSecretMounts[0].mountPath"
  value = "/etc/secrets/my-secret"
}
set {
  name  = "server.extraSecretMounts[0].readOnly"
  value = "true"
}
```

What Helm generates:

```yaml
volumes:
  - name: my-secret
    secret:
      secretName: k8s-secret-name

containers:
  - name: server
    volumeMounts:
      - name: my-secret
        mountPath: /etc/secrets/my-secret
        readOnly: true
```

### Reading `set` name field

```
server.extraSecretMounts[0].secretName
  │       │                │     │
  │       │                │     └── YAML key
  │       │                └── First element of array
  │       └── Key in Helm values
  └── This setting belongs to server section
```

### `values = [file(...)]` vs `set {}`

```hcl
resource "helm_release" "app" {
  # Method 1: YAML file for bulk settings
  values = [file("${path.module}/config.yaml")]

  # Method 2: set for individual overrides (higher priority)
  set {
    name  = "server.replicaCount"
    value = "2"
  }
}
```

Both can be used together. `set` takes priority over `values` file.
