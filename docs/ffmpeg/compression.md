---
sidebar_position: 1
---

# FFmpeg 影片壓縮

## 基本壓縮指令

```bash
ffmpeg -i input.mp4 \
  -vf "scale=854:480" \
  -c:v libx264 -profile:v baseline -pix_fmt yuv420p -level 4.0 \
  -crf 35 -g 150 -force_key_frames "expr:gte(n,n_forced*150)" \
  -c:a aac -b:a 96k -ar 44100 -ac 2 \
  -movflags +faststart \
  output.mp4
```

## 加上靜音音軌（原始影片無聲）

```bash
ffmpeg -i input.mp4 \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
  -c:v libx264 -profile:v baseline -pix_fmt yuv420p \
  -crf 29 -preset fast \
  -c:a aac -b:a 96k -ar 44100 -ac 2 \
  -shortest -movflags +faststart \
  output.mp4
```

## CRF 參數說明

CRF（Constant Rate Factor）控制畫質與檔案大小的平衡：

| CRF 值 | 畫質 | 檔案大小 |
|--------|------|----------|
| 18-23 | 高畫質 | 大 |
| 28-32 | 中等 | 中 |
| 35+ | 低畫質 | 小 |

> **規律：** CRF 每增加 6，檔案大小約減少一半。

## 壓縮效果參考

- `scale=854:480` + `crf=35` → 壓縮剩約 7%（2.6MB → 184KB）
- `scale=840:480` + `crf=32` → 壓縮剩約 20%

## 標記已壓縮的影片

加上 metadata comment 標記，方便之後判斷是否已壓縮：

```bash
ffmpeg -i input.mp4 \
  -vf "scale=840:480" \
  -crf 32 -c:v libx264 -c:a aac -b:a 96k \
  -metadata comment=compressed \
  output.mp4
```

查看 comment：

```bash
ffprobe -v error \
  -show_entries format_tags=comment \
  -of default=noprint_wrappers=1 \
  output.mp4
```
