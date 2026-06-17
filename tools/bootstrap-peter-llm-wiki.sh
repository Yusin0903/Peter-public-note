#!/usr/bin/env bash
set -euo pipefail

TARGET="${LLM_WIKI_HOME:-$HOME/peter-llm-wiki}"
PUBLIC_NOTE="${PUBLIC_NOTE_HOME:-$HOME/Peter_public_note}"
TREND_NOTE="${TREND_NOTE_HOME:-$HOME/peter-trend-note}"

if [[ ! -d "$PUBLIC_NOTE" ]]; then
  echo "Public note repo not found: $PUBLIC_NOTE" >&2
  exit 1
fi

if [[ ! -d "$TREND_NOTE" ]]; then
  echo "Trend note repo not found: $TREND_NOTE" >&2
  exit 1
fi

mkdir -p "$TARGET"/{wiki/public,wiki/internal,raw/imports,raw/inbox,tasks,scripts,.claude/commands}

cat > "$TARGET/.gitignore" <<'EOF'
.DS_Store
.obsidian/workspace.json
.obsidian/workspace-mobile.json
node_modules/
.cache/
EOF

cat > "$TARGET/README.md" <<'EOF'
# Peter LLM Wiki

This repo is Peter's canonical note system.

- `~/peter-llm-wiki` is the source of truth.
- `~/Peter_public_note` is only a Docusaurus export target.
- Notes are edited here first, then exported when needed.

## 中文說明

### 核心規則

只維護這一份 wiki。

- 公開筆記：`wiki/public/`
- 私人、工作、研究、會議脈絡：`wiki/internal/`
- 未整理輸入：`raw/inbox/`
- TODO：`tasks/now.md`
- Daily Note：`wiki/internal/DailyNote/`

`~/Peter_public_note/docs` 是匯出結果，不是手動維護的 source。

### 常用指令

```bash
cd ~/peter-llm-wiki

# 建立或更新今天的 DailyNote
scripts/daily

# 檢查 public/private boundary
scripts/lint-wiki

# 匯出 public notes 到 Docusaurus
scripts/export-public-note
```

### TODO

TODO 只有一個檔案：

```text
tasks/now.md
```

之後就是手動改這個檔，或請 agent 幫你加 / 完成 TODO。

範例：

```md
## Today

- [ ] 建立部署的 doc
- [ ] deploy prod

## This Week

- [ ] 整理 public note

## Done Recently

- [x] 新增 /daily command
```

不要再使用 generated/imported TODO 檔案；搬遷結束後那些不是日常流程的一部分。

### Daily Note

Daily Note 放在：

```text
wiki/internal/DailyNote/YYYY-MM-DD.md
```

建立今天的 Daily：

```bash
scripts/daily
```

格式固定：

```md
## today focus:

- [ ] 今天最重要的 focus

## today important contribution:

- 今天真正完成、產生價值的事
```

你也可以請 agent 幫你補今天做的事。Agent 應該只根據目前對話、`tasks/now.md`、git diff/status、既有 notes 來整理，不要憑空編造。

### Public Notes

公開筆記放在 `wiki/public/`，需要 frontmatter：

```yaml
---
title: Monorepo
visibility: public
export_path: design-pattern/monorepo.md
tags: [architecture]
---
```

`export_path` 是匯出到 `~/Peter_public_note/docs/` 底下的位置。

如果公開筆記中有暫時不能匯出的內容，用 private block：

```md
<!-- private:start -->
private context
<!-- private:end -->
```

匯出時 private block 會被移除。

### Export

```bash
cd ~/peter-llm-wiki
scripts/lint-wiki
scripts/export-public-note

cd ~/Peter_public_note
npm run build
git diff
```

匯出的 Markdown 會有 marker：

```md
<!-- generated from ~/peter-llm-wiki; edit source there, not here -->
```

看到這個 marker，就回 `~/peter-llm-wiki` 改 source。

### Agent / Claude Commands

