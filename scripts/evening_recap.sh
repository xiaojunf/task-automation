#!/bin/bash
# Evening Recap Agent - runs at 9pm

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TODAY=$(date '+%Y-%m-%d')
LOG_FILE="$SCRIPT_DIR/logs/evening_$TODAY.log"
TODAY_TASKS_FILE="$SCRIPT_DIR/today_tasks.txt"
TMP_AS="$SCRIPT_DIR/tmp_applescript_eve.scpt"

mkdir -p "$SCRIPT_DIR/logs"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Evening Recap started at $(date) ==="

# 1. Read morning plan
if [ -f "$TODAY_TASKS_FILE" ]; then
  MORNING_PLAN=$(cat "$TODAY_TASKS_FILE")
else
  MORNING_PLAN="(今天没有生成早间简报)"
fi

# 2. Read today's calendar
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

# 3. Read any new Inbox content added during the day
cat > "$TMP_AS" << 'HEREDOC'
tell application "Notes"
  repeat with n in every note of every folder of every account
    if name of n is "Inbox" then
      return body of n
    end if
  end repeat
  return "EMPTY"
end tell
HEREDOC
INBOX_RAW=$(osascript "$TMP_AS" 2>/dev/null)
INBOX_CONTENT=$(echo "$INBOX_RAW" | sed 's/<[^>]*>//g' | sed '/^[[:space:]]*$/d')

# 4. Generate recap with Claude
echo "Generating recap..."
CLAUDE_INPUT="你是我的个人助理。今天是 $TODAY，现在是晚上。

=== 今早的计划 ===
$MORNING_PLAN

=== 今天的日历事件 ===
$CALENDAR_EVENTS

=== 白天新加入 Inbox 的内容 ===
${INBOX_CONTENT:-（没有新内容）}

请帮我做今日复盘：
1. 根据今早的计划和日历，推测今天大概完成了哪些事
2. 明天需要继续的事情
3. 一句温暖鼓励的话

输出格式：
🌙 今日复盘 - $TODAY

✅ 今天的进展
[推断内容]

📌 明天继续
[延续任务]

💡 一句话
[简短鼓励]

语言：中文，温暖简洁。"

RECAP=$(/opt/homebrew/bin/claude -p "$CLAUDE_INPUT" 2>/dev/null)
echo "Recap generated."

# 5. Send email
SUBJECT="🌙 今日复盘 - $TODAY"
RECAP_ESCAPED=$(echo "$RECAP" | sed "s/\"/\\\\\"/g" | sed "s/'/\\\\'/g")

cat > "$TMP_AS" << HEREDOC
tell application "Mail"
  set msg to make new outgoing message with properties {subject:"$SUBJECT", content:"$RECAP_ESCAPED", visible:false}
  tell msg
    set sender to "junjun80585@gmail.com"
    make new to recipient at end of to recipients with properties {address:"junjun80585@gmail.com"}
  end tell
  send msg
end tell
HEREDOC
osascript "$TMP_AS" 2>/dev/null
echo "Recap email sent."

rm -f "$TMP_AS"
echo "=== Evening Recap completed at $(date) ==="
