#!/bin/bash
# Evening Recap Agent - runs at 9pm
# Sends combined email: today's recap + tomorrow's plan
# Updates Weekly list with today's tasks

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TODAY=$(date '+%Y-%m-%d')
LOG_FILE="$SCRIPT_DIR/logs/evening_$TODAY.log"
TMP_AS="$SCRIPT_DIR/tmp_applescript_eve.scpt"
OBSIDIAN_VAULT="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Inbox"

mkdir -p "$SCRIPT_DIR/logs"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Evening Recap started at $(date) ==="

# 1. Read today's calendar
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

# 2. Collect all pending tasks from Living Notes + Weekly list
python3 << 'PYEOF' > "$SCRIPT_DIR/context_tmp.txt"
import os, re
from datetime import date, timedelta

vault = os.path.expanduser("~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Inbox")
today = date.today()
tomorrow = today + timedelta(days=1)
monday = today - timedelta(days=today.weekday())
week_str = today.strftime('%Y-W%V')

# Read weekly file for today's section
weekly_file = os.path.join(vault, f"Weekly/{week_str}.md")
weekly_today = ""
if os.path.exists(weekly_file):
    with open(weekly_file) as f:
        content = f.read()
    weekday_cn = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    today_cn = weekday_cn[today.weekday()]
    pattern = rf"## {today_cn} {today}(.*?)(?=\n## |\Z)"
    m = re.search(pattern, content, re.DOTALL)
    if m:
        weekly_today = m.group(1).strip()

# Count completed tasks in weekly file this week
total, done = 0, 0
if os.path.exists(weekly_file):
    for line in open(weekly_file):
        if re.match(r'\s*- \[.\]', line):
            total += 1
            if re.match(r'\s*- \[x\]', line, re.IGNORECASE):
                done += 1

# Collect top pending tasks from all Living Notes
pending = {}
categories = ["建房决策", "孩子教育", "职业规划", "财务投资", "面试准备"]
for cat in categories:
    filepath = os.path.join(vault, f"{cat}/{cat}.md")
    if not os.path.exists(filepath):
        continue
    tasks = []
    with open(filepath) as f:
        in_tasks = False
        for line in f:
            if "## 📋 Tasks" in line:
                in_tasks = True
                continue
            if in_tasks and line.startswith("## "):
                break
            if in_tasks and re.match(r'\s*- \[ \]', line):
                tasks.append(line.strip())
    if tasks:
        pending[cat] = tasks[:3]  # top 3 per category

print(f"TODAY_WEEKLY={weekly_today}")
print(f"WEEK_TOTAL={total}")
print(f"WEEK_DONE={done}")
print("PENDING_TASKS_START")
for cat, tasks in pending.items():
    print(f"[{cat}]")
    for t in tasks:
        print(f"  {t}")
print("PENDING_TASKS_END")
PYEOF

CONTEXT=$(cat "$SCRIPT_DIR/context_tmp.txt")

# 3. Generate email with Claude
echo "Generating evening email..."
CLAUDE_INPUT="你是我的个人助理。今天是 $TODAY（晚上 9 点）。

=== 今天的日历事件 ===
$CALENDAR_EVENTS

=== 各类别待办事项（未完成）===
$CONTEXT

请生成今晚的邮件内容，包含两部分：

第一部分：今日复盘
- 根据今天的日历事件，总结今天可能完成的事情
- 语气轻松，有成就感

第二部分：明天计划
- 从各类别的待办事项中，挑选 3-5 件明天最应该做的事
- 考虑优先级和紧迫度

输出格式：
🌙 $TODAY 晚间简报

✅ 今日完成
[根据日历推断]

📋 明天计划
1. [任务]（类别）
2. [任务]（类别）
3. [任务]（类别）

语言：中文，简洁有力。"

EMAIL_CONTENT=$(/opt/homebrew/bin/claude -p "$CLAUDE_INPUT" 2>/dev/null)
echo "Email generated."

# 4. Update Weekly list with tomorrow's planned tasks
python3 << PYEOF
import os, re
from datetime import date, timedelta

vault = "$OBSIDIAN_VAULT"
today = date.today()
tomorrow = today + timedelta(days=1)
week_str = today.strftime('%Y-W%V')
# Check if tomorrow is a new week
tom_week = tomorrow.strftime('%Y-W%V')

for target_date, target_week in [(tomorrow, tom_week)]:
    weekly_file = os.path.join(vault, f"Weekly/{target_week}.md")
    weekday_cn = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    day_cn = weekday_cn[target_date.weekday()]
    section_header = f"## {day_cn} {target_date}"

    # Create new weekly file if it's a new week
    if not os.path.exists(weekly_file):
        monday = target_date - timedelta(days=target_date.weekday())
        sunday = monday + timedelta(days=6)
        with open(weekly_file, "w") as f:
            f.write(f"""# 📅 {target_week}（{monday} ～ {sunday}）

## 📊 本周统计
> 自动更新于每周日晚

| 指标 | 数值 |
|------|------|
| 计划总数 | — |
| 已完成 | — |
| 完成率 | — |

---

""")
        print(f"Created next week file: {target_week}.md")

    with open(weekly_file, "r") as f:
        content = f.read()

    if section_header not in content:
        content += f"\n{section_header}\n\n"
        with open(weekly_file, "w") as f:
            f.write(content)
        print(f"Added tomorrow section: {section_header}")

PYEOF

# 5. Send email
echo "Sending email..."
SUBJECT="🌙 晚间简报 - $TODAY"
EMAIL_ESCAPED=$(echo "$EMAIL_CONTENT" | sed "s/\"/\\\\\"/g" | sed "s/'/\\\\'/g")

cat > "$TMP_AS" << HEREDOC
tell application "Mail"
  set msg to make new outgoing message with properties {subject:"$SUBJECT", content:"$EMAIL_ESCAPED", visible:false}
  tell msg
    set sender to "junjun80585@gmail.com"
    make new to recipient at end of to recipients with properties {address:"junjun80585@gmail.com"}
  end tell
  send msg
end tell
HEREDOC
osascript "$TMP_AS" 2>/dev/null
echo "Email sent."

rm -f "$TMP_AS" "$SCRIPT_DIR/context_tmp.txt"
echo "=== Evening Recap completed at $(date) ==="
