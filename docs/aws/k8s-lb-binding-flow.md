---
sidebar_position: 16
---

# K8s Service/Ingress 綁定 AWS LB 的流程

K8s 不直接建 ALB/NLB——你寫 K8s 物件，**AWS Load Balancer Controller** 看到後幫你呼叫 AWS API 建 LB。然後可以透過 tag 反向找回那顆 LB，做 Route 53 alias。

---

## 兩個觸發來源

| K8s 物件 | 觸發 | 結果 |
|---|---|---|
| `Service` (type=LoadBalancer) | annotation 控制細節 | **NLB**（L4 TCP/UDP）|
| `Ingress` (ingressClassName=alb) | annotation 控制細節 | **ALB**（L7 HTTP/HTTPS）|

---

## 綁定流程

```
1. 你 apply K8s yaml
     Service yaml: namespace=monitoring, name=vmauth-nlb, type=LoadBalancer
   或
     Ingress yaml: name=grafana-central-ingress-alb, group.name=...

2. AWS LB Controller (cluster 內 Pod，watch K8s API)
   → 看到新物件 → 呼叫 AWS API: CreateLoadBalancer
   → AWS 隨機產生 NLB/ALB
        - 內部 ID
        - DNS hostname (k8s-monitori-vmauthnl-XXXX.elb.us-east-1.amazonaws.com)

3. Controller 自動在 LB 上打 tag：

   NLB:
     elbv2.k8s.aws/cluster   = <cluster name>
     service.k8s.aws/stack   = <namespace>/<service-name>
     service.k8s.aws/resource = LoadBalancer

   ALB:
     elbv2.k8s.aws/cluster   = <cluster name>
     ingress.k8s.aws/stack   = <group.name>  或 <namespace>/<ingress-name>
     ingress.k8s.aws/resource = LoadBalancer

4. Controller 把 LB DNS 寫回 K8s 物件的 status：
   Service: status.loadBalancer.ingress[0].hostname
   Ingress: status.loadBalancer.ingress[0].hostname

5. kubectl get 才看得到 EXTERNAL-IP/hostname
```

---

## 反向查詢：用 tag 找 LB（給 Route 53 alias 用）

```hcl
# 找 NLB
data "aws_lb" "service" {
  tags = {
    "elbv2.k8s.aws/cluster"  = var.eks_cluster_name
    "service.k8s.aws/stack"  = "monitoring/vmauth-nlb"   # ns/service
  }
}

# 找 ALB
data "aws_lb" "ingress" {
  tags = {
    "elbv2.k8s.aws/cluster" = var.eks_cluster_name
    "ingress.k8s.aws/stack" = "monitor-ingress-controller"   # group.name 或 ns/ingress-name
  }
}
```

`data.aws_lb.xxx.dns_name` / `.zone_id` 就是 LB 的當前 DNS。

---

## 為什麼用 tag 找而不是寫死 DNS

LB 重建（Service/Ingress 被 destroy 重建）→ DNS 換 hash，但 **tag 不變**。terraform 下次 apply 會重新 query，自動拿到新 DNS。

→ Route 53 ALIAS 配 tag-based lookup = LB 重建時 record 自動跟著更新，**下游 hostname 永遠不用改**。

---

## Route 53 ALIAS 完整接線

```
Route 53 record: ti-vmauth-stg.visionone.trendmicro.com
                              ↓ ALIAS to
              dualstack.<NLB DNS>          ← terraform 從 tag 查到，每次 apply 校準
                              ↓
                          NLB IPs (3 個 AZ)
                              ↓
                          NLB target group
                              ↓
                          Pod IPs (target-type=ip)
```

下游（regional Prometheus 之類）只認 hostname。

```
remote_write URL: http://ti-vmauth-stg.visionone.trendmicro.com:443/...
                      ↓ DNS resolve
                      ↓ 永遠拿到當前 NLB IP
```

---

## terraform code 範本（NLB 版）

```hcl
# 1. variables.tf
variable "nlb_domains" {
  type    = map(string)
  default = {}
  # key = FQDN, value = "namespace/service-name"
}

# 2. route53.tf
data "aws_lb" "service" {
  for_each = var.nlb_domains
  tags = {
    "elbv2.k8s.aws/cluster" = var.eks_cluster_name
    "service.k8s.aws/stack" = each.value
  }
}

resource "aws_route53_record" "service_alias" {
  for_each = var.nlb_domains
  zone_id  = data.aws_route53_zone.parent.zone_id
  name     = each.key
  type     = "A"

  alias {
    name                   = "dualstack.${data.aws_lb.service[each.key].dns_name}"
    zone_id                = data.aws_lb.service[each.key].zone_id
    evaluate_target_health = true
  }
}

# 3. caller (terragrunt.hcl)
nlb_domains = {
  "ti-vmauth-stg.visionone.trendmicro.com" = "monitoring/vmauth-nlb"
}
```

ALB 版只需把 `service.k8s.aws/stack` 換成 `ingress.k8s.aws/stack`，value 換成 ingress 的 group.name 或 ns/name。

---

## 對齊清單（任一環錯字就 apply fail）

| 位置 | 值 |
|---|---|
| Service yaml `metadata.namespace` | `monitoring` |
| Service yaml `metadata.name` | `vmauth-nlb` |
| Controller 自動打 tag value | `monitoring/vmauth-nlb` |
| terragrunt `nlb_domains` map value | `monitoring/vmauth-nlb` ← 必須一致 |

---

## 成本

| 項目 | 月費 |
|---|---|
| Route 53 hosted zone | $0.50/zone（共用既有 zone）|
| Route 53 ALIAS record | **$0**（指 ELB 免 query fee）|
| 多寫 terraform code | $0 |

「給 LB 一個固定 hostname，下游永遠不用改」**淨增加成本是 0**。
