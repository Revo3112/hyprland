#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# apply-gaming-memory-fixes.sh
# Complete gaming memory management setup for Arch Linux (2026)
#
# This script performs ALL memory management fixes:
#   1. Creates 16 GB NVMe swapfile (Btrfs) — like Windows pagefile
#   2. Replaces earlyoom → nohang (smarter OOM handler)
#   3. Applies optimal sysctl tuning
#   4. Sets THP to madvise
#   5. Sets up game OOM protection
#
# Run: sudo bash ~/.config/hypr/scripts/apply-gaming-memory-fixes.sh
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✅]${NC} $1"; }
warn() { echo -e "${YELLOW}[⚠️]${NC} $1"; }
err()  { echo -e "${RED}[❌]${NC} $1" >&2; }
step() { echo -e "\n${BLUE}═══ $1 ═══${NC}"; }

if [[ $EUID -ne 0 ]]; then
    err "This script requires sudo!"
    echo "Usage: sudo bash $0"
    exit 1
fi

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo miku)}"

echo ""
echo "╔═══════════════════════════════════════════════════╗"
echo "║  🎮 Gaming Memory Management — Arch Linux 2026   ║"
echo "╠═══════════════════════════════════════════════════╣"
echo "║  1. NVMe Swapfile (16 GB)                        ║"
echo "║  2. nohang OOM Handler                           ║"
echo "║  3. Sysctl Tuning                                ║"
echo "║  4. THP → madvise                                ║"
echo "║  5. Game OOM Protection                          ║"
echo "╚═══════════════════════════════════════════════════╝"
echo ""

# ═══════════════════════════════════════════════════
# STEP 1: NVMe Swapfile
# ═══════════════════════════════════════════════════
step "STEP 1/5: Creating 16 GB NVMe Swapfile"

if swapon --show | grep -q '/swap/swapfile'; then
    log "Swapfile already active, skipping creation"
else
    # Create btrfs subvolume
    if [[ ! -d /swap ]]; then
        btrfs subvolume create /swap
        log "Created Btrfs subvolume /swap"
    else
        log "Subvolume /swap already exists"
    fi

    # Create swapfile
    if [[ ! -f /swap/swapfile ]]; then
        echo "  Creating 16 GB swapfile on NVMe SSD... (this takes ~30 seconds)"
        btrfs filesystem mkswapfile --size 16G /swap/swapfile
        log "Created 16 GB swapfile"
    else
        log "Swapfile already exists"
        # Make sure it's formatted
        mkswap /swap/swapfile 2>/dev/null || true
    fi

    # Activate with low priority (below ZRAM at 100)
    swapon -p 10 /swap/swapfile
    log "Activated swapfile with priority 10 (below ZRAM priority 100)"

    # Add to fstab if not already there
    if ! grep -q '/swap/swapfile' /etc/fstab; then
        echo '/swap/swapfile none swap defaults,pri=10 0 0' >> /etc/fstab
        log "Added swapfile to /etc/fstab (persistent)"
    else
        log "Swapfile already in /etc/fstab"
    fi
fi

echo "  Current swap layout:"
swapon --show

# ═══════════════════════════════════════════════════
# STEP 2: Replace earlyoom → nohang
# ═══════════════════════════════════════════════════
step "STEP 2/5: Setting up nohang OOM Handler"

# Check if nohang is installed
if ! command -v nohang &>/dev/null; then
    warn "nohang not installed yet"
    echo ""
    echo "  nohang needs to be installed from AUR."
    echo "  Please run this AFTER the script completes:"
    echo ""
    echo "    yay -S nohang-git"
    echo "    sudo systemctl enable --now nohang-desktop.service"
    echo ""
    NOHANG_PENDING=true
else
    NOHANG_PENDING=false
    log "nohang is installed"
fi

# Disable earlyoom
if systemctl is-active earlyoom &>/dev/null; then
    systemctl disable --now earlyoom
    log "Disabled earlyoom"
elif systemctl is-enabled earlyoom &>/dev/null 2>&1; then
    systemctl disable earlyoom
    log "Disabled earlyoom (was inactive)"
else
    log "earlyoom already disabled/not found"
fi

# Configure nohang if installed
if [[ "$NOHANG_PENDING" == "false" ]] && [[ -f /etc/nohang/nohang-desktop.conf ]]; then
    CONF=/etc/nohang/nohang-desktop.conf

    # Apply gaming-optimized thresholds
    # soft_threshold = SIGTERM (warning before kill)
    sed -i 's/^soft_threshold_min_mem\s*=.*/soft_threshold_min_mem = 3 %/' "$CONF"
    sed -i 's/^soft_threshold_min_swap\s*=.*/soft_threshold_min_swap = 3 %/' "$CONF"
    # hard_threshold = SIGKILL (force kill)
    sed -i 's/^hard_threshold_min_mem\s*=.*/hard_threshold_min_mem = 2 %/' "$CONF"
    sed -i 's/^hard_threshold_min_swap\s*=.*/hard_threshold_min_swap = 2 %/' "$CONF"

    # Enable PSI monitoring (modern, more accurate than polling)
    sed -i 's/^psi_checking_enabled\s*=.*/psi_checking_enabled = True/' "$CONF"

    # Enable low memory warnings (desktop notification before kill)
    sed -i 's/^low_memory_warnings_enabled\s*=.*/low_memory_warnings_enabled = True/' "$CONF"

    systemctl enable --now nohang-desktop.service 2>/dev/null
    systemctl restart nohang-desktop.service
    log "Configured and restarted nohang-desktop"
else
    if [[ "$NOHANG_PENDING" == "true" ]]; then
        warn "nohang config will be applied after installation"
    fi
