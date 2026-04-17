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

範例：
```
644 = rw-r--r--   Owner 可讀寫，Group/Others 只能讀
700 = rwx------   只有 Owner 可讀寫執行
755 = rwxr-xr-x   Owner 全部，Group/Others 可讀執行
```

## Docker + 安全性設定範例

部署時想讓一般使用者無法直接讀取設定檔，但 Docker 可以掛載資料：

```
docker-compose.yml  → 700（只有 owner 可讀寫執行）
設定檔目錄/         → 600（只有 owner 可讀寫）
內層資料檔案        → 644（owner 讀寫，其他人可讀）
```

這樣一般使用者沒辦法直接讀取設定，但 Docker container 因為使用者身份可以把資料掛進去使用。
