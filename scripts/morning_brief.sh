#!/bin/bash
# Morning Brief Agent - runs at 8am

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TODAY=$(date '+%Y-%m-%d')
WEEKDAY=$(date '+%A')
LOG_FILE="$SCRIPT_DIR/logs/morning_$TODAY.log"
TODAY_TASKS_FILE="$SCRIPT_DIR/today_tasks.txt"
TMP_AS="$SCRIPT_DIR/tmp_applescript.scpt"
OBSIDIAN_INBOX="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Inbox/Inbox.md"
OBSIDIAN_VAULT="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Inbox"

mkdir -p "$SCRIPT_DIR/logs"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Morning Brief started at $(date) ==="

# 1. Read Obsidian Inbox.md
echo "Reading Obsidian Inbox..."
if [ -f "$OBSIDIAN_INBOX" ]; then
  # Skip the header section (everything before the first ---)
  INBOX_CONTENT=$(awk '/^---$/{found++; next} found>=1' "$OBSIDIAN_INBOX" | sed '/^[[:space:]]*$/d')
fi
if [ -z "$INBOX_CONTENT" ]; then
  INBOX_CONTENT="(今天没有新的 inbox 内容)"
fi
echo "Inbox retrieved."

# 2. Read Google Calendar events
echo "Reading Calendar..."
cat > "$TMP_AS" << 'HEREDOC'
tell application "Calendar"
  set tod to current date
  set startOfDay to tod
  set hours of startOfDay to 0
  set minutes of startOfDay to 0
  set seconds of startOfDay to 0
  set endOfDay to startOfDay + 86399
  set lines to {}
  repeat with cal in calendars
    repeat with ev in (every event of cal whose start date >= startOfDay and start date <= endOfDay)
      set t to time string of (start date of ev)
      set end of lines to "- " & (summary of ev) & " (" & t & ")"
    end repeat
  end repeat
  if (count of lines) = 0 then return "今天没有日历事件"
  set AppleScript's text item delimiters to linefeed
  return lines as string
end tell
HEREDOC
CALENDAR_EVENTS=$(osascript "$TMP_AS" 2>/dev/null)
echo "Calendar retrieved."

# 3. Use Claude to process
echo "Processing with Claude..."
CLAUDE_INPUT="你是我的个人助理。今天是 $TODAY（$WEEKDAY）。

=== 我的 Inbox（需要处理的想法和任务）===
$INBOX_CONTENT

=== 今天的日历事件 ===
$CALENDAR_EVENTS

请帮我做以下事情：
1. 把 Inbox 里的内容分析，提取出明确的 actionable tasks
2. 考虑今天的日历安排，给我安排 3-5 件今天最重要的事
3. 如果有「持续思考类」内容（不是 task，是需要继续思考的想法），单独列出来

输出格式：
📅 今天是 $TODAY（$WEEKDAY）

🎯 今日重点（按优先级）
1. [任务]
2. [任务]
3. [任务]

📆 日历提醒
[简短列出今天的事件]

💭 需要在 Obsidian 继续思考的
- [想法]（如果没有则省略此部分）

⚡ 快速杂项
- [其他小事]（如果没有则省略此部分）

语言：中文，简洁。"

SUMMARY=$(/opt/homebrew/bin/claude -p "$CLAUDE_INPUT" 2>/dev/null)
echo "Summary generated."

# 4. Classify Inbox content into Living Notes
echo "Classifying into Living Notes..."
CLASSIFY_INPUT="你是我的个人助理。今天是 $TODAY。

以下是我的 Inbox 内容：
$INBOX_CONTENT

请把每一条内容分类到以下五个类别之一，并判断它是「task（需要做的事）」还是「note（思考/笔记）」：
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
- task 是明确需要执行的动作，note 是想法、分析、代码片段、学习内容
- 代码片段属于 note，保留原始格式"