fi

# ═══════════════════════════════════════════════════
# STEP 3: Sysctl Tuning
# ═══════════════════════════════════════════════════
step "STEP 3/5: Applying Sysctl Tuning"

cat > /etc/sysctl.d/99-gaming-memory.conf << 'SYSCTL'
# ═══════════════════════════════════════════════════
# Gaming & Desktop Optimization — Arch Linux 2026
# Sources: SteamOS, CachyOS, Arch Wiki
# Hardware: 16 GB LPDDR5, ZRAM + NVMe swap, AMD APU
# ═══════════════════════════════════════════════════

# --- Swap ---
vm.swappiness = 100                    # SteamOS default (ZRAM + disk swap)
vm.page-cluster = 0                    # CachyOS: single page read (ZRAM optimal)

# --- Memory Limits ---
vm.max_map_count = 2147483642          # SteamOS: required by AAA Proton games
vm.min_free_kbytes = 131072            # Reserve 128 MB to prevent sudden OOM

# --- Cache ---
vm.vfs_cache_pressure = 50            # CachyOS: keep filesystem cache longer

# --- Compaction & Watermark ---
vm.compaction_proactiveness = 0        # Save CPU during gaming
vm.watermark_boost_factor = 0          # Reduce reclaim overhead
vm.watermark_scale_factor = 125        # Moderate watermark scaling

# --- I/O (adapted from CachyOS) ---
vm.dirty_bytes = 536870912             # 512 MB max dirty before blocking
vm.dirty_background_bytes = 268435456  # 256 MB triggers background flush

# --- CPU (from CachyOS) ---
kernel.nmi_watchdog = 0                # Disable NMI watchdog (reduce overhead)

# --- Network (from CachyOS) ---
net.core.netdev_max_backlog = 4096     # Handle burst traffic better
SYSCTL

# Remove old conflicting ZRAM sysctl file if present
rm -f /etc/sysctl.d/99-vm-zram-parameters.conf 2>/dev/null

sysctl --system &>/dev/null
log "Sysctl applied"

echo "  Key values:"
sysctl vm.swappiness vm.max_map_count vm.vfs_cache_pressure vm.min_free_kbytes vm.compaction_proactiveness

# ═══════════════════════════════════════════════════
# STEP 4: THP → madvise
# ═══════════════════════════════════════════════════
step "STEP 4/5: Setting THP to madvise"

cat > /etc/tmpfiles.d/thp-madvise.conf << 'THP'
# Transparent Hugepages: madvise (not always)
# "always" causes micro-stutter from defrag during gaming
# "madvise" = apps must opt-in (Wine/Proton already do this)
w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise
THP

# Apply immediately
echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
log "THP set to madvise"
echo "  Current: $(cat /sys/kernel/mm/transparent_hugepage/enabled)"

# ═══════════════════════════════════════════════════
# STEP 5: Script Permissions
# ═══════════════════════════════════════════════════
step "STEP 5/5: Setting up Scripts"

SCRIPT_DIR="/home/${REAL_USER}/.config/hypr/scripts"

chmod +x "$SCRIPT_DIR/protect-game.sh" 2>/dev/null && log "protect-game.sh → executable" || warn "protect-game.sh not found"
chmod +x "$SCRIPT_DIR/pre-game-cleanup.sh" 2>/dev/null && log "pre-game-cleanup.sh → executable" || warn "pre-game-cleanup.sh not found"

# Setup sudoers for protect-game.sh (no password needed)
SUDOERS_FILE="/etc/sudoers.d/99-gaming-memory"
cat > "$SUDOERS_FILE" << "EOF"
# Allow gaming memory management without password
miku ALL=(root) NOPASSWD: /home/miku/.config/hypr/scripts/protect-game.sh
EOF
chmod 440 "$SUDOERS_FILE"
visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1 && log "Sudoers configured for gaming scripts" || warn "Sudoers syntax error!"

# Cleanup old staging files
rm -f "$SCRIPT_DIR/earlyoom.conf.new" 2>/dev/null
rm -f "$SCRIPT_DIR/99-gaming-memory.conf.new" 2>/dev/null
log "Cleaned up staging files"

# ═══════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════
echo ""
echo "╔═══════════════════════════════════════════════════╗"
echo "║           ✅ ALL FIXES APPLIED                    ║"
echo "╠═══════════════════════════════════════════════════╣"
echo "║                                                   ║"
echo "║  Swapfile:  16 GB on NVMe (pri=10)               ║"
echo "║  OOM:       earlyoom disabled                    ║"
echo "║  Sysctl:    swappiness=100, max_map_count=2B     ║"
echo "║  THP:       madvise (safer for gaming)           ║"
echo "║  Scripts:   protect-game.sh ready                ║"
echo "║                                                   ║"
echo "╚═══════════════════════════════════════════════════╝"
echo ""

if [[ "${NOHANG_PENDING:-false}" == "true" ]]; then
    echo -e "${YELLOW}⚠️  REMAINING STEP: Install nohang${NC}"
    echo ""
    echo "  Run these commands:"
    echo "    yay -S nohang-git"
    echo "    sudo systemctl enable --now nohang-desktop.service"
    echo "    sudo bash $0  # re-run to configure nohang"
    echo ""
fi

echo "Before gaming, run:"
echo "  ~/.config/hypr/scripts/pre-game-cleanup.sh"
echo ""
echo "For OOM protection while gaming:"
echo "  sudo ~/.config/hypr/scripts/protect-game.sh &"
echo ""

# Final swap check
echo "Current swap layout:"
swapon --show
echo ""
echo "Current memory:"
free -h
