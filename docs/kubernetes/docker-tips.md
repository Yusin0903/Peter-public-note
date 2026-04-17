---
sidebar_position: 2
---

# Docker 常用指令與注意事項

## 清理資源

刪除所有未被使用的資源（images、containers、volumes、networks、build cache）：

```bash
docker system prune -a
```

也清掉 volumes：

```bash
docker system prune -a --volumes
```

## NVIDIA GPU 設定

Docker Compose 指定 NVIDIA GPU 時，務必加上 `driver: nvidia`，否則在較新版本（550+）的驅動會報錯：

```yaml
# ✅ 正確寫法
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu]

# ❌ 不指定 driver（在 NVIDIA driver 550+ 會報錯）
deploy:
  resources:
    reservations:
      devices:
        - capabilities: [gpu]
```

| NVIDIA Driver 版本 | 不指定 driver 的行為 |
|-------------------|---------------------|
| 535 | 可以自動找到 |
| 550+ | 報錯，必須明確指定 `driver: nvidia` |

## Jetson 影片播放

Jetson 裝置上用 Firefox 播放影片時，可能出現「no compatible media can play」錯誤。

原因是 Jetson 的 Firefox 不支援某些 H.264 codec profile。解法：
- 用 ffmpeg 重新壓縮為 `baseline` profile：`-profile:v baseline`
- 或改用 Chromium
