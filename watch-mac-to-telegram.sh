#!/usr/bin/env bash
# watch-mac-to-telegram.sh
# Pushes macOS activity events to a Telegram chat.
# Events: frontmost app changes, app launch/quit, Wi-Fi SSID changes,
# USB/volume mount/unmount, and new/updated files in ~/Downloads.
#
# Configuration (do NOT hardcode secrets in Git):
#   - Set TELEGRAM_BOT_TOKEN and CHAT_ID as environment variables, OR
#   - Put them in ~/.macsnitch/config or ./.env (KEY=VALUE lines; see README).
#
# Usage:
#   chmod +x watch-mac-to-telegram.sh
#   TELEGRAM_BOT_TOKEN=xxx CHAT_ID=123 ./watch-mac-to-telegram.sh
#
# Flags:
#   --no-focus       disable frontmost app notifications
#   --no-apps        disable app launch/quit notifications
#   --no-wifi        disable Wi-Fi SSID change notifications
#   --no-usb         disable USB/volume notifications
#   --no-downloads   disable Downloads folder notifications
#   --interval N     polling interval in seconds (default 2)
#   --downloads-dir PATH (default: ~/Downloads)
#   -h, --help       show help
#
# Requires: macOS 10.12+ (uses `osascript`, `log stream`, `networksetup`/`airport`, `awk`, `curl`)
# Permissions: grant Terminal/iTerm Accessibility (and optionally Full Disk Access) for best results.

set -euo pipefail

# ---------- Defaults ----------
CHECK_INTERVAL=2
DOWNLOADS_DIR="${HOME}/Downloads"
LOG_DIR="${HOME}/ActivityWatcher"
AIRPORT="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"

ENABLE_FOCUS=1
ENABLE_APPS=1
ENABLE_WIFI=1
ENABLE_USB=1
ENABLE_DOWNLOADS=1

mkdir -p "$LOG_DIR"

# ---------- Helpers ----------
die() { echo "Error: $*" >&2; exit 1; }
ts() { date "+%Y-%m-%d %H:%M:%S"; }

# Load KEY=VALUE pairs from a file (ignore comments/blank lines)
load_kv_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      local k="${BASH_REMATCH[1]}"
      local v="${BASH_REMATCH[2]}"
      v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"   # strip simple quotes
      export "$k=$v"
    fi
  done < "$f"
}

# Try config sources (no secrets in repo)
load_kv_file "./.env"
load_kv_file "${HOME}/.macsnitch/config"

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
CHAT_ID="${CHAT_ID:-}"

usage() {
  sed -n '1,80p' "$0" | sed -n '1,60p' | sed 's/^# \{0,1\}//' | sed 's/^$//'
  exit 0
}

# ---------- Arg parse ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-focus)      ENABLE_FOCUS=0; shift ;;
    --no-apps)       ENABLE_APPS=0; shift ;;
    --no-wifi)       ENABLE_WIFI=0; shift ;;
    --no-usb)        ENABLE_USB=0; shift ;;
    --no-downloads)  ENABLE_DOWNLOADS=0; shift ;;
    --interval)      CHECK_INTERVAL="${2:-}" ; [[ -n "$CHECK_INTERVAL" ]] || die "--interval needs a number"; shift 2 ;;
    --downloads-dir) DOWNLOADS_DIR="${2:-}" ; [[ -n "$DOWNLOADS_DIR" ]] || die "--downloads-dir needs a path"; shift 2 ;;
    -h|--help)       usage ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ -n "$TELEGRAM_BOT_TOKEN" ]] || die "TELEGRAM_BOT_TOKEN is not set (see README)"
[[ -n "$CHAT_ID" ]]            || die "CHAT_ID is not set (see README)"

notify() {
  # Use --data-urlencode to avoid breaking on spaces/specials
  local msg="$1"
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT_ID}" \
    --data-urlencode "text=${msg}" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null || true
}

# Simple per-key throttle via timestamp files
throttle() {
  local key="$1"; local seconds="$2"
  local f="${LOG_DIR}/.last_${key//[^A-Za-z0-9_]/_}"
  local now last=0
  now=$(date +%s)
  [[ -f "$f" ]] && last=$(cat "$f" 2>/dev/null || echo 0)
  if (( now - last >= seconds )); then echo "$now" > "$f"; return 0; fi
  return 1
}