| Command file | 用途 |
| --- | --- |
| `.claude/commands/ingest.md` | 把新資料整理進 wiki。 |
| `.claude/commands/daily.md` | 建立或更新今天的 DailyNote。 |
| `.claude/commands/todo.md` | 管理 `tasks/now.md`。 |
| `.claude/commands/export-public-note.md` | 匯出 public notes。 |
| `.claude/commands/lint-wiki.md` | 檢查 public/private boundary。 |

預期 slash command：

```text
/ingest
/daily
/todo
/export-public-note
/lint-wiki
```

### Command 使用方式

TODO 只改 `tasks/now.md`：

```text
/todo
/todo add 建立部署的 doc
/todo week 整理 public note
/todo done 建立部署
```

Daily 只改今天的 `wiki/internal/DailyNote/YYYY-MM-DD.md`：

```text
/daily
/daily focus deploy prod
/daily contribution 新增 /daily command 並更新 README
/daily recap
```

規則很簡單：

- `/todo` 管待辦。
- `/daily` 管今天紀錄。
- Agent 不要建立第二份 TODO，也不要掃整個 wiki 產生 TODO。
- `/daily recap` 只能根據目前對話、`tasks/now.md`、git diff/status、既有 notes 整理。

## English Guide

### Core Rule

Keep one canonical wiki.

- Public notes: `wiki/public/`
- Private, work, research, and meeting context: `wiki/internal/`
- Unprocessed input: `raw/inbox/`
- TODO: `tasks/now.md`
- Daily notes: `wiki/internal/DailyNote/`

`~/Peter_public_note/docs` is exported output, not the source of truth.

### Common Commands

```bash
cd ~/peter-llm-wiki

# Create or update today's DailyNote
scripts/daily

# Check the public/private boundary
scripts/lint-wiki

# Export public notes to Docusaurus
scripts/export-public-note
```

### TODO

There is only one TODO file:

```text
tasks/now.md
```

Edit this file manually, or ask an agent to add / complete TODOs there.

Do not use generated/imported TODO files after migration; they are not part of the daily workflow.

### Daily Note

Daily notes live at:

```text
wiki/internal/DailyNote/YYYY-MM-DD.md
```

Create today's note:

```bash
scripts/daily
```

Required format:

```md
## today focus:

- [ ] Today's most important focus

## today important contribution:

- Meaningful completed work from today
```

You can ask an agent to fill today's work from visible evidence: this conversation, `tasks/now.md`, git diff/status, and existing notes.

### Agent / Claude Commands

Expected slash commands:

```text
/ingest
/daily
/todo
/export-public-note
/lint-wiki
```

### Command Usage

TODO only edits `tasks/now.md`:

```text
/todo
/todo add Write deployment doc
/todo week Clean up public notes
/todo done deployment doc
```

Daily only edits today's `wiki/internal/DailyNote/YYYY-MM-DD.md`:

```text
/daily
/daily focus deploy prod
/daily contribution Added /daily command and updated README
/daily recap
```

Rules:

- `/todo` manages tasks.
- `/daily` manages today's record.
- The agent must not create a second TODO list or scan the whole wiki to generate TODOs.
- `/daily recap` must use visible evidence only: this conversation, `tasks/now.md`, git diff/status, and existing notes.

### Public Notes

Public notes live in `wiki/public/` and need frontmatter:

```yaml
---
title: Monorepo
visibility: public
export_path: design-pattern/monorepo.md
tags: [architecture]
---
```

`export_path` is the path under `~/Peter_public_note/docs/`.

Wrap private context inside public notes with:

```md
<!-- private:start -->
private context
<!-- private:end -->
```

The export script removes private blocks.

### Export

```bash
cd ~/peter-llm-wiki
scripts/lint-wiki
scripts/export-public-note

cd ~/Peter_public_note
npm run build
git diff
```

Exported Markdown includes:

```md
<!-- generated from ~/peter-llm-wiki; edit source there, not here -->
```

Edit the source note in `~/peter-llm-wiki`, not the generated file.
EOF

cat > "$TARGET/AGENTS.md" <<'EOF'
# Peter LLM Wiki Agent Rules

## Source of truth

