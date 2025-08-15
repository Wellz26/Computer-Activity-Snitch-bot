# MacSnitch — Push Mac Activity to Telegram

Real-time macOS activity notifications sent straight to your phone via Telegram.  
No third-party daemons, no Homebrew deps — just Bash + AppleScript + `log stream`.

**Events captured**
- 🖥️ **Frontmost app changes** (focus switch)
- 🚀 **App launched / ✅ quit** (visible apps)
- 📡 **Wi-Fi SSID changes** (join/leave/roam)
- 🔌 **USB/Volume mount/unmount** (Disk Arbitration / IOUSB)
- ⬇️ **New/updated items in Downloads** (lightweight polling)

> The noisy “general network stack” watcher is intentionally **not included**.

---

## Why Telegram?
- Free, fast push to iOS/Android
- Simple HTTP API
- No Apple Developer account or APNs setup

If you prefer Pushover/Discord/Slack/iMessage, see **Alternatives** below.

---

## Requirements
- macOS 10.12+ (tested on Ventura/Sonoma/Sequoia)
- Built-ins: `bash`, `osascript`, `log`, `awk`, `sed`, `curl`
- **Permissions**:
  - **System Settings → Privacy & Security → Accessibility** → allow your Terminal app (for app names/focus)
  - Optional: **Full Disk Access** → your Terminal app (for better Downloads detection)

---

## Setup

### 1) Create a Telegram Bot & Get Your Chat ID
1. In Telegram, talk to **@BotFather** → `/newbot` → follow prompts.
2. Copy your **bot token** (format: `123456789:ABC...`).
3. Start a chat with your bot (press **Start**, send `hi`).
4. Get your **chat_id**:
