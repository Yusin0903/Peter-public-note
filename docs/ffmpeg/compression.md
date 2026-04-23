---
sidebar_position: 1
---

# FFmpeg 影片壓縮與推論前處理

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

---

## Python subprocess 包裝 ffmpeg

在推論系統中通常用 Python 呼叫 ffmpeg，而不是直接寫 shell script：

```python
import subprocess
import shutil
from pathlib import Path


def compress_video(
    input_path: str,
    output_path: str,
    scale: str = "854:480",
    crf: int = 35,
) -> None:
    """壓縮影片，適合推論前的前處理。"""
    cmd = [
        "ffmpeg",
        "-i", input_path,
        "-vf", f"scale={scale}",
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        "-crf", str(crf),
        "-c:a", "aac",
        "-b:a", "96k",
        "-movflags", "+faststart",
        "-y",           # 覆蓋輸出檔案（不詢問）
        output_path,
    ]

    result = subprocess.run(
        cmd,
        capture_output=True,   # 捕捉 stdout/stderr
        text=True,
    )

    if result.returncode != 0:
        raise RuntimeError(
            f"ffmpeg 失敗（return code {result.returncode}）\n"
            f"stderr: {result.stderr}"
        )


def check_ffmpeg_installed() -> bool:
    """確認系統有安裝 ffmpeg。"""
    return shutil.which("ffmpeg") is not None
```

### 非同步版本（推論系統常見）

```python
import asyncio
from pathlib import Path


async def compress_video_async(
    input_path: str,
    output_path: str,
    crf: int = 35,
) -> None:
    """非同步版本，不阻塞事件迴圈。"""
    cmd = [
        "ffmpeg", "-i", input_path,
        "-vf", "scale=854:480",
        "-c:v", "libx264",
        "-crf", str(crf),
        "-y", output_path,
    ]

    # asyncio.create_subprocess_exec 不阻塞事件迴圈
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await proc.communicate()

    if proc.returncode != 0:
        raise RuntimeError(f"ffmpeg 失敗: {stderr.decode()}")
```

---

## 推論常用場景

### 場景 1：從影片擷取幀（Frame Extraction）

影像分類、目標偵測推論時，需要先把影片切成圖片：

```bash
# 每秒擷取 1 幀
ffmpeg -i input.mp4 -vf "fps=1" frames/frame_%04d.jpg

# 擷取特定時間段（第 10 秒到第 20 秒）
ffmpeg -i input.mp4 -ss 10 -to 20 -vf "fps=1" frames/frame_%04d.jpg

# 擷取所有幀（高頻率，適合動作分析）
ffmpeg -i input.mp4 -vf "fps=30" frames/frame_%04d.jpg

# 擷取 + 縮放（節省儲存空間）
ffmpeg -i input.mp4 -vf "fps=1,scale=224:224" frames/frame_%04d.jpg
```

> **Python 包裝**：
> ```python
> import subprocess
> from pathlib import Path
>
>
> def extract_frames(
>     video_path: str,
>     output_dir: str,
>     fps: float = 1.0,
>     resize: tuple[int, int] | None = None,
> ) -> list[str]:
>     """
>     從影片擷取幀，回傳所有幀的路徑列表。
>     適合批次推論前的前處理。
>     """
>     Path(output_dir).mkdir(parents=True, exist_ok=True)
>
>     vf_filters = [f"fps={fps}"]
>     if resize:
>         vf_filters.append(f"scale={resize[0]}:{resize[1]}")
>
>     output_pattern = str(Path(output_dir) / "frame_%04d.jpg")
>
>     cmd = [
>         "ffmpeg", "-i", video_path,
>         "-vf", ",".join(vf_filters),
>         "-y", output_pattern,
>     ]
>
>     subprocess.run(cmd, capture_output=True, check=True)
>
>     # 回傳所有產生的幀路徑，依順序排列
>     return sorted(Path(output_dir).glob("frame_*.jpg"))
>
>
> # 使用範例
> frames = extract_frames(
>     "video.mp4",
>     "output/frames/",
>     fps=1.0,
>     resize=(224, 224),   # ResNet/ViT 常用尺寸
> )
>
> for frame_path in frames:
>     result = model.predict(str(frame_path))
> ```

### 場景 2：影像縮放與正規化（Image Resize for Inference）

推論模型通常要求固定輸入尺寸：

```bash
# 縮放到固定大小（不保持比例）
ffmpeg -i input.mp4 -vf "scale=224:224" output.mp4

# 縮放後保持比例，不足的部分補黑邊（letterbox）
ffmpeg -i input.mp4 \
  -vf "scale=224:224:force_original_aspect_ratio=decrease,pad=224:224:(ow-iw)/2:(oh-ih)/2" \
  output.mp4

# 轉換像素格式（推論框架通常要 RGB，ffmpeg 預設是 YUV）
ffmpeg -i input.mp4 -pix_fmt rgb24 -vf "scale=224:224" output.mp4

# 擷取單張幀當推論輸入
ffmpeg -i input.mp4 -ss 00:00:01 -vframes 1 -vf "scale=224:224" frame.jpg
```