This repo is the only note source of truth.

Do not treat `~/Peter_public_note` or the old trend note vault as editable canonical notes. They are sources/imports or export targets.

## Public/private boundary

Never export private company context, endpoints, credentials, customer data, internal architecture details, meeting notes, or repo-specific work context to public notes.

Public notes must explicitly opt in:

```yaml
visibility: public
export_path: some/category/file.md
```

Private blocks must be wrapped before export:

```md
<!-- private:start -->
private details
<!-- private:end -->
```

## Directory meaning

- `wiki/public/`: canonical public-ready notes. These export to `~/Peter_public_note/docs`.
- `wiki/internal/`: canonical private knowledge.
- `raw/imports/`: migration snapshots. Do not edit except when re-importing.
- `raw/inbox/`: temporary unprocessed material.
- `tasks/now.md`: the only active TODO list.

## Writing style

Use Peter's note style: conversational Traditional Chinese, English technical terms kept as-is, concise examples, practical tradeoffs.
EOF

cat > "$TARGET/schema.md" <<'EOF'
# LLM Wiki Schema

## Frontmatter

Recommended fields:

```yaml
---
title: Human readable title
visibility: private | public
export_path: category/file.md
tags: []
source:
  - raw/imports/...
updated: YYYY-MM-DD
---
```

## Visibility

- `private`: default. Never exported.
- `public`: may be exported when `export_path` exists.

## Public export

Public export reads from:

- `wiki/public/**/*.md`
- `wiki/internal/**/*.md` only when the file explicitly says `visibility: public`

During export:

- private blocks are removed
- `visibility` and `export_path` are removed from frontmatter
- a generated-file marker is inserted

## TODO

Use `tasks/now.md` as the only active TODO list.

```md
- [ ] TODO item
- [x] Done item
```
EOF

cat > "$TARGET/tasks/now.md" <<'EOF'
# Now TODO

這是每天或最近要完成事情的固定清單。

## Today

- [ ] 

## This Week

把不是今天、但最近要做的事放這裡。

## Done Recently

完成後移到這裡，月底或任務結束再清掉。
EOF

cat > "$TARGET/scripts/daily" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATE_VALUE="${1:-$(date +%F)}"
DAILY_DIR="$ROOT/wiki/internal/DailyNote"
OUT="$DAILY_DIR/$DATE_VALUE.md"

mkdir -p "$DAILY_DIR"