# Track child PIDs for clean shutdown
PIDS=()
cleanup() {
  notify "🛑 MacSnitch stopped on $(hostname) at $(ts)."
  for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done
}
trap cleanup EXIT INT TERM

# ---------- Watchers ----------
foreground_watcher() {
  local last=""
  while :; do
    local now
    now=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || echo "")
    if [[ -n "$now" && "$now" != "$last" ]]; then
      throttle "focus_${now}" 10 && notify "🖥️ Focus → ${now}"
      last="$now"
    fi
    sleep "$CHECK_INTERVAL"
  done
}

visible_apps_watcher() {
  local prev="${LOG_DIR}/.visible_prev"
  : > "$prev"
  while :; do
    local current tmp="${LOG_DIR}/.visible_cur.$$"
    current=$(osascript -e 'tell application "System Events" to get name of (every process where background only is false)' 2>/dev/null \
      | tr ',' '\n' | sed 's/^ *//; s/ *$//' | sort -u)
    printf "%s\n" $current > "$tmp" 2>/dev/null || true

    comm -13 "$prev" "$tmp" | while read -r a; do [[ -n "$a" ]] && notify "🚀 App launched: ${a}"; done
    comm -23 "$prev" "$tmp" | while read -r q; do [[ -n "$q" ]] && notify "✅ App quit: ${q}"; done

    mv "$tmp" "$prev" 2>/dev/null || true
    sleep "$CHECK_INTERVAL"
  done
}

wifi_poll_watcher() {
  local last="(start)"
  while :; do
    local ssid="(unknown)"
    if [[ -x "$AIRPORT" ]]; then
      ssid=$("$AIRPORT" -I 2>/dev/null | awk -F': ' '/ SSID/ {print $2; exit}')
      [[ -z "$ssid" ]] && ssid="(disconnected)"
    else
      ssid=$(networksetup -getairportnetwork en0 2>/dev/null | awk -F': ' '{print $2}')
      [[ -z "$ssid" ]] && ssid="(unknown)"
    fi
    if [[ "$ssid" != "$last" ]]; then notify "📡 SSID → ${ssid}"; last="$ssid"; fi
    sleep "$CHECK_INTERVAL"
  done
}

usb_volume_watcher() {
  log stream --style syslog --level info \
    --predicate 'subsystem == "com.apple.iokit.IOUSB" || subsystem == "com.apple.diskarbitration"' 2>&1 \
  | while IFS= read -r line; do
      if echo "$line" | grep -Eiq 'USB|attached|detached|mount|unmount|Volume'; then
        throttle "io_event" 2 && notify "🔌 IO/Disks: $(echo "$line" | sed 's/^[^:]*: //')"
      fi
    done
}

downloads_watcher() {
  local last_mtime=0
  while :; do
    local mtime
    mtime=$(stat -f %m "$DOWNLOADS_DIR" 2>/dev/null || echo 0)
    if (( mtime > last_mtime )); then
      # files changed within last 2 minutes
      find "$DOWNLOADS_DIR" -type f -mmin -2 -maxdepth 1 2>/dev/null \
        | while read -r f; do
            local base="${f##*/}"
            throttle "dl_${base}" 30 && notify "⬇️ ${base} updated"
          done
      last_mtime=$mtime
    fi
    sleep "$CHECK_INTERVAL"
  done
}

# ---------- Start ----------
notify "✅ MacSnitch started on $(hostname) at $(ts)."

(( ENABLE_FOCUS == 1 ))      && foreground_watcher & PIDS+=($!)
(( ENABLE_APPS == 1 ))       && visible_apps_watcher & PIDS+=($!)
(( ENABLE_WIFI == 1 ))       && wifi_poll_watcher & PIDS+=($!)
(( ENABLE_USB == 1 ))        && usb_volume_watcher & PIDS+=($!)
(( ENABLE_DOWNLOADS == 1 ))  && downloads_watcher & PIDS+=($!)

wait
