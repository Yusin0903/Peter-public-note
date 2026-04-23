---
sidebar_position: 1
---

# Linux 權限

## chmod 數字對應

```bash
chmod 644 file
```

| 數字 | 意義 |
|------|------|
| 第一位 | Owner 權限 |
| 第二位 | Group 權限 |
| 第三位 | Others 權限 |

| 值 | 權限 |
|----|------|
| 4  | read (r) |
| 2  | write (w) |
| 1  | execute (x) |
| 0  | 無權限 (-) |

```
644 = rw-r--r--   Owner 可讀寫，Group/Others 只能讀
700 = rwx------   只有 Owner 可讀寫執行
755 = rwxr-xr-x   Owner 全部，Group/Others 可讀執行
600 = rw-------   只有 Owner 可讀寫（設定檔常用）
```

## 符號寫法（比數字更直觀）

```bash
chmod u+x script.py       # 給 owner 加 execute 權限
chmod g-w file.txt        # 移除 group 的 write 權限
chmod o=r file.txt        # 設定 others 只有 read
chmod a+x script.py       # 所有人都加 execute（a = all）
chmod u+x,g+x script.py   # 多個同時設定
```

> **Python 類比**：Python 的 `os.chmod()` 做同樣的事：
> ```python
> import os
> import stat
>
> # chmod 755
> os.chmod("script.py", 0o755)
>
> # 用 stat 常數（更可讀）
> os.chmod("script.py",
>     stat.S_IRWXU |   # owner: rwx
>     stat.S_IRGRP |   # group: r
>     stat.S_IXGRP |   # group: x
>     stat.S_IROTH |   # others: r
>     stat.S_IXOTH     # others: x
> )
>
> # 查看目前權限
> mode = oct(os.stat("script.py").st_mode)
> print(mode)  # → '0o100755'
> ```

## chown：更改擁有者

```bash
chown user:group file.txt        # 同時改 owner 和 group
chown alice file.txt             # 只改 owner
chown :ml-team model.bin         # 只改 group
chown -R alice:ml-team /models/  # 遞迴改整個目錄
```

> **Python 類比**：
> ```python
> import os
> import pwd
> import grp
>
> # 查詢 uid/gid
> uid = pwd.getpwnam("alice").pw_uid
> gid = grp.getgrnam("ml-team").gr_gid
>
> # chown（需要 root 或 sudo 權限）
> os.chown("file.txt", uid, gid)
> os.chown("file.txt", -1, gid)   # -1 表示不改這個欄位
> ```

## sudo vs su

| 指令 | 用途 | 適合場景 |
|------|------|---------|
| `sudo command` | 以 root 身份執行單一指令 | 需要特權的單次操作 |
| `sudo -u alice command` | 以特定使用者身份執行 | 切換成特定服務帳號 |
| `su -` | 切換成 root shell | 需要連續執行多個特權指令 |
| `su alice` | 切換成 alice 的 shell | 切換成其他使用者 |

```bash
# 常見用法
sudo chmod 600 /etc/secrets.env       # 以 root 改權限
sudo chown root:root /usr/local/bin/  # 以 root 改擁有者
sudo -u www-data python app.py        # 以 www-data 身份跑應用

# su
su -                    # 切換到 root（需要 root 密碼）
su - alice              # 切換到 alice（需要 alice 密碼）
sudo su -               # 用 sudo 切換到 root（不需要 root 密碼，只需要自己有 sudo 權限）
```

**重要差異**：
- `sudo` 是「借用」特權執行一個指令，執行完就回來
- `su` 是「切換身份」，之後所有指令都以那個身份執行
- 容器和服務環境優先用 `sudo -u`，避免長時間以 root 身份執行

## Sticky Bit（防止他人刪除你的檔案）

```bash
chmod +t /tmp          # 設定 sticky bit
ls -ld /tmp            # → drwxrwxrwt（最後的 t 就是 sticky bit）
```

Sticky bit 常用在共享目錄（如 `/tmp`）：即使目錄是 777（所有人可寫），有 sticky bit 的話，**只有檔案的 owner 才能刪除自己的檔案**。

```
/tmp 是 1777（drwxrwxrwt）
alice 建了 /tmp/alice.txt → 只有 alice（或 root）可以刪它
bob 無法刪除 /tmp/alice.txt，即使 /tmp 本身是 777
```

## Docker + 安全性設定範例

部署時想讓一般使用者無法直接讀取設定檔，但 Docker 可以掛載資料：

```
docker-compose.yml  → 700（只有 owner 可讀寫執行）
設定檔目錄/         → 600（只有 owner 可讀寫）
內層資料檔案        → 644（owner 讀寫，其他人可讀）
```

這樣一般使用者沒辦法直接讀取設定，但 Docker container 因為使用者身份可以把資料掛進去使用。

## 推論系統實戰場景

### 場景 1：Python 腳本無法讀取 /dev/nvidia0

```bash
$ python run_inference.py
PermissionError: [Errno 13] Permission denied: '/dev/nvidia0'
```

原因：`/dev/nvidia0` 通常只有 `root` 或 `video` group 的成員才能存取：