CLASSIFIED=$(/opt/homebrew/bin/claude -p "$CLASSIFY_INPUT" 2>/dev/null)

# Write classified output to temp file to avoid heredoc quoting issues
CLASSIFY_TMP="$SCRIPT_DIR/classify_tmp.json"
echo "$CLASSIFIED" > "$CLASSIFY_TMP"

# Append to each Living Note using Python for JSON parsing
python3 << PYEOF
import json, os, re

today = "$TODAY"
vault = "$OBSIDIAN_VAULT"
classify_tmp = "$CLASSIFY_TMP"

with open(classify_tmp) as f:
    classified_raw = f.read()

# Extract JSON from response
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

    lines = [f"\n### {today}"]
    if tasks:
        for t in tasks:
            # Also append to Tasks section
            lines.append(f"- 新增 task：{t}")
    if notes:
        for n in notes:
            lines.append(f"- {n}")
    lines.append("")

    # Append to 思考日志 section
    with open(filepath, "r") as f:
        content = f.read()

    log_section = "## 🗒 思考日志"
    if log_section in content:
        content = content.replace(log_section, log_section + "\n" + "\n".join(lines))
    else:
        content += "\n" + "\n".join(lines)

    # Also add tasks to Tasks section
    if tasks:
        tasks_section = "## 📋 Tasks"
        task_lines = "\n".join([f"- [ ] {t}" for t in tasks])
        if tasks_section in content:
            content = content.replace(tasks_section, tasks_section + "\n" + task_lines)

    with open(filepath, "w") as f:
        f.write(content)

    print(f"Updated: {category} ({len(tasks)} tasks, {len(notes)} notes)")

PYEOF

rm -f "$CLASSIFY_TMP"
echo "Living Notes updated."

# 5. Save for evening recap
echo "$SUMMARY" > "$TODAY_TASKS_FILE"

# 5. Send email via Apple Mail
echo "Sending email..."
SUBJECT="☀️ 今日简报 - $TODAY"
# Escape for AppleScript string
SUMMARY_ESCAPED=$(echo "$SUMMARY" | sed "s/\"/\\\\\"/g" | sed "s/'/\\\\'/g")

cat > "$TMP_AS" << HEREDOC
tell application "Mail"
  set msg to make new outgoing message with properties {subject:"$SUBJECT", content:"$SUMMARY_ESCAPED", visible:false}
  tell msg
    set sender to "junjun80585@gmail.com"
    make new to recipient at end of to recipients with properties {address:"junjun80585@gmail.com"}
  end tell
  send msg
end tell
HEREDOC
osascript "$TMP_AS" 2>/dev/null
echo "Email sent."

# 6. Archive Inbox content with date stamp, then reset
echo "Archiving Inbox..."
ARCHIVE_FILE="$OBSIDIAN_VAULT/Archive/$TODAY.md"

# Extract content below the --- separator
INBOX_TO_ARCHIVE=$(awk '/^---$/{found++; next} found>=1' "$OBSIDIAN_INBOX")

if [ -n "$(echo "$INBOX_TO_ARCHIVE" | tr -d '[:space:]')" ]; then
  cat > "$ARCHIVE_FILE" << HEREDOC
# Inbox Archive - $TODAY
> ✅ 已处理｜处理时间：$(date '+%Y-%m-%d %H:%M')

---

$INBOX_TO_ARCHIVE

---
> 本日简报见 Gmail：☀️ 今日简报 - $TODAY
HEREDOC
  echo "Archived to $ARCHIVE_FILE"
else
  echo "Inbox was empty, skipping archive."
fi

# Reset Inbox to template only
cat > "$OBSIDIAN_INBOX" << 'HEREDOC'
# Inbox

往这里扔任何东西，不需要格式。代码、想法、任务都可以。

---

HEREDOC
echo "Inbox reset."

rm -f "$TMP_AS"
echo "=== Morning Brief completed at $(date) ==="