> **Python 包裝（搭配 numpy）**：
> ```python
> import subprocess
> import numpy as np
> from pathlib import Path
>
>
> def video_to_frames_numpy(
>     video_path: str,
>     target_size: tuple[int, int] = (224, 224),
>     fps: float = 1.0,
> ) -> np.ndarray:
>     """
>     從影片讀取幀，直接回傳 numpy array（推論用）。
>     shape: (N, H, W, 3)，dtype: uint8，RGB 格式
>     """
>     w, h = target_size
>     cmd = [
>         "ffmpeg", "-i", video_path,
>         "-vf", f"fps={fps},scale={w}:{h}",
>         "-f", "rawvideo",
>         "-pix_fmt", "rgb24",
>         "-",           # 輸出到 stdout（不存檔）
>     ]
>
>     result = subprocess.run(cmd, capture_output=True, check=True)
>
>     # 從 raw bytes 轉成 numpy array
>     raw = np.frombuffer(result.stdout, dtype=np.uint8)
>     n_frames = len(raw) // (h * w * 3)
>     frames = raw.reshape(n_frames, h, w, 3)
>
>     return frames   # (N, 224, 224, 3)
>
>
> # 使用範例（搭配 PyTorch）
> import torch
> import torchvision.transforms as T
>
> frames = video_to_frames_numpy("video.mp4", target_size=(224, 224))
> tensor = torch.from_numpy(frames).permute(0, 3, 1, 2).float() / 255.0
> # shape: (N, 3, 224, 224)，已正規化到 [0, 1]
> ```

### 場景 3：音訊轉換（語音模型前處理）

語音辨識模型（Whisper、Wav2Vec 等）通常要求特定音訊格式：

```bash
# 轉成 Whisper 要求的格式：16kHz, mono, float32
ffmpeg -i input.mp4 \
  -ar 16000 \       # sample rate = 16kHz
  -ac 1 \           # mono（單聲道）
  -f wav \          # WAV 格式
  output.wav

# 只擷取音軌（去掉影像）
ffmpeg -i input.mp4 -vn -acodec pcm_s16le -ar 16000 -ac 1 output.wav

# 轉成 mp3（壓縮，傳輸用）
ffmpeg -i input.wav -codec:a libmp3lame -b:a 128k output.mp3

# 剪取特定時段的音訊
ffmpeg -i input.mp4 -ss 10 -to 30 -vn -ar 16000 -ac 1 segment.wav
```

> **Python 包裝（搭配 Whisper）**：
> ```python
> import subprocess
> import numpy as np
> import tempfile
> from pathlib import Path
>
>
> def extract_audio_for_whisper(
>     input_path: str,
>     sample_rate: int = 16000,
> ) -> np.ndarray:
>     """
>     擷取音訊並轉成 Whisper 需要的格式。
>     回傳 float32 numpy array，shape: (N,)
>     """
>     with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
>         tmp_path = tmp.name
>
>     cmd = [
>         "ffmpeg", "-i", input_path,
>         "-ar", str(sample_rate),
>         "-ac", "1",           # mono
>         "-f", "f32le",        # 直接輸出 float32 raw bytes
>         "-",                  # stdout
>     ]
>
>     result = subprocess.run(cmd, capture_output=True, check=True)
>     audio = np.frombuffer(result.stdout, dtype=np.float32)
>     return audio
>
>
> # 使用範例（搭配 OpenAI Whisper）
> import whisper
>
> model = whisper.load_model("base")
> audio = extract_audio_for_whisper("video.mp4")
> result = model.transcribe(audio)
> print(result["text"])
> ```

### 場景 4：取得影片資訊（推論前檢查）

```bash
# 用 ffprobe 取得影片詳細資訊
ffprobe -v error \
  -show_entries stream=width,height,r_frame_rate,duration \
  -of json \
  input.mp4
```

> **Python 包裝**：
> ```python
> import subprocess
> import json
>
>
> def get_video_info(video_path: str) -> dict:
>     """取得影片的基本資訊，推論前用來驗證輸入。"""
>     cmd = [
>         "ffprobe", "-v", "error",
>         "-show_entries", "stream=width,height,r_frame_rate,duration,codec_name",
>         "-show_entries", "format=duration,size",
>         "-of", "json",
>         video_path,
>     ]
>
>     result = subprocess.run(cmd, capture_output=True, text=True, check=True)
>     info = json.loads(result.stdout)
>
>     video_stream = next(
>         (s for s in info["streams"] if s.get("codec_name") in ("h264", "hevc", "vp9")),
>         info["streams"][0] if info["streams"] else {}
>     )
>
>     # 解析 frame rate（格式是 "30000/1001" 這樣的分數）
>     fps_str = video_stream.get("r_frame_rate", "0/1")
>     num, den = map(int, fps_str.split("/"))
>     fps = num / den if den != 0 else 0
>
>     return {
>         "width": video_stream.get("width"),
>         "height": video_stream.get("height"),
>         "fps": round(fps, 2),
>         "duration": float(info.get("format", {}).get("duration", 0)),
>         "size_bytes": int(info.get("format", {}).get("size", 0)),
>     }
>
>
> # 使用範例
> info = get_video_info("input.mp4")
> print(info)
> # → {"width": 1920, "height": 1080, "fps": 29.97, "duration": 120.5, "size_bytes": 52428800}
>
> # 推論前驗證
> if info["width"] < 224 or info["height"] < 224:
>     raise ValueError(f"影片解析度太低：{info['width']}x{info['height']}")
> ```