if [[ ! "$DATE_VALUE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "Usage: scripts/daily [YYYY-MM-DD]" >&2
  exit 1
fi

if [[ ! -f "$OUT" ]]; then
  cat > "$OUT" <<DAILY_EOF
---
title: Daily $DATE_VALUE
visibility: private
created: $DATE_VALUE
---

# Daily $DATE_VALUE

## today focus:

- [ ] 

## today important contribution:

- 
DAILY_EOF
  echo "Created $OUT"
else
  echo "Daily note already exists: $OUT"
fi

echo "$OUT"
EOF

cat > "$TARGET/scripts/export-public-note" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DOCS="${PUBLIC_NOTE_DOCS:-$HOME/Peter_public_note/docs}"

if [[ "${SKIP_WIKI_LINT:-0}" != "1" ]]; then
  "$ROOT/scripts/lint-wiki"
fi

python3 - "$ROOT" "$TARGET_DOCS" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
target_docs = Path(sys.argv[2])

def parse_frontmatter(text):
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---\n", 4)
    if end == -1:
        return {}, text
    raw = text[4:end]
    body = text[end + 5:]
    data = {}
    lines = []
    for line in raw.splitlines():
        if ":" not in line or line.startswith(" ") or line.startswith("-"):
            lines.append(line)
            continue
        key, value = line.split(":", 1)
        data[key.strip()] = value.strip().strip('"').strip("'")
        lines.append(line)
    return data, body

def render_frontmatter(text):
    data, body = parse_frontmatter(text)
    kept = []
    if text.startswith("---\n"):
        raw = text[4:text.find("\n---\n", 4)]
        for line in raw.splitlines():
            key = line.split(":", 1)[0].strip() if ":" in line else ""
            if key in {"visibility", "export_path", "source"}:
                continue
            kept.append(line)
    body = re.sub(
        r"<!--\s*private:start\s*-->.*?<!--\s*private:end\s*-->",
        "",
        body,
        flags=re.DOTALL | re.IGNORECASE,
    ).strip() + "\n"
    marker = "<!-- generated from ~/peter-llm-wiki; edit source there, not here -->\n\n"
    if kept:
        return "---\n" + "\n".join(kept).strip() + "\n---\n" + marker + body
    return marker + body

exported = []
scan_roots = [root / "wiki" / "public", root / "wiki" / "internal"]
for scan_root in scan_roots:
    if not scan_root.exists():
        continue
    for path in sorted(scan_root.rglob("*.md")):
        text = path.read_text(encoding="utf-8")
        data, _ = parse_frontmatter(text)
        if data.get("visibility", "private") != "public":
            continue
        export_path = data.get("export_path")
        if not export_path:
            print(f"SKIP missing export_path: {path.relative_to(root)}", file=sys.stderr)
            continue
        if export_path.startswith("/") or ".." in Path(export_path).parts:
            print(f"SKIP unsafe export_path: {path.relative_to(root)} -> {export_path}", file=sys.stderr)
            continue
        out = target_docs / export_path
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(render_frontmatter(text), encoding="utf-8")
        exported.append((path.relative_to(root), out))

print(f"Exported {len(exported)} public notes to {target_docs}")
for src, dst in exported:
    print(f"- {src} -> {dst}")
PY
EOF

cat > "$TARGET/scripts/lint-wiki" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
problems = []
blocked_terms = [
    "Trend Micro",
    "trendmicro.com",
    "Vision One",
]

credential_assignment = re.compile(
    r"(?i)(?<![A-Za-z0-9_])"
    r"(api[_-]?key|secret[_-]?key|access[_-]?token|refresh[_-]?token|password)"
    r"(?![A-Za-z0-9_])\s*[:=]\s*['\"]?([^'\"\s,}]+)"
)
credential_patterns = [
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"(?i)bearer\s+[a-z0-9._~+/=-]{20,}"),
]

def is_placeholder_or_reference(value):
    lowered = value.lower()
    return (
        "example" in lowered
        or "xxx" in lowered
        or "..." in lowered
        or lowered.startswith("<")
        or lowered.startswith("self.")
        or lowered.startswith("data[")
        or lowered.startswith("token_data[")
        or lowered.startswith("token_data.get(")
        or lowered.startswith("os.getenv(")
        or lowered in {"none", "null", "true", "false", "str", "int", "dict", "list"}
    )

def parse_frontmatter(text):
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---\n", 4)
    if end == -1:
        return {}
    data = {}
    for line in text[4:end].splitlines():
        if ":" in line and not line.startswith(" "):
            k, v = line.split(":", 1)
            data[k.strip()] = v.strip().strip('"').strip("'")
    return data

for path in sorted((root / "wiki").rglob("*.md")):
    text = path.read_text(encoding="utf-8", errors="ignore")
    data = parse_frontmatter(text)
    rel = path.relative_to(root)
    if data.get("visibility") == "public":
        if not data.get("export_path"):
            problems.append(f"{rel}: public note missing export_path")
        public_text = re.sub(
            r"<!--\s*private:start\s*-->.*?<!--\s*private:end\s*-->",
            "",
            text,
            flags=re.DOTALL | re.IGNORECASE,
        )
        for term in blocked_terms:
            if term.lower() in public_text.lower():
                problems.append(f"{rel}: public note contains blocked term: {term}")
        for match in credential_assignment.finditer(public_text):
            value = match.group(2)
            if not is_placeholder_or_reference(value):
                problems.append(f"{rel}: public note may contain credential-like assignment: {match.group(1)}")
                break
        for pattern in credential_patterns:
            if pattern.search(public_text):
                problems.append(f"{rel}: public note may contain credential-like text: {pattern.pattern}")

if problems:
    print("Wiki lint found problems:")
    for p in problems:
        print(f"- {p}")
    sys.exit(1)

print("Wiki lint passed.")
PY
EOF

cat > "$TARGET/.claude/commands/export-public-note.md" <<'EOF'
Export public notes from `~/peter-llm-wiki` into `~/Peter_public_note`.

Steps:
1. Run `scripts/lint-wiki`.
2. Run `scripts/export-public-note`.
3. Review the git diff in `~/Peter_public_note`.

Do not manually edit generated public note files unless the source in `~/peter-llm-wiki` is also updated.
EOF

cat > "$TARGET/.claude/commands/daily.md" <<'EOF'
Create or update the daily note in `~/peter-llm-wiki`.

Source of truth:
- Today's note: `wiki/internal/DailyNote/YYYY-MM-DD.md`
- TODO source: `tasks/now.md`

Behavior:
- `/daily` — run `scripts/daily`, then show today's note.
- `/daily focus <item>` — add the item under `today focus`.
- `/daily contribution <item>` — add the item under `today important contribution`.
- `/daily recap` — update today's note from visible evidence only: this conversation, `tasks/now.md`, changed files, git diff/status, and existing notes.

Daily note path:

```text
wiki/internal/DailyNote/YYYY-MM-DD.md
```

Use the current local date for `YYYY-MM-DD`.

Required format:

```md
# Daily YYYY-MM-DD

## today focus:

- [ ] ...

## today important contribution:

- ...
```

When updating:
- Keep the two required sections.
- Put planned or unfinished work under `today focus`.
- Put completed meaningful outcomes under `today important contribution`.
- Preserve existing user-written content.
- Do not invent work. If evidence is unclear, ask or leave it blank.
EOF

cat > "$TARGET/.claude/commands/todo.md" <<'EOF'
Manage TODOs for `~/peter-llm-wiki`.

Source of truth:
- `tasks/now.md` is the only TODO list.

Usage:
- `/todo` — show `tasks/now.md`
- `/todo add <item>` — add the item under `## Today`
- `/todo week <item>` — add the item under `## This Week`
- `/todo done <partial text>` — move the matching item to `## Done Recently` and mark it `[x]`

Rule:
- Do not recreate generated or imported TODO files.
- Do not scan the whole wiki for TODOs.
- Keep wording short; this file is for execution, not project management.
EOF

cat > "$TARGET/.claude/commands/ingest.md" <<'EOF'
Ingest content into `~/peter-llm-wiki`.

Rules:
1. Raw unprocessed input goes to `raw/inbox/`.
2. Private/work context goes to `wiki/internal/`.
3. Public-ready distilled technical knowledge goes to `wiki/public/` with `visibility: public` and `export_path`.
4. Never export company context unless the user explicitly rewrites it into a general public-safe explanation.
5. Keep source links or source paths in frontmatter.
EOF

cat > "$TARGET/.claude/commands/lint-wiki.md" <<'EOF'
Run wiki quality checks.

Steps:
1. Run `scripts/lint-wiki`.
2. Check public notes for missing `export_path`.
3. Check private/public boundary violations.
4. Report exact files that need changes.
EOF

chmod +x "$TARGET/scripts/daily" "$TARGET/scripts/export-public-note" "$TARGET/scripts/lint-wiki"

rsync -a --delete \
  --exclude '.git' \
  --exclude 'node_modules' \
  --exclude 'build' \
  --exclude '.docusaurus' \
  --exclude '.DS_Store' \
  "$PUBLIC_NOTE/docs/" "$TARGET/raw/imports/public-note/docs/"

mkdir -p "$TARGET/raw/imports/public-note/site"
for file in sidebars.js docusaurus.config.js package.json package-lock.json; do
  if [[ -f "$PUBLIC_NOTE/$file" ]]; then
    cp -p "$PUBLIC_NOTE/$file" "$TARGET/raw/imports/public-note/site/$file"
  fi
done
for dir in static src; do
  if [[ -d "$PUBLIC_NOTE/$dir" ]]; then
    rsync -a --delete --exclude '.DS_Store' "$PUBLIC_NOTE/$dir/" "$TARGET/raw/imports/public-note/site/$dir/"
  fi
done

python3 - "$PUBLIC_NOTE/docs" "$TARGET/wiki/public" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])

