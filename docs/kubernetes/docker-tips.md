---
sidebar_position: 10
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

---

## Multi-stage Build — Python inference image 瘦身

Python inference image 最大的問題：build 工具（gcc、cmake、build-essential）和 dev dependency 被打包進去，image 動輒 10GB+。Multi-stage build 讓你用一個大 image 編譯，再把成品複製到小 image 裡。

### 基本 Python inference Dockerfile

```dockerfile
# ========== Stage 1: Builder ==========
FROM python:3.11-slim AS builder

WORKDIR /build

# 安裝 build 工具（只在 builder stage 需要）
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    cmake \
    git \
    && rm -rf /var/lib/apt/lists/*

# 複製 requirements 並安裝（利用 Docker layer cache）
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt
# --prefix=/install 把安裝的 package 都放到 /install，方便複製到下一個 stage

# ========== Stage 2: Final (Runtime) ==========
FROM python:3.11-slim AS final

WORKDIR /app

# 只複製 runtime 需要的系統套件
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \       # OpenMP runtime（PyTorch 需要）
    curl \           # healthcheck 用
    && rm -rf /var/lib/apt/lists/*

# 從 builder stage 複製已安裝的 Python packages
COPY --from=builder /install /usr/local

# 複製應用程式 code
COPY src/ ./src/
COPY config/ ./config/

# 設定環境
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# 非 root 用戶跑（安全最佳實踐）
RUN useradd --create-home --shell /bin/bash appuser
USER appuser

EXPOSE 8080

# 用 exec form（不用 shell form），確保 SIGTERM 正確傳遞
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

**Image 大小對比**：
- 不用 multi-stage（pytorch + build tools）：~8GB
- Multi-stage：~4GB（省了 build tools 和 cache）

---

## GPU Dockerfile

GPU inference 需要 NVIDIA CUDA base image。關鍵是選對 CUDA 版本，要跟機器上的 NVIDIA driver 版本對齊。

### CUDA 版本對應

```
NVIDIA Driver 版本 → 支援的最高 CUDA 版本
  525.x  → CUDA 12.0
  535.x  → CUDA 12.2
  545.x  → CUDA 12.3
  550.x  → CUDA 12.4
  560.x  → CUDA 12.6

查詢你的 driver 版本：
  nvidia-smi | grep "Driver Version"
  kubectl exec <pod> -- nvidia-smi
```

### GPU inference Dockerfile

```dockerfile
# ========== Stage 1: Builder ==========
# 用 CUDA devel image 編譯（包含 nvcc 和 headers）
FROM nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04 AS builder

WORKDIR /build

# 防止 apt-get 互動式提示
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3.11-dev \
    python3-pip \
    gcc \
    g++ \
    cmake \
    git \
    && rm -rf /var/lib/apt/lists/*

# 讓 python 和 pip 指向 3.11
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1
RUN update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ========== Stage 2: Final (Runtime) ==========
# 用 runtime image（比 devel 小很多，沒有 nvcc）
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04 AS final

WORKDIR /app

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3-pip \
    libgomp1 \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1

# 從 builder 複製已安裝的 packages
COPY --from=builder /install /usr/local

COPY src/ ./src/
COPY config/ ./config/

ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1
ENV CUDA_VISIBLE_DEVICES=0

# inference server 通常需要 root 或特定 UID 存取 GPU
# 如果不需要，用非 root 更安全
RUN useradd --create-home --uid 1000 appuser
USER appuser

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD curl -f http://localhost:8080/health/live || exit 1

CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

**CUDA image 類型選擇**：

| Image 類型 | 包含 | 大小 | 用途 |
|---|---|---|---|
| `base` | CUDA runtime only | 最小 | 只跑 CUDA binary |
| `runtime` | CUDA runtime + cuDNN | 中 | 跑 PyTorch/TensorFlow |
| `devel` | runtime + nvcc + headers | 最大 | 編譯 CUDA extension |

**原則**：build stage 用 `devel`，final stage 用 `runtime`。

---

## .dockerignore 最佳實踐

`.dockerignore` 是 Docker build context 的過濾規則。沒有它，`docker build` 會把整個目錄（包含 model weights、.git、venv）都送進去，讓 build 變慢還可能洩漏機密。

```
# .dockerignore

# Python 虛擬環境和 cache（絕對不要打包進去）
__pycache__/
*.py[cod]
*$py.class
*.pyc
.Python
venv/
env/
.venv/
pip-log.txt

# 測試和 CI
.pytest_cache/
.coverage
coverage.xml
htmlcov/
.tox/
tests/
test_*/

# 開發工具設定
.git/
.gitignore
.env              # 機密！絕對不能打包
.env.*            # .env.local, .env.staging 都要排除
*.env

# Model weights（通常很大，從 S3 下載，不打包進 image）
*.bin
*.pt
*.pth
*.onnx
*.safetensors
models/
weights/
checkpoints/

# 文件和筆記
*.md
docs/
notebooks/
*.ipynb

# IDE 設定
.vscode/
.idea/
*.swp
*.swo
.DS_Store

# Docker 相關（避免遞迴）
Dockerfile*
docker-compose*.yml
.dockerignore

# 暫存檔
*.log
*.tmp
tmp/
```

**為什麼 .dockerignore 對 inference 特別重要**：
- model weights 動輒幾 GB，不應該打包進 image（從 S3 或 model registry 下載）
- `.env` 裡可能有 API key，一旦打包進 image 推到 ECR 就完了
- `venv/` 打包進去會覆蓋 image 裡正確安裝的 packages

---

## NVIDIA GPU 設定（Docker Compose）

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

---

## Jetson 影片播放

Jetson 裝置上用 Firefox 播放影片時，可能出現「no compatible media can play」錯誤。

原因是 Jetson 的 Firefox 不支援某些 H.264 codec profile。解法：
- 用 ffmpeg 重新壓縮為 `baseline` profile：`-profile:v baseline`
- 或改用 Chromium

---

## 常用 Docker 指令速查

```bash
# Build（加 --no-cache 強制重新 build）
docker build -t my-inference:v1.0 .
docker build --no-cache -t my-inference:v1.0 .

# 指定 stage（只 build 到 builder stage，debug 用）
docker build --target builder -t my-inference:debug .

# 查看 image 各 layer 大小（找出哪個 layer 最肥）
docker image history my-inference:v1.0

# 進入 container debug（不跑預設 CMD）
docker run --rm -it --gpus all my-inference:v1.0 /bin/bash

# 掛載本地 code 進去開發（不用重 build）
docker run --rm -it \
  --gpus all \
  -v $(pwd)/src:/app/src \
  -p 8080:8080 \
  my-inference:v1.0

# 推到 ECR
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin \
  123456789.dkr.ecr.us-west-2.amazonaws.com

docker tag my-inference:v1.0 \
  123456789.dkr.ecr.us-west-2.amazonaws.com/my-inference:v1.0

docker push 123456789.dkr.ecr.us-west-2.amazonaws.com/my-inference:v1.0
```