```bash
ls -la /dev/nvidia0
# crw-rw---- 1 root video 195, 0 /dev/nvidia0
#             ^^^^^^^^^^^
#             只有 root 和 video group 可以讀寫
```

解法：

```bash
# 方法 1：把你的使用者加入 video group
sudo usermod -aG video $USER
# 重新登入後生效

# 方法 2：在 Dockerfile 裡處理（推薦）
# Dockerfile
RUN groupadd -g 44 video 2>/dev/null || true
RUN usermod -aG video appuser

# 方法 3：docker run 時直接給 GPU 權限（Docker 推薦的方式）
docker run --gpus all --device /dev/nvidia0 my-inference-image
# 或用 nvidia-container-runtime，不需要手動管理 /dev/nvidia0 權限
```

> **Python 類比**：
> ```python
> import os
>
> # 檢查目前使用者的 group
> import subprocess
> result = subprocess.run(["groups"], capture_output=True, text=True)
> print(result.stdout)   # 看有沒有 'video' 在裡面
>
> # 或用 grp 模組
> import grp
> groups = [g.gr_name for g in grp.getgrall()
>           if os.getlogin() in g.gr_mem]
> print(groups)
> ```

### 場景 2：Container 非 root 使用者（安全最佳實踐）

以 root 身份跑 container 是危險的：如果容器被攻破，攻擊者直接拿到 host 的 root。

```dockerfile
# ❌ 壞做法：以 root 跑
FROM python:3.11-slim
COPY . /app
CMD ["python", "/app/inference.py"]
# 預設以 root 身份跑

# ✅ 好做法：建立非 root 使用者
FROM python:3.11-slim

# 建立專用使用者（uid 1000 是慣例）
RUN groupadd -r appgroup && useradd -r -g appgroup -u 1000 appuser

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

# 設定正確的檔案擁有者
RUN chown -R appuser:appgroup /app

# 切換到非 root 使用者
USER appuser

CMD ["python", "inference.py"]
```

> **Python 類比（檢查目前使用者）**：
> ```python
> import os
> import pwd
>
> uid = os.getuid()
> username = pwd.getpwuid(uid).pw_name
> print(f"目前以 {username}（uid={uid}）執行")
>
> if uid == 0:
>     print("警告：以 root 執行，安全風險！")
> ```

### 場景 3：模型權重檔案的權限設定

模型權重檔（`.pt`, `.bin`, `.safetensors`）通常很大，要平衡安全性和可存取性：

```bash
# 建議設定
chmod 640 /models/gpt2/pytorch_model.bin
#         rw-r-----
#         owner 可讀寫，group 可讀，others 無法存取

chown appuser:ml-team /models/gpt2/pytorch_model.bin
# 擁有者是 appuser，ml-team 的成員都可以讀取

# 整個模型目錄
chmod 750 /models/gpt2/
#         rwxr-x---
#         owner 全部，group 可讀執行（進入目錄），others 無

# 批次設定整個模型目錄
find /models/ -type f -exec chmod 640 {} \;   # 所有檔案 640
find /models/ -type d -exec chmod 750 {} \;   # 所有目錄 750
chown -R appuser:ml-team /models/
```

> **Python 類比**：
> ```python
> import os
> import pathlib
>
> models_dir = pathlib.Path("/models")
>
> # 批次設定權限
> for f in models_dir.rglob("*"):
>     if f.is_file():
>         os.chmod(f, 0o640)    # rw-r-----
>     elif f.is_dir():
>         os.chmod(f, 0o750)    # rwxr-x---
>
> # 檢查是否可讀
> model_path = "/models/gpt2/pytorch_model.bin"
> if not os.access(model_path, os.R_OK):
>     raise PermissionError(f"無法讀取模型檔案：{model_path}，請確認權限設定")
> ```

### 場景 4：Script 需要 execute 權限才能直接執行

```bash
# ❌ 沒有 execute 權限
chmod 644 run_inference.sh
./run_inference.sh
# bash: ./run_inference.sh: Permission denied

# ✅ 加上 execute 權限
chmod 755 run_inference.sh
./run_inference.sh   # 可以執行了

# Python 腳本同樣需要 execute 權限才能直接執行
chmod 755 inference.py
./inference.py       # 需要有 #!/usr/bin/env python3 這行
```

## 常用權限數字速查

| 權限 | 數字 | 適用場景 |
|------|------|---------|
| `rw-------` | 600 | 私鑰、密碼檔（只有 owner 能讀） |
| `rw-r--r--` | 644 | 一般設定檔、靜態資源 |
| `rw-rw----` | 660 | 需要 group 共同讀寫的檔案 |
| `rw-r-----` | 640 | 模型權重（owner 讀寫，group 讀） |
| `rwx------` | 700 | 只有 owner 能用的目錄或腳本 |
| `rwxr-xr-x` | 755 | 可執行程式、公開目錄 |
| `rwxr-x---` | 750 | 需要 group 才能進入的目錄 |
| `rwxrwxrwt` | 1777 | 共享暫存目錄（如 /tmp） |
