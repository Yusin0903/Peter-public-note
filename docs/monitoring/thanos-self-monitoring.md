---
title: Thanos 自我監控方式
sidebar_position: 21
---
<!-- generated from ~/peter-llm-wiki; edit source there, not here -->

# Thanos 自我監控方式

Thanos 每個元件（sidecar、querier、store-gateway 等）都會自己開兩個 port：

| Port | 用途 |
|---|---|
| `:10901` | gRPC — 給 Querier 來撈資料用（StoreAPI）|
| `:10902` | HTTP — 暴露自己的 `/metrics`，給 Prometheus 來 scrape |

所以 Thanos 監控自己的方式，**不是** 直接打 sidecar 的 gRPC 問「你還活著嗎」，而是跟監控其他服務一樣，讓 Prometheus 去 scrape `:10902` 的 metrics。

然後這份 metrics 再透過 sidecar 傳到 S3、讓 Querier 查得到，就變成「Thanos 透過自己的架構監控自己」。

簡單說：**store port 是 data path，metrics port 是 monitoring path，兩條路分開走。**
