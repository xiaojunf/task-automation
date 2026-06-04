#!/bin/bash
# Morning Brief Agent - runs at 8am

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TODAY=$(date '+%Y-%m-%d')
WEEKDAY=$(date '+%A')
LOG_FILE="$SCRIPT_DIR/logs/morning_$TODAY.log"
TODAY_TASKS_FILE="$SCRIPT_DIR/today_tasks.txt"
TMP_AS="$SCRIPT_DIR/tmp_applescript.scpt"
OBSIDIAN_INBOX="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Inbox/Inbox.md"

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

# 4. Save for evening recap
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
OBSIDIAN_VAULT=$(dirname "$OBSIDIAN_INBOX")
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
