#!/usr/bin/env bash
# protect-game.sh — Auto-protect game processes from OOM killer
# Monitors for Wine/Proton game processes and lowers their oom_score_adj
# so the kernel/nohang kills other things first.
#
# Usage: sudo ~/.config/hypr/scripts/protect-game.sh
# Stop:  Ctrl+C or kill the process

set -euo pipefail

SCORE=-900  # -1000 = absolutely unkillable, -900 = almost unkillable
INTERVAL=5  # seconds between scans

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[protect-game]${NC} $1"; }
warn() { echo -e "${YELLOW}[protect-game]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    echo "Error: This script requires sudo" >&2
    exit 1
fi

protect_pid() {
    local pid="$1" name="$2"
    local current
    current=$(cat "/proc/${pid}/oom_score_adj" 2>/dev/null) || return 0
    if [[ "$current" != "$SCORE" ]]; then
        if printf '%d' "$SCORE" > "/proc/${pid}/oom_score_adj" 2>/dev/null; then
            log "Protected PID $pid ($name) → oom_score_adj=$SCORE"
        fi
    fi
}

log "Monitoring for game processes... (Ctrl+C to stop)"
log "OOM score target: $SCORE"
echo ""

while true; do
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        pid=$(echo "$line" | awk '{print $2}')
        name=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}' | xargs)
        # Get just the executable basename
        basename=$(basename "$(echo "$name" | awk '{print $1}')" 2>/dev/null || echo "$name")
        protect_pid "$pid" "$basename"
    done < <(ps aux 2>/dev/null | grep -E '\.exe|wineserver|wine-preloader|wine64-preloader' | grep -v grep || true)

    sleep "$INTERVAL"
done
