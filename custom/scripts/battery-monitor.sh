#!/usr/bin/env bash
# Battery Monitor - Event-driven low battery notifications (failsafe layer)
# Works alongside Quickshell Battery.qml as a redundant backup.
# Reads thresholds from ~/.config/illogical-impulse/config.json when available.

set -euo pipefail

CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"

# Read thresholds from config.json, fallback to defaults
if command -v jq &>/dev/null && [[ -f "$CONFIG_FILE" ]]; then
    LOW_THRESHOLD=$(jq -r '.battery.low // 25' "$CONFIG_FILE")
    CRITICAL_THRESHOLD=$(jq -r '.battery.critical // 10' "$CONFIG_FILE")
    EMERGENCY_THRESHOLD=$(jq -r '.battery.suspend // 5' "$CONFIG_FILE")
else
    LOW_THRESHOLD=25
    CRITICAL_THRESHOLD=10
    EMERGENCY_THRESHOLD=5
fi

# Cooldowns (seconds) to prevent notification spam
LOW_COOLDOWN=300        # 5 minutes
CRITICAL_COOLDOWN=120   # 2 minutes
EMERGENCY_COOLDOWN=30   # 30 seconds

# State tracking directory
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/battery-monitor"
mkdir -p "$STATE_DIR"

# --- Helper functions ---

get_pct() {
    cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo 100
}

# Check if AC adapter is physically plugged in (NOT battery status)
# This avoids the bug where BAT0/status reports "Full" while unplugged
is_on_ac() {
    local online
    online=$(cat /sys/class/power_supply/ADP1/online 2>/dev/null || echo 0)
    [[ "$online" == "1" ]]
}

# Cooldown check — returns 0 (allow) if never notified or cooldown expired
can_notify() {
    local level=$1 cooldown=$2 now last
    now=$(date +%s)
    if [[ -f "$STATE_DIR/$level" ]]; then
        last=$(cat "$STATE_DIR/$level")
        (( now - last >= cooldown ))
    fi
    # File doesn't exist = never notified before = return 0 (allow)
}

record() { date +%s > "$STATE_DIR/$1"; }

play_sound() {
    paplay "/usr/share/sounds/freedesktop/stereo/$1.oga" &>/dev/null & disown
}

send_notify() {
    notify-send -u "$1" -a "Battery" -t 8000 "$2" "$3" & disown
}

# --- Main check function ---

check() {
    local pct
    pct=$(get_pct)

    # If on AC power, clear all cooldown records and skip
    if is_on_ac; then
        rm -f "$STATE_DIR"/{low,critical,emergency} 2>/dev/null
        return
    fi

    # Not on AC — check battery thresholds (most critical first)
    if (( pct <= EMERGENCY_THRESHOLD )); then
        if can_notify emergency "$EMERGENCY_COOLDOWN"; then
            send_notify critical "🚨 BATERAI DARURAT!" "Sisa ${pct}% - Suspend 30 detik!"
            play_sound suspend-error
            record emergency
            # Auto-suspend after 30s if still not charging
            (sleep 30; is_on_ac || (( $(get_pct) > EMERGENCY_THRESHOLD )) || systemctl suspend) & disown
        fi
    elif (( pct <= CRITICAL_THRESHOLD )); then
        if can_notify critical "$CRITICAL_COOLDOWN"; then
            send_notify critical "⚠️ Baterai Kritis!" "Sisa ${pct}% - Colok charger!"
            play_sound dialog-warning
            record critical
        fi
    elif (( pct <= LOW_THRESHOLD )); then
        if can_notify low "$LOW_COOLDOWN"; then
            send_notify critical "🔋 Baterai Rendah" "Sisa ${pct}%"
            play_sound dialog-warning
            record low
        fi
    fi
}

# --- Entry point ---

# Cleanup state on exit
trap 'rm -rf "$STATE_DIR"' EXIT

# Exit silently if no battery found
[[ -d /sys/class/power_supply/BAT0 ]] || exit 0

# Run initial check
check

# Event-driven monitoring via UPower D-Bus signals
# The while loop survives gdbus restarts via pipefail being unset for this block
gdbus monitor --system --dest org.freedesktop.UPower \
    --object-path /org/freedesktop/UPower/devices/battery_BAT0 2>/dev/null | \
    while IFS= read -r line; do
        [[ "$line" =~ Percentage|State|WarningLevel ]] && check
    done