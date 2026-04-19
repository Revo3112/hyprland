#!/usr/bin/env bash
# pre-game-cleanup.sh — Free up RAM before launching heavy games
# Usage: ~/.config/hypr/scripts/pre-game-cleanup.sh
#
# Typical savings: ~4-6 GB depending on what's running

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[pre-game]${NC} $1"; }
warn() { echo -e "${YELLOW}[pre-game]${NC} $1"; }
err()  { echo -e "${RED}[pre-game]${NC} $1"; }

show_mem() {
    local avail
    avail=$(awk '/MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo)
    echo -e "${GREEN}RAM Available: ${avail} MiB${NC}"
}

saved=0

kill_app() {
    local name="$1" pattern="$2" label="$3"
    local before after
    if pgrep -f "$pattern" &>/dev/null; then
        before=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
        pkill -f "$pattern" 2>/dev/null || true
        sleep 1
        after=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
        local diff=$(( (after - before) / 1024 ))
        (( diff < 0 )) && diff=0
        saved=$(( saved + diff ))
        log "✅ $label ditutup (+${diff} MiB)"
    else
        log "⏭️  $label tidak berjalan, skip"
    fi
}

echo ""
echo "═══════════════════════════════════════"
echo "  🎮 Pre-Game RAM Cleanup"
echo "═══════════════════════════════════════"
echo ""

log "RAM sebelum cleanup:"
show_mem
echo ""

# --- Kill heavy apps ---
log "Menutup aplikasi berat..."

kill_app "Antigravity" "antigravity" "Antigravity (Electron)"
kill_app "OpenCode" "opencode" "OpenCode"
kill_app "Zen Browser" "zen-bin" "Zen Browser"

# --- Stop optional services ---
log "Menghentikan service opsional..."

if docker ps -q 2>/dev/null | grep -q .; then
    before=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
    docker stop $(docker ps -q) 2>/dev/null || true
    sleep 2
    after=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
    diff=$(( (after - before) / 1024 ))
    (( diff < 0 )) && diff=0
    saved=$(( saved + diff ))
    log "✅ Docker containers stopped (+${diff} MiB)"
else
    log "⏭️  Tidak ada container Docker berjalan"
fi

# --- Flush caches ---
log "Membersihkan filesystem cache..."
before=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
sync
sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null || warn "Butuh sudo untuk drop caches"
after=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
diff=$(( (after - before) / 1024 ))
(( diff < 0 )) && diff=0
saved=$(( saved + diff ))
log "✅ Cache dibersihkan (+${diff} MiB)"

# --- Compact ZRAM ---
log "Mengompakkan ZRAM..."
sudo sh -c 'echo all > /sys/block/zram0/compact' 2>/dev/null || true
log "✅ ZRAM compacted"

echo ""
echo "═══════════════════════════════════════"
log "RAM setelah cleanup:"
show_mem
echo ""
log "💾 Total dihemat: ~${saved} MiB"
echo "═══════════════════════════════════════"
echo ""
log "✅ Siap gaming! Silakan launch game dari Steam."

# Send desktop notification
notify-send -u normal -t 8000 "🎮 Pre-Game Cleanup" "RAM dibebaskan ~${saved} MiB. Siap gaming!" 2>/dev/null || true
