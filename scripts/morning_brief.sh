#!/bin/bash
# Morning Brief Agent - runs at 8am
# Silent: read Inbox → classify → Living Notes → update Weekly list (no email)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TODAY=$(date '+%Y-%m-%d')
WEEKDAY=$(date '+%A')
LOG_FILE="$SCRIPT_DIR/logs/morning_$TODAY.log"
TMP_AS="$SCRIPT_DIR/tmp_applescript.scpt"
OBSIDIAN_VAULT="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Inbox"
OBSIDIAN_INBOX="$OBSIDIAN_VAULT/Inbox.md"

mkdir -p "$SCRIPT_DIR/logs"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Morning processing started at $(date) ==="

# 1. Read Obsidian Inbox.md
echo "Reading Obsidian Inbox..."
INBOX_CONTENT=""
if [ -f "$OBSIDIAN_INBOX" ]; then
  INBOX_CONTENT=$(awk '/^---$/{found++; next} found>=1' "$OBSIDIAN_INBOX" | sed '/^[[:space:]]*$/d')
fi
if [ -z "$INBOX_CONTENT" ]; then
  echo "Inbox is empty, skipping classification."
else
  echo "Inbox retrieved."

  # 2. Classify into Living Notes via Claude
  echo "Classifying into Living Notes..."
  CLASSIFY_INPUT="你是我的个人助理。今天是 $TODAY。

以下是我的 Inbox 内容：
$INBOX_CONTENT

请把每一条内容分类到以下五个类别之一，并判断它是「task」还是「note」：
1. 建房决策
2. 孩子教育
3. 职业规划
4. 财务投资
5. 面试准备

输出严格按照以下 JSON 格式，不要输出其他内容：
{
  \"建房决策\": { \"tasks\": [\"...\"], \"notes\": [\"...\"] },
  \"孩子教育\": { \"tasks\": [\"...\"], \"notes\": [\"...\"] },
  \"职业规划\": { \"tasks\": [\"...\"], \"notes\": [\"...\"] },
  \"财务投资\": { \"tasks\": [\"...\"], \"notes\": [\"...\"] },
  \"面试准备\": { \"tasks\": [\"...\"], \"notes\": [\"...\"] }
}
rules:
- 如果某类别没有内容，tasks 和 notes 都用空数组 []
- task 是明确需要执行的动作，note 是想法/分析/代码片段/学习内容
- 代码片段属于 note，保留原始格式"

  CLASSIFIED=$(/opt/homebrew/bin/claude -p "$CLASSIFY_INPUT" 2>/dev/null)
  CLASSIFY_TMP="$SCRIPT_DIR/classify_tmp.json"
  echo "$CLASSIFIED" > "$CLASSIFY_TMP"

  python3 << PYEOF
import json, os, re

today = "$TODAY"
vault = "$OBSIDIAN_VAULT"
classify_tmp = "$CLASSIFY_TMP"

with open(classify_tmp) as f:
    classified_raw = f.read()

match = re.search(r'\{.*\}', classified_raw, re.DOTALL)
if not match:
    print("Could not parse classification JSON")
    exit(0)

try:
    data = json.loads(match.group())
except:
    print("JSON parse error")
    exit(0)

category_files = {
    "建房决策": os.path.join(vault, "建房决策/建房决策.md"),
    "孩子教育": os.path.join(vault, "孩子教育/孩子教育.md"),
    "职业规划": os.path.join(vault, "职业规划/职业规划.md"),
    "财务投资": os.path.join(vault, "财务投资/财务投资.md"),
    "面试准备": os.path.join(vault, "面试准备/面试准备.md"),
}

for category, filepath in category_files.items():
    tasks = data.get(category, {}).get("tasks", [])
    notes = data.get(category, {}).get("notes", [])
    if not tasks and not notes:
        continue
    if not os.path.exists(filepath):
        continue

    with open(filepath, "r") as f:
        content = f.read()

    # Append tasks to Tasks section
    if tasks:
        task_lines = "\n".join([f"- [ ] {t}" for t in tasks])
        tasks_section = "## 📋 Tasks"
        if tasks_section in content:
            content = content.replace(tasks_section, tasks_section + "\n" + task_lines)

    # Append to 思考日志
    log_lines = [f"\n### {today}"]
    if tasks:
        for t in tasks:
            log_lines.append(f"- 新增 task：{t}")
    if notes:
        for n in notes:
            log_lines.append(f"- {n}")
    log_lines.append("")

    log_section = "## 🗒 思考日志"
    if log_section in content:
        content = content.replace(log_section, log_section + "\n" + "\n".join(log_lines))

    with open(filepath, "w") as f:
        f.write(content)

    print(f"Updated: {category} ({len(tasks)} tasks, {len(notes)} notes)")
PYEOF

  rm -f "$CLASSIFY_TMP"
  echo "Living Notes updated."

  # 3. Archive Inbox content
  echo "Archiving Inbox..."
  ARCHIVE_FILE="$OBSIDIAN_VAULT/Archive/$TODAY.md"
  INBOX_TO_ARCHIVE=$(awk '/^---$/{found++; next} found>=1' "$OBSIDIAN_INBOX")
  if [ -n "$(echo "$INBOX_TO_ARCHIVE" | tr -d '[:space:]')" ]; then
    cat > "$ARCHIVE_FILE" << HEREDOC
# Inbox Archive - $TODAY
> ✅ 已处理｜处理时间：$(date '+%Y-%m-%d %H:%M')

---

$INBOX_TO_ARCHIVE

---
HEREDOC
    echo "Archived to $ARCHIVE_FILE"
  fi

  # Reset Inbox
  cat > "$OBSIDIAN_INBOX" << 'HEREDOC'
# Inbox

往这里扔任何东西，不需要格式。代码、想法、任务都可以。

---

HEREDOC
  echo "Inbox reset."
fi

# 4. Ensure today's section exists in Weekly list
python3 << PYEOF
import os, re
from datetime import date, timedelta

today = date.today()
monday = today - timedelta(days=today.weekday())
sunday = monday + timedelta(days=6)
week_str = today.strftime('%Y-W%V')
vault = "$OBSIDIAN_VAULT"
weekly_file = os.path.join(vault, f"Weekly/{week_str}.md")

weekday_cn = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
today_cn = weekday_cn[today.weekday()]
today_str = str(today)

# Create weekly file if not exists
if not os.path.exists(weekly_file):
    with open(weekly_file, "w") as f:
        f.write(f"""# 📅 {week_str}（{monday} ～ {sunday}）

## 📊 本周统计
> 自动更新于每周日晚

| 指标 | 数值 |
|------|------|
| 计划总数 | — |
| 已完成 | — |
| 完成率 | — |

---

""")
    print(f"Created weekly file: {week_str}.md")

# Add today's section if not already there
with open(weekly_file, "r") as f:
    content = f.read()

section_header = f"## {today_cn} {today_str}"
if section_header not in content:
    content += f"\n{section_header}\n\n"
    with open(weekly_file, "w") as f:
        f.write(content)
    print(f"Added section: {section_header}")
else:
    print(f"Section already exists: {section_header}")
PYEOF

rm -f "$TMP_AS"
echo "=== Morning processing completed at $(date) ==="
