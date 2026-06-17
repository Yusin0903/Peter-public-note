---
title: Grafana Microsoft AAD 無法 rotate token 原因
sidebar_position: 20
---
<!-- generated from ~/peter-llm-wiki; edit source there, not here -->

# Grafana Microsoft AAD 無法 rotate token 原因

## 問題背景

在 EKS 上部署 Grafana，希望透過 Microsoft Entra ID (AAD) SSO 登入，且不使用 `client_secret`（需要手動輪替），改用 **Workload Identity** 以取得自動輪替的 token。

目標架構：EKS IRSA → Azure Federated Credentials → AAD OAuth，不需要任何 secret。

---

## 核心原因：Grafana 版本不支援

### Grafana azuread 連接器的實作缺口

Grafana 的 azuread OAuth connector 在 `pkg/login/social/azuread_oauth.go` 處理 token 交換方式。支援的 `clientAuthentication` 模式只有：

| 模式 | 說明 |
|---|---|
| `client_secret_post` | 傳統 client secret（預設）|
| `managed_identity` | Azure IMDS endpoint（只在 Azure VM/AKS 上可用）|
| `workload_identity` | **v12.1.0+ 才有** |

Grafana **v11.x（含 11.6.14）的 switch-case 對 `workload_identity` 落到 default → none**，完全忽略設定，最終仍走無認證路徑，導致 AAD 回傳：

```
AADSTS7000218: The request body must contain the following parameter: 'client_assertion' or 'client_secret'.
```

這是 **原始碼層級的功能缺失**，不是設定問題。

### Helm chart 的 volume 問題（即使版本夠也會踩）

Grafana Helm chart **8.x（對應 Grafana 11.x）** 的 `extraVolumes` loop 不支援 `projected` volume type，靜默 fallback 成 `emptyDir{}`，導致 token 檔根本不存在於容器內。

需要改用 `extraSecretMounts`（該 key 有 projected 分支）才能正確掛入 service account token。

---

## 版本比較

| Grafana App Version | Helm Chart Version | `workload_identity` 支援 | 備註 |
|---|---|---|---|
| ≤ 11.6.x | ≤ 8.10.x | ❌ 無 | `azuread_oauth.go` 無實作，設定值被忽略 |
| 12.0.x | 9.x | ❌ 未確認 | 過渡版本，不建議 |
| **≥ 12.1.0** | **≥ 9.3.5**（建議 10.5.x） | **✅ 有** | PR #104807 引入；chart 10.5.x 對應 appVersion 12.3.1 |

---

## 目前止血方案

維持使用 `client_secret`，secret 值存在 AWS Secrets Manager，Terraform `data` source 讀取後注入 `kubernetes_secret_v1`。

- **輪替流程**：只需更新 SM JSON，再 `terragrunt apply`，不動 code。
- **缺點**：secret 會明文寫進 Terraform state（S3 backend）。若要避免需改用 External Secrets Operator（另案）。

---

## 真正解法：升級 Grafana ≥ v12.1.0

### 升級前必做

1. 用 [`detect-angular-dashboards`](https://grafana.com/blog/2024/09/16/grafana-11-deprecation-of-angularjs/) 掃現有 dashboard — Grafana 12 完全移除 AngularJS plugin，舊 panel 可能壞掉。
2. 確認 `editors_can_admin` 相關設定已移除（Grafana 12 不支援）。
3. chart 10.5.x values 結構與 8.10.x 相容（已用 `helm template` 驗證主要 values key 無 breaking change）。

### 升級後可啟用路徑

EKS IRSA → Azure Federated Credentials → `workload_identity` connector → 完全不需要 `client_secret`，token 由 K8s projected volume 自動輪替。
