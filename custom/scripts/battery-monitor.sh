#!/usr/bin/env bash
# Battery Monitor - Event-driven low battery notifications
# Synced with Quickshell config (~/.config/illogical-impulse/config.json)

set -euo pipefail

LOW_THRESHOLD=25
CRITICAL_THRESHOLD=10
EMERGENCY_THRESHOLD=5

LOW_COOLDOWN=300
CRITICAL_COOLDOWN=120
EMERGENCY_COOLDOWN=30

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/battery-monitor"
mkdir -p "$STATE_DIR"

get_pct() { cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo 100; }
is_charging() { [[ "$(cat /sys/class/power_supply/BAT0/status 2>/dev/null)" =~ ^(Charging|Full)$ ]]; }
can_notify() {
    local level=$1 cooldown=$2 now last
    now=$(date +%s)
    [[ -f "$STATE_DIR/$level" ]] && { last=$(cat "$STATE_DIR/$level"); ((now - last >= cooldown)); } || true
}
record() { date +%s > "$STATE_DIR/$1"; }
play() { paplay "/usr/share/sounds/freedesktop/stereo/$1.oga" &>/dev/null & disown; }
notify() { notify-send -u "$1" -a "Battery" -t 8000 "$2" "$3" & disown; }

check() {
    local pct=$(get_pct)
    is_charging && { rm -f "$STATE_DIR"/{low,critical,emergency} 2>/dev/null; return; }
    
    if [[ $pct -le $EMERGENCY_THRESHOLD ]]; then
        can_notify emergency $EMERGENCY_COOLDOWN && {
            notify critical "🚨 BATERAI DARURAT!" "Sisa ${pct}% - Suspend 30 detik!"
            play suspend-error; record emergency
            (sleep 30; is_charging || [[ $(get_pct) -gt $EMERGENCY_THRESHOLD ]] || systemctl suspend) & disown
        }
    elif [[ $pct -le $CRITICAL_THRESHOLD ]]; then
        can_notify critical $CRITICAL_COOLDOWN && {
            notify critical "⚠️ Baterai Kritis!" "Sisa ${pct}% - Colok charger!"
            play dialog-warning; record critical
        }
    elif [[ $pct -le $LOW_THRESHOLD ]]; then
        can_notify low $LOW_COOLDOWN && {
            notify normal "🔋 Baterai Rendah" "Sisa ${pct}%"
            play power-unplug; record low
        }
    fi
}

trap 'rm -rf "$STATE_DIR"' EXIT

[[ -d /sys/class/power_supply/BAT0 ]] || exit 0
check
gdbus monitor --system --dest org.freedesktop.UPower \
    --object-path /org/freedesktop/UPower/devices/battery_BAT0 2>/dev/null | \
    while IFS= read -r line; do [[ "$line" =~ Percentage|State|WarningLevel ]] && check; done