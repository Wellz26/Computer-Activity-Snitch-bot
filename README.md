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

If you prefer Pushover/Discord/Slack/iMessage, you can replace the `notify()` function in the script.

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
   ```
   https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates
   ```
   Find `"chat":{"id": 123456789, ... }`.

> Treat the token like a password. **Do not commit it to Git.**

### 2) Configure secrets
Create a local config (not committed). The script reads from `.env` in the current directory and `~/.macsnitch/config` if present.

**.env (preferred)**
```env
TELEGRAM_BOT_TOKEN=YOUR_BOT_TOKEN
CHAT_ID=YOUR_CHAT_ID_NUMBER
```

**.gitignore (recommended in your repo)**
```
.env
.macsnitch/
ActivityWatcher/
```

---

## Run

```bash
chmod +x watch-mac-to-telegram.sh
./watch-mac-to-telegram.sh
```
You should receive:
> ✅ MacSnitch started on HOSTNAME at YYYY-MM-DD HH:MM:SS

Open/quit apps, change Wi‑Fi, plug a USB drive, or drop a file in `~/Downloads` to see alerts.

---

## Flags / Customization

```text
--no-focus         disable frontmost app notifications
--no-apps          disable app launch/quit notifications
--no-wifi          disable Wi-Fi SSID change notifications
--no-usb           disable USB/volume notifications
--no-downloads     disable Downloads folder notifications
--interval N       polling interval in seconds (default 2)
--downloads-dir P  path to watch for new/updated files (default ~/Downloads)
-h, --help         show usage
```

Examples:
```bash
# Only apps and USB, polling every 5s
./watch-mac-to-telegram.sh --no-focus --no-wifi --no-downloads --interval 5

# Watch a custom folder instead of Downloads
./watch-mac-to-telegram.sh --downloads-dir "$HOME/Work/Incoming"
```

---

## Start at Login (LaunchAgent)

Create `~/Library/LaunchAgents/com.macsnitch.watcher.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.macsnitch.watcher</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/YOUR_USER/path/to/watch-mac-to-telegram.sh</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>TELEGRAM_BOT_TOKEN</key><string>YOUR_TOKEN</string>
    <key>CHAT_ID</key><string>YOUR_CHAT_ID</string>
  </dict>
  <key>StandardOutPath</key><string>/Users/YOUR_USER/ActivityWatcher/launchagent.out</string>
  <key>StandardErrorPath</key><string>/Users/YOUR_USER/ActivityWatcher/launchagent.err</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
```

Load it:
```bash
launchctl load -w ~/Library/LaunchAgents/com.macsnitch.watcher.plist
```

Stop/unload:
```bash
launchctl unload -w ~/Library/LaunchAgents/com.macsnitch.watcher.plist
```

---

## Security Notes
- **Do not commit tokens**: keep them in `.env` or `~/.macsnitch/config`.
- Telegram bots are not end-to-end encrypted; avoid sending sensitive filenames if that matters.
- To reduce metadata, you can change the Downloads notifier to generic text:
  ```bash
  # in downloads_watcher(): replace the notify line with:
  notify "⬇️ New item in Downloads"
  ```

---

## Troubleshooting
- **No app names / focus events** → grant Accessibility to your terminal app.
- **No Downloads alerts** → grant Full Disk Access or check the correct folder path.
- **No Wi‑Fi SSID** → some macOS versions hide `airport`; the script falls back to `networksetup`.
- **Duplicate / noisy alerts** → you may have multiple instances running:
  ```bash
  ps aux | grep watch-mac-to-telegram | grep -v grep
  pkill -f watch-mac-to-telegram.sh
  ```
- **Change throttles** → search `throttle("focus_*", 10)` etc. and adjust seconds.

---

## License
MIT (optional — add a `LICENSE` file if you want to publish under MIT).
