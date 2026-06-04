#!/bin/bash
# Weekly Summary Agent - runs every Sunday at 9pm
# Summarizes the week, sends stats email, carries over incomplete tasks

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TODAY=$(date '+%Y-%m-%d')
LOG_FILE="$SCRIPT_DIR/logs/weekly_$TODAY.log"
TMP_AS="$SCRIPT_DIR/tmp_applescript_wk.scpt"
OBSIDIAN_VAULT="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Inbox"

mkdir -p "$SCRIPT_DIR/logs"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Weekly Summary started at $(date) ==="

# 1. Read this week's file and compute stats
python3 << 'PYEOF' > "$SCRIPT_DIR/weekly_context.txt"
import os, re
from datetime import date, timedelta

vault = os.path.expanduser("~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Inbox")
today = date.today()
week_str = today.strftime('%Y-W%V')
weekly_file = os.path.join(vault, f"Weekly/{week_str}.md")

if not os.path.exists(weekly_file):
    print("NO_WEEKLY_FILE")
    exit(0)

with open(weekly_file) as f:
    content = f.read()

# Count tasks
total, done, incomplete = 0, 0, []
for line in content.split('\n'):
    if re.match(r'\s*- \[x\]', line, re.IGNORECASE):
        total += 1
        done += 1
    elif re.match(r'\s*- \[ \]', line):
        total += 1
        incomplete.append(line.strip())

rate = round(done / total * 100) if total > 0 else 0

print(f"WEEK={week_str}")
print(f"TOTAL={total}")
print(f"DONE={done}")
print(f"RATE={rate}")
print(f"INCOMPLETE_COUNT={len(incomplete)}")
print("WEEKLY_CONTENT_START")
print(content)
print("WEEKLY_CONTENT_END")
print("INCOMPLETE_START")
for item in incomplete:
    print(item)
print("INCOMPLETE_END")
PYEOF

WEEKLY_CONTEXT=$(cat "$SCRIPT_DIR/weekly_context.txt")

if echo "$WEEKLY_CONTEXT" | grep -q "NO_WEEKLY_FILE"; then
  echo "No weekly file found, skipping."
  exit 0
fi

WEEK_STR=$(echo "$WEEKLY_CONTEXT" | grep '^WEEK=' | cut -d= -f2)
TOTAL=$(echo "$WEEKLY_CONTEXT" | grep '^TOTAL=' | cut -d= -f2)
DONE=$(echo "$WEEKLY_CONTEXT" | grep '^DONE=' | cut -d= -f2)
RATE=$(echo "$WEEKLY_CONTEXT" | grep '^RATE=' | cut -d= -f2)

# 2. Generate weekly summary email with Claude
echo "Generating weekly summary..."
CLAUDE_INPUT="你是我的个人助理。今天是 $TODAY，本周（$WEEK_STR）结束了。

本周数据：
- 计划任务总数：$TOTAL
- 已完成：$DONE
- 完成率：$RATE%

本周详细内容：
$WEEKLY_CONTEXT

请帮我生成本周总结邮件：
1. 简短点评本周完成情况（鼓励为主）
2. 列出本周亮点（完成的重要事项）
3. 未完成的事项（carry over 到下周）
4. 对下周的一句期望

输出格式：
📊 本周总结 $WEEK_STR

🏆 完成率：$DONE / $TOTAL（$RATE%）

✨ 本周亮点
[已完成的重要事项]

🔄 下周继续
[未完成事项，将自动加入下周列表]

💪 下周期望
[一句话]

语言：中文，温暖有力。"

SUMMARY_EMAIL=$(/opt/homebrew/bin/claude -p "$CLAUDE_INPUT" 2>/dev/null)
echo "Summary generated."

# 3. Update this week's stats section in the weekly file
python3 << PYEOF
import os, re
from datetime import date

vault = "$OBSIDIAN_VAULT"
today = date.today()
week_str = "$WEEK_STR"
total, done, rate = $TOTAL, $DONE, $RATE
weekly_file = os.path.join(vault, f"Weekly/{week_str}.md")

with open(weekly_file) as f:
    content = f.read()

# Update stats table
new_stats = f"""## 📊 本周统计
> 最终统计于 {today}

| 指标 | 数值 |
|------|------|
| 计划总数 | {total} |
| 已完成 | {done} |
| 完成率 | {rate}% |"""

content = re.sub(r'## 📊 本周统计.*?(?=\n---|\n## )', new_stats + '\n', content, flags=re.DOTALL)

with open(weekly_file, "w") as f:
    f.write(content)
print(f"Updated weekly stats: {done}/{total} ({rate}%)")
PYEOF

# 4. Carry over incomplete tasks to next week
python3 << PYEOF
import os, re
from datetime import date, timedelta

vault = "$OBSIDIAN_VAULT"
today = date.today()
next_monday = today + timedelta(days=7 - today.weekday())
next_week_str = next_monday.strftime('%Y-W%V')
next_sunday = next_monday + timedelta(days=6)
this_week_str = "$WEEK_STR"

# Read incomplete tasks
this_week_file = os.path.join(vault, f"Weekly/{this_week_str}.md")
with open(this_week_file) as f:
    content = f.read()

incomplete = []
for line in content.split('\n'):
    if re.match(r'\s*- \[ \]', line):
        incomplete.append(line.strip())

if not incomplete:
    print("No incomplete tasks to carry over.")
    exit(0)

# Create next week file
next_week_file = os.path.join(vault, f"Weekly/{next_week_str}.md")
carry_lines = "\n".join(incomplete)

if not os.path.exists(next_week_file):
    with open(next_week_file, "w") as f:
        f.write(f"""# 📅 {next_week_str}（{next_monday} ～ {next_sunday}）

## 📊 本周统计
> 自动更新于每周日晚

| 指标 | 数值 |
|------|------|
| 计划总数 | — |
| 已完成 | — |
| 完成率 | — |

---

## 🔄 从上周延续（{this_week_str}）

{carry_lines}

""")
    print(f"Created next week file with {len(incomplete)} carry-over tasks.")
else:
    with open(next_week_file, "r") as f:
        existing = f.read()
    carry_section = f"\n## 🔄 从上周延续（{this_week_str}）\n\n{carry_lines}\n"
    if "从上周延续" not in existing:
        existing += carry_section
        with open(next_week_file, "w") as f:
            f.write(existing)
    print(f"Added {len(incomplete)} carry-over tasks to next week.")
PYEOF

# 5. Send summary email
echo "Sending weekly summary email..."
SUBJECT="📊 本周总结 $WEEK_STR"
EMAIL_ESCAPED=$(echo "$SUMMARY_EMAIL" | sed "s/\"/\\\\\"/g" | sed "s/'/\\\\'/g")

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
echo "Weekly summary email sent."

rm -f "$TMP_AS" "$SCRIPT_DIR/weekly_context.txt"
echo "=== Weekly Summary completed at $(date) ==="