def with_public_frontmatter(text, rel):
    export_path = rel.as_posix()
    if text.startswith("---\n"):
        end = text.find("\n---\n", 4)
        if end != -1:
            raw = text[4:end].strip()
            body = text[end + 5:]
            lines = [line for line in raw.splitlines() if not line.startswith("visibility:") and not line.startswith("export_path:")]
            lines.append("visibility: public")
            lines.append(f"export_path: {export_path}")
            lines.append("source: raw/imports/public-note/docs/" + export_path)
            return "---\n" + "\n".join(lines) + "\n---\n" + body
    title = rel.stem.replace("-", " ")
    return (
        "---\n"
        f"title: {title}\n"
        "visibility: public\n"
        f"export_path: {export_path}\n"
        "source: raw/imports/public-note/docs/" + export_path + "\n"
        "---\n\n"
        + text
    )

for path in sorted(src.rglob("*.md")):
    if ".DS_Store" in path.parts:
        continue
    rel = path.relative_to(src)
    out = dst / rel
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(with_public_frontmatter(path.read_text(encoding="utf-8"), rel), encoding="utf-8")
PY

for dir in Domain wiki raw repo-overview DailyNote 1-on-1 _inbox _templates openspec; do
  if [[ -d "$TREND_NOTE/$dir" ]]; then
    mkdir -p "$TARGET/wiki/internal/$dir"
    rsync -a --exclude '.DS_Store' "$TREND_NOTE/$dir/" "$TARGET/wiki/internal/$dir/"
  fi
