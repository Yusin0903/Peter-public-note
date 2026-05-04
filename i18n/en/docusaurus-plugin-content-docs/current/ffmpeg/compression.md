---
sidebar_position: 1
---

# FFmpeg Video Compression

## Basic Compression

```bash
ffmpeg -i input.mp4 \
  -vf "scale=854:480" \
  -c:v libx264 -profile:v baseline -pix_fmt yuv420p -level 4.0 \
  -crf 35 -g 150 -force_key_frames "expr:gte(n,n_forced*150)" \
  -c:a aac -b:a 96k -ar 44100 -ac 2 \
  -movflags +faststart \
  output.mp4
```

## Add Silent Audio Track (for silent source videos)

```bash
ffmpeg -i input.mp4 \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
  -c:v libx264 -profile:v baseline -pix_fmt yuv420p \
  -crf 29 -preset fast \
  -c:a aac -b:a 96k -ar 44100 -ac 2 \
  -shortest -movflags +faststart \
  output.mp4
```

## CRF Parameter

CRF (Constant Rate Factor) controls the quality vs file size trade-off:

| CRF Value | Quality | File Size |
|-----------|---------|-----------|
| 18–23 | High quality | Large |
| 28–32 | Medium | Medium |
| 35+ | Low quality | Small |

> **Rule of thumb:** Every +6 CRF roughly halves the file size.

## Compression Results Reference

- `scale=854:480` + `crf=35` → ~7% of original (2.6MB → 184KB)
- `scale=840:480` + `crf=32` → ~20% of original

## Tagging Compressed Videos

Add a metadata comment to mark the file as compressed for later detection:

```bash
ffmpeg -i input.mp4 \
  -vf "scale=840:480" \
  -crf 32 -c:v libx264 -c:a aac -b:a 96k \
  -metadata comment=compressed \
  output.mp4
```

Check the comment:

```bash
ffprobe -v error \
  -show_entries format_tags=comment \
  -of default=noprint_wrappers=1 \
  output.mp4
```
