# Personal Task Automation

每天自动读取 Apple Notes Inbox，生成今日任务摘要和晚间复盘，发送到 Gmail。

## 系统架构

```
Apple Notes "Inbox"  ──┐
                        ├──► Claude CLI  ──► Gmail 摘要邮件
Google Calendar       ──┘
```

- **早上 8:00**：读 Inbox + Calendar → Claude 生成今日重点 → 发邮件 → 清空 Inbox
- **晚上 9:00**：读早间计划 + Calendar → Claude 生成复盘 → 发邮件

**你每天只需要做一件事**：往 Apple Notes 的 `Inbox` note 里扔任何想法或任务，不需要格式。

---

## 文件结构

```
automation/
├── README.md                          # 本文件
├── scripts/
│   ├── morning_brief.sh               # 早间简报脚本
│   ├── evening_recap.sh               # 晚间复盘脚本
│   ├── com.xiaojunf.morning-brief.plist   # launchd 定时配置（8am）
│   └── com.xiaojunf.evening-recap.plist   # launchd 定时配置（9pm）
```

运行时数据（不在 repo 里）：
```
~/scripts/daily-agent/
├── today_tasks.txt      # 当天早间简报内容，供晚间复盘使用
└── logs/                # 每日运行日志
```

---

## 安装步骤

### 1. 复制脚本到运行目录

```bash
mkdir -p ~/scripts/daily-agent/logs
cp scripts/morning_brief.sh ~/scripts/daily-agent/
cp scripts/evening_recap.sh ~/scripts/daily-agent/
chmod +x ~/scripts/daily-agent/*.sh
```

### 2. 在 Apple Notes 里创建 Inbox note

打开 Apple Notes → 新建一个 note，标题改为 `Inbox`（确保连接的是 Google 账号）。

### 3. 注册 launchd agent（定时触发）

```bash
cp scripts/com.xiaojunf.morning-brief.plist ~/Library/LaunchAgents/
cp scripts/com.xiaojunf.evening-recap.plist ~/Library/LaunchAgents/

launchctl load ~/Library/LaunchAgents/com.xiaojunf.morning-brief.plist
launchctl load ~/Library/LaunchAgents/com.xiaojunf.evening-recap.plist
```

验证是否注册成功：
```bash
launchctl list | grep xiaojunf
# 应该看到两行：com.xiaojunf.morning-brief 和 com.xiaojunf.evening-recap
```

### 4. 测试运行

```bash
bash ~/scripts/daily-agent/morning_brief.sh
# 检查 Gmail 是否收到邮件
# 检查 Apple Notes Inbox 是否被清空
```

---

## 日常使用

### Capture（随时）

打开 Obsidian → `Inbox.md`，在 `---` 分隔线下面直接写，支持所有格式：

~~~markdown
明天要给 Aaron 发邮件关于建房材料

需要复习 DP 题目，感觉这块比较弱

这个命令很有用要记一下：
```bash
launchctl list | grep xiaojunf
```

周五前更新简历的 EMOS 项目部分
~~~

想法、任务、代码片段全部混在一起没关系，Claude 会帮你分类。

### 每天早上

收到邮件 `☀️ 今日简报 - YYYY-MM-DD`，里面是：
- 🎯 今日重点（3-5 件）
- 📆 日历提醒
- 💭 需要在 Obsidian 继续思考的（如果有）
- ⚡ 快速杂项

花 2 分钟看一眼，不需要做任何操作。

### 每天晚上

收到邮件 `🌙 今日复盘 - YYYY-MM-DD`，里面是：
- ✅ 今天的进展（根据计划推断）
- 📌 明天继续的事
- 💡 一句话

### 手动触发（不想等到定时）

```bash
bash ~/scripts/daily-agent/morning_brief.sh
bash ~/scripts/daily-agent/evening_recap.sh
```

### 查看日志

```bash
tail -f ~/scripts/daily-agent/logs/morning_2026-06-03.log
```

---

## 管理 launchd agent

```bash
# 停止（临时不想跑）
launchctl unload ~/Library/LaunchAgents/com.xiaojunf.morning-brief.plist

# 重新启动
launchctl load ~/Library/LaunchAgents/com.xiaojunf.morning-brief.plist

# 修改了 plist 后需要 reload
launchctl unload ~/Library/LaunchAgents/com.xiaojunf.morning-brief.plist
launchctl load ~/Library/LaunchAgents/com.xiaojunf.morning-brief.plist
```

修改触发时间：编辑 plist 文件里的 `Hour` 和 `Minute` 字段，然后 reload。

---

## 后续可以 evolve 的方向

### 短期（用一两周后）

**1. 加入 Gmail 扫描**
早间简报同时扫一遍 Gmail，把需要回复的重要邮件摘要出来，一起放在邮件里。这样早上一封邮件就能看到：今天要做的事 + 需要回复的邮件。

```bash
# 可以用 Gmail MCP 或 gmail API 实现
# 在 morning_brief.sh 里加一段读邮件的逻辑
```

**2. 更智能的 task 排期**
目前 Claude 只是根据当天来排，可以改成：
- 记住哪些 task 被连续推迟了（说明太难或优先级不对）
- 自动建议拆解大 task
- 在 evening recap 里明确问你"哪件事没做，为什么"

**3. 面试准备专项 tracking**
在 evening recap 里加一个 section，专门追踪面试准备进度：
- 今天刷了几道题
- System Design 覆盖了哪些题型
- 当前最弱的地方

### 中期

**4. Obsidian Living Notes 自动更新**
当 evening recap 识别到某个想法属于某个 Living Note（建房、面试、职业规划），自动 append 到对应的 Obsidian 文件里，不需要手动去记。

**5. Weekly Review 自动化**
每周日晚增加一个 weekly_review.sh：
- 汇总这周完成了什么
- 识别反复出现但没做的 task（说明需要重新评估）
- 为下周提前排期

**6. 接入更多数据源**
- 读 Obsidian 的 `#todo` 标签，自动把思考里冒出的 task 纳入
- 读 GitHub issues / PR（如果有工作项目）
- 读 Google Keep（如果开始用的话）

### 长期

**7. 习惯学习**
在 today_tasks.txt 旁边维护一个 `history.jsonl`，记录每天的计划 vs 实际完成情况。Claude 分析之后可以：
- 知道你哪类 task 总是完不成（调整建议方式）
- 知道你哪个时间段效率高（优化排期）
- 真正做到"跟着你，慢慢适应你的习惯"

**8. 移动端 capture 优化**
目前用 Apple Notes 已经够用，但如果想更快：
- iPhone 桌面加 Notes widget，打开就是 Inbox
- 用 Siri shortcut："Hey Siri，加到 Inbox：xxx"直接 append 到 Inbox note
- 考虑接入 Telegram bot（一条消息直接进 Inbox）

---

## 依赖

- macOS（Apple Notes + Calendar + Mail AppleScript）
- Claude Code CLI（`/opt/homebrew/bin/claude`）
- Apple Mail 连接 Google 账号（用于发邮件）
- Google Calendar 同步到 Mac Calendar.app