done

mkdir -p "$TARGET/raw/imports/trend-note/snapshot"
rsync -a --delete \
  --exclude '.git' \
  --exclude 'node_modules' \
  --exclude '.DS_Store' \
  "$TREND_NOTE/" "$TARGET/raw/imports/trend-note/snapshot/"

mkdir -p "$TARGET/wiki/internal/_root"
find "$TREND_NOTE" -maxdepth 1 -type f \( \
    -name '*.md' -o \
    -iname '*.png' -o \
    -iname '*.jpg' -o \
    -iname '*.jpeg' -o \
    -iname '*.gif' -o \
    -iname '*.webp' -o \
    -iname '*.pdf' \
  \) \
  ! -name 'AGENTS.md' \
  ! -name 'CLAUDE.md' \
  ! -name 'schema.md' \
  ! -name 'memory.md' \
  ! -name 'TODO list.md' \
  ! -name 'Report import.md' \
  -print0 | while IFS= read -r -d '' file; do
    cp -p "$file" "$TARGET/wiki/internal/_root/"
  done

for file in AGENTS.md CLAUDE.md schema.md memory.md "TODO list.md" "Report import.md"; do
  if [[ -f "$TREND_NOTE/$file" ]]; then
    mkdir -p "$TARGET/raw/imports/trend-note"
    cp -p "$TREND_NOTE/$file" "$TARGET/raw/imports/trend-note/$file"
  fi
done

cat > "$TARGET/MIGRATION.md" <<EOF
# Migration Record

Generated on: $(date +%F)

## Imported sources

- Public Docusaurus note: \`$PUBLIC_NOTE\`
- Private trend note: \`$TREND_NOTE\`

## New rule

\`$TARGET\` is now the only source of truth.

Do not manually maintain the same note in three places:

- edit canonical public-ready pages in \`wiki/public/\`
- edit private pages in \`wiki/internal/\`
- export to \`$PUBLIC_NOTE\` with \`scripts/export-public-note\`

## First checks

\`\`\`bash
cd "$TARGET"
scripts/lint-wiki
scripts/export-public-note
\`\`\`
EOF

echo "Created LLM wiki at $TARGET"
echo "Next:"
echo "  cd \"$TARGET\""
echo "  scripts/lint-wiki"
echo "  scripts/export-public-note"
