---
title: "Terraform Import vs Git Pull/Push 的差別"
tags: [terraform, git, devops, infrastructure]
created: 2026-06-17
---
<!-- generated from ~/peter-llm-wiki; edit source there, not here -->

## 一句話總結

`terragrunt import` 改 **Terraform state**（存在 S3）；`git pull/push` 改 **程式碼**（存在 GitHub）。兩者完全獨立，互不影響。

## 對照表

| 指令 | 操作對象 | 方向 | 改變什麼 |
|---|---|---|---|
| `terragrunt import` | Terraform state（S3 的 `terraform.tfstate`）| AWS 既有資源 → 寫進 state | state 多一筆「code 地址 ↔ AWS 真實資源」對應 |
| `git pull` | git repo（程式碼/歷史）| 遠端 GitHub → 你本機 | 本機 code 變成最新 |
| `git push` | git repo（程式碼/歷史）| 你本機 → 遠端 GitHub | 遠端 code 收到你的 commit |

## 關鍵：state 和 git 是兩套獨立的東西

- **git（pull/push）** 管的是 `.tf` 程式碼——你寫的宣告、commit 歷史。存在 GitHub。
- **state（import）** 管的是「Terraform 認為現在 AWS 有什麼」——資源清單與 metadata。存在 S3。

兩者不互通：
- `git push` 把 code 推上去，不會動 AWS、不會動 state。
- `terragrunt import` 把 AWS 資源納入 state，不會動 git、不會改你的 `.tf` 檔。

## 為什麼三個都要做

| 缺少 | 後果 |
|---|---|
| 沒改 code + push | CI 跑舊 code，邏輯沒更新 |
| 沒 import | `apply` 撞既有 AWS 資源，拋 `ResourceExistsException` |

完整流程：
1. **改 `.tf` code** → 這是改宣告。
2. **`git push`** → 把 code 推上 GitHub，讓 workflow/CI 能抓到新邏輯。AWS / state 完全沒動。
3. **`terragrunt import`** → 把 AWS 既有資源寫進 S3 state，讓 `apply` 不會嘗試重建。git / code 完全沒動。

驗證：
- `import` 後 `git status` 是乾淨的（import 不改任何檔）
- `push` 後 S3 state 也沒變（push 不碰 state）

## 記憶口訣

> **push** 是給「人/CI 看的程式碼」；**import** 是給「Terraform 看的現況清單」。
