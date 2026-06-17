---
title: "Monorepo：不是 Design Pattern，是 Repo 管理策略"
sidebar_position: 1
---
<!-- generated from ~/peter-llm-wiki; edit source there, not here -->

# Monorepo：不是 Design Pattern，是 Repo 管理策略

今天第一次聽到 **Monorepo** 這個詞。

一開始我還以為同事在講 "moto repo"，後來才知道是 **mono-repo**：

- `mono` = 單一
- `repo` = repository

所以 Monorepo 的意思很直白：**把多個專案、服務、套件，放在同一個 repository 裡管理**。

---

## 先講結論

Monorepo 不是 design pattern。

Design pattern 比較像 Singleton、Factory、Observer 這種東西，主要是在講「程式碼裡面的物件或模組要怎麼設計」。

Monorepo 講的是另一個層級：**程式碼要放在哪裡、repo 要怎麼切、不同服務要怎麼一起管理**。

比較精準的說法是：

- **Repository strategy**
- **Code organization strategy**
- 或者把它看成一種工程管理上的架構選擇

我先把它放在 Design Pattern 這區，是因為它跟「軟體怎麼組織」很有關，但要記得它不是傳統 GoF design pattern 那種東西。

---

## Monorepo vs Polyrepo

平常比較直覺的做法通常是 **Polyrepo**，也有人叫 Multi-repo。

也就是每個服務一個 repo：

```txt
app-repo/
worker-repo/
shared-lib-repo/
```

Monorepo 則是把它們放在同一個 repo 裡：

```txt
my-project/
├── apps/
│   ├── app/
│   └── worker/
├── packages/
│   └── shared/      # 共用 types、models、utils
├── package.json
└── ...
```

簡單說：

| 策略 | 做法 |
|---|---|
| Polyrepo | app 一個 repo、worker 一個 repo、shared lib 也可能一個 repo |
| Monorepo | app、worker、shared package 都放在同一個 repo 裡 |

---

## 它解決什麼問題？

以 `app + worker` 這種場景來看，兩邊很常會共用東西：

- data model
- type 定義
- protobuf schema
- validation rule
- 共用 utils

如果這些東西分散在不同 repo，就很容易遇到版本同步問題。

例如 app 改了某個 field，但 worker 還沒更新，就可能變成：

```txt
app 已經送出 new_field
worker 還只認得 old_field
→ runtime 才爆
```

Monorepo 的好處是可以把這種跨服務修改放在同一個 PR 裡：

```txt
改 shared type
改 app
改 worker
CI 一起跑
一次 merge
```

這就是很常被提到的 **atomic commit**。

意思是：相關的修改可以在同一個 commit / PR 裡一起完成，不會卡在「A repo 已經改了，但 B repo 還沒跟上」的中間狀態。

---

## Monorepo 的好處

### 共用程式碼比較自然

shared type、model、utils 可以直接放在 `packages/shared` 之類的地方。

不用每次改一個 type 就發新版套件，也不用到處更新 dependency version。

### 跨服務重構比較舒服

如果今天要把欄位從 `user_id` 改成 `account_id`，Polyrepo 可能要開好幾個 PR。

Monorepo 可以一次改：

- app
- worker
- shared package
- tests

### CI 和工具鏈比較一致

可以統一：

- lint
- formatter
- test command
- build command
- dependency policy

這對團隊來說很有感，因為規則不用散在很多 repo 裡各自長出不同版本。

---

## Monorepo 的代價

Monorepo 不是免費午餐。

### Repo 會變大

專案越多，repo 就越大。

clone、install dependency、跑 CI 都可能變慢。

大型公司像 Google、Meta 可以靠內部工具硬扛，但一般團隊不能直接照抄那個規模的玩法。

### 權限控制會變麻煩

Polyrepo 很容易做到：

```txt
只給某人看 app repo
不給他看 worker repo
```

Monorepo 因為東西都在同一個 repo，權限通常會變粗。

如果有很強的隔離需求，Monorepo 反而不一定適合。

### CI 需要工具支援

如果每次只改 app 的一行 code，CI 卻把 app、worker、shared、docs 全部重跑，成本會很高。

所以 Monorepo 通常會搭配工具做 **affected detection**。

也就是只 build / test 這次真的被影響到的部分。

---

## 常見工具

JS / TS 圈常見：

- Nx
- Turborepo
- pnpm workspaces
- Lerna

比較大型或多語言的場景：

- Bazel
- Buck

這些工具的重點不是只是「把資料夾放在一起」，而是幫你處理：

- workspace dependency
- build cache
- task pipeline
- affected detection
- CI 加速

---

## 不要跟 Monolith 搞混

這個很容易混。

**Monorepo 是程式碼放哪裡。**

**Monolith 是 runtime 長怎樣。**

所以這兩個不是同一個維度。

你可以有：

| Repo 策略 | Runtime 架構 |
|---|---|
| Monorepo | 一個 monolith app |
| Monorepo | 很多 microservices |
| Polyrepo | 很多 microservices |
| Polyrepo | 一個 app 拆成很多 repo |

也就是說：**用 Monorepo 不代表你的系統就是 Monolith**。

你完全可以用一個 repo 管很多個 services。

---

## 我的理解

我會先這樣記：

> Monorepo 不是 design pattern，而是一種 repo 管理策略。
> 它適合用在多個服務需要共用 code、共用 type、一起重構的情境。
> 但如果 repo 很大、權限要切很細、CI 沒有工具支援，就會開始痛。

以 `app + worker` 這種組合來說，如果兩邊真的常常共用 model / type / schema，Monorepo 會是很合理的選擇。

但如果 app 和 worker 幾乎沒有共用東西，只是部署上有關係，那就不一定需要硬合在一起。
