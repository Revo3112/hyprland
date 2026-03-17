#!/usr/bin/env bash
# safe-monitor-switch.sh v4.1 - Refactored
# Workaround untuk Hyprland 0.54.0 crash saat switch monitor profile.
#
# Crash yang ditangani:
#   1. SEGV di CMonitorFrameScheduler::onFrame() — bad_any_cast saat
#      hyprexpo plugin hook ke rendering pipeline selama modesetting.
#      FIX: Unload hyprexpo sebelum switch, reload sesudahnya.
#
#   2. DRM page-flip race condition — "Cannot commit when a page-flip
#      is awaiting" berulang saat 2 monitor di-modeset bersamaan.
#      FIX: Apply monitor keyword satu per satu dengan jeda cukup.
#            Untuk mirror: set source monitor dulu, tunggu settle,
#            baru set mirror target.
#
#   3. SIGABRT di CScreenshareFrame::copyDmabuf — screenshare/portal
#      aktif saat monitor topology berubah.
#      FIX: SELALU stop portal sebelum switch (bukan hanya saat
#      screenshare aktif — portal bisa interfere tanpa screenshare).
#
#   4. Swapchain reallocation crash saat mirror — HDMI 4K di-resize
#      ke 1080p trigger GBM buffer reallocation race.
#      FIX: Force HDMI ke resolusi laptop di mirror config.

set -euo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================

readonly NOTIFY_TIMEOUT=5000
readonly HYPRCONFIGS="$HOME/.config/hyprdynamicmonitors/hyprconfigs"
readonly MONITORS_CONF="$HOME/.config/hypr/monitors.conf"
readonly HYPREXPO_SO="/var/cache/hyprpm/miku/hyprland-plugins/hyprexpo.so"

# Timing delays (seconds) - Terlalu kecil → DRM page-flip storm
readonly KEYWORD_DELAY=0.3
readonly MIRROR_SETTLE_DELAY=0.8
readonly POST_MODESET_SETTLE=1.0
readonly PORTAL_STOP_WAIT=0.5
readonly PORTAL_START_WAIT=0.8
readonly HYPREXPO_UNLOAD_WAIT=0.5
readonly PAGEFLIP_DRAIN_WAIT=0.1

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

notify() {
    local urgency="${1:-normal}"
    local title="${2:-Monitor}"
    local message="${3:-}"
    
    notify-send -u "$urgency" -t "$NOTIFY_TIMEOUT" "$title" "$message" \
        2>/dev/null || true
}

die() {
    notify "critical" "Monitor Switch Error" "$1"
    echo "[safe-monitor-switch] ERROR: $1" >&2
    exit 1
}

usage() {
    cat >&2 <<EOF
Usage: $0 <profile>

Profiles:
  laptop-only   — only laptop screen (eDP-1)
  extend        — extend HDMI to the right
  mirror        — mirror laptop to HDMI
  hdmi-only     — disable laptop, use HDMI only
EOF
    exit 1
}

# =============================================================================
# PROFILE MANAGEMENT
# =============================================================================

normalize_profile() {
    local profile="$1"
    
    case "$profile" in
        mirror|hdmi-mirror)     echo "hdmi-mirror" ;;
        extend|hdmi-extend*)    echo "hdmi-extend-right" ;;
        hdmi-only)              echo "hdmi-only" ;;
        laptop|laptop-only)     echo "laptop-only" ;;
        *) die "Profile tidak dikenal: '$profile'. Gunakan: mirror|extend|hdmi-only|laptop-only" ;;
    esac
}

# =============================================================================
# PORTAL MANAGEMENT
# =============================================================================

stop_portal() {
    echo "[safe-monitor-switch] Menghentikan portal..."

    if systemctl --user is-active --quiet xdg-desktop-portal-hyprland.service 2>/dev/null; then
        systemctl --user stop xdg-desktop-portal-hyprland.service
        _wait_for_process_stop "xdg-desktop-portal-hyprland" 6 "$PORTAL_STOP_WAIT"
    fi

    if systemctl --user is-active --quiet xdg-desktop-portal.service 2>/dev/null; then
        systemctl --user stop xdg-desktop-portal.service
        sleep 0.3
    fi

    echo "[safe-monitor-switch] Portal dihentikan."
}

restart_portal() {
    echo "[safe-monitor-switch] Merestart portal..."
    systemctl --user start xdg-desktop-portal.service 2>/dev/null || true
    sleep "$PORTAL_START_WAIT"
    systemctl --user start xdg-desktop-portal-hyprland.service 2>/dev/null || true
    echo "[safe-monitor-switch] Portal direstart."
}

_wait_for_process_stop() {
    local process="$1"
    local max_attempts="$2"
    local delay="$3"
    local i=0
    
    while pgrep -x "$process" &>/dev/null && (( i < max_attempts )); do
        sleep "$delay"
        (( i++ ))
    done
}

# =============================================================================
# PLUGIN MANAGEMENT
# =============================================================================

unload_hyprexpo() {
    if hyprctl plugin list 2>/dev/null | grep -q "hyprexpo"; then
        echo "[safe-monitor-switch] Unloading hyprexpo plugin..."
        hyprctl plugin unload "$HYPREXPO_SO" 2>/dev/null || true
        sleep "$HYPREXPO_UNLOAD_WAIT"
        return 0
    fi
    return 1
}

reload_hyprexpo() {
    if [[ -f "$HYPREXPO_SO" ]]; then
        echo "[safe-monitor-switch] Reloading hyprexpo plugin..."
        hyprctl plugin load "$HYPREXPO_SO" 2>/dev/null || {
            echo "[safe-monitor-switch] WARN: gagal reload hyprexpo" >&2
        }
    fi
}

# =============================================================================
# MONITOR KEYWORD APPLICATION
# =============================================================================

apply_single_keyword() {
    local val="$1"
    local attempt=0
    local max_attempts=3

    while (( attempt < max_attempts )); do
        echo "[safe-monitor-switch]   hyprctl keyword monitor '$val' (attempt $((attempt+1)))"
        if hyprctl keyword monitor "$val" 2>/dev/null; then
            return 0
        fi
        (( attempt++ ))
        echo "[safe-monitor-switch]   WARN: keyword gagal, retry setelah delay..." >&2
        sleep 0.3
    done

    echo "[safe-monitor-switch]   WARN: keyword '$val' gagal setelah $max_attempts percobaan" >&2
    return 1
}

apply_monitor_keyword() {
    local conf_path="$1"
    local is_mirror=false

    # Deteksi apakah ini mirror config
    if grep -q ",mirror," "$conf_path" 2>/dev/null; then
        is_mirror=true
        echo "[safe-monitor-switch] Mirror profile terdeteksi — sequential apply mode"
    fi

    # Collect semua monitor lines
    local -a source_lines=()
    local -a mirror_lines=()
    local -a other_lines=()

    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        local val
        val=$(echo "$line" | sed -n 's/^[[:space:]]*monitor[[:space:]]*=[[:space:]]*//p')
        [[ -z "$val" ]] && continue

        if [[ "$is_mirror" == true ]] && echo "$val" | grep -q ",mirror,"; then
            mirror_lines+=("$val")
        elif [[ "$is_mirror" == true ]] && ! echo "$val" | grep -q ",mirror,"; then
            source_lines+=("$val")
        else
            other_lines+=("$val")
        fi
    done < "$conf_path"

    if [[ "$is_mirror" == true ]]; then
        _apply_mirror_profile "$conf_path" source_lines mirror_lines
    else
        _apply_normal_profile other_lines
    fi
}

_apply_mirror_profile() {
    local conf_path="$1"
    local -n source_arr=$2
    local -n mirror_arr=$3

    # Apply source monitors first
    for val in "${source_arr[@]}"; do
        apply_single_keyword "$val"
        sleep "$KEYWORD_DELAY"
    done

    # Wait for source monitor to settle before setting up mirror
    echo "[safe-monitor-switch] Menunggu source monitor settle (${MIRROR_SETTLE_DELAY}s)..."
    sleep "$MIRROR_SETTLE_DELAY"

    # Apply mirror targets
    for val in "${mirror_arr[@]}"; do
        apply_single_keyword "$val"
        sleep "$KEYWORD_DELAY"
    done
}

_apply_normal_profile() {
    local -n lines=$1
    
    for val in "${lines[@]}"; do
        apply_single_keyword "$val"
        sleep "$KEYWORD_DELAY"
    done
}

# =============================================================================
# PAGE FLIP MANAGEMENT
# =============================================================================

drain_pageflips() {
    echo "[safe-monitor-switch] Draining pending pageflips..."
    # Hyprctl dispatch dpms toggle is too aggressive; just wait for frames
    # to complete their cycle. At 60Hz, one frame = ~16.7ms.
    # Wait 3 frame cycles to be safe.
    sleep "$PAGEFLIP_DRAIN_WAIT"
}

# =============================================================================
# PROFILE SWITCHING
# =============================================================================

switch_monitor_profile() {
    local profile="$1"
    local conf_path="$HYPRCONFIGS/$profile.conf"

    echo "[safe-monitor-switch] Switching ke profil: $profile"

    [[ -f "$conf_path" ]] || die "Config file tidak ditemukan: $conf_path"

    # Copy config ke monitors.conf (BUKAN symlink!)
    cp -f "$conf_path" "$MONITORS_CONF"

    # Apply via hyprctl keyword — TIDAK pakai hyprctl reload!
    apply_monitor_keyword "$conf_path"

    echo "[safe-monitor-switch] Monitor profile '$profile' diterapkan."
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    [[ -z "${PROFILE:-}" ]] && usage

    local profile
    profile=$(normalize_profile "$PROFILE")

    echo "[safe-monitor-switch] === Mulai switch ke: $profile ==="
    notify "normal" "Monitor Switch" "Switching ke profil '$profile'..."

    # 1. SELALU stop portal sebelum switch monitor
    #    (Portal bisa interfere bahkan tanpa screenshare aktif)
    stop_portal

    # 2. Unload hyprexpo plugin (ROOT CAUSE utama crash!)
    #    Plugin ini hook ke rendering pipeline dan corrupt internal state
    #    (bad_any_cast di CMonitorFrameScheduler::onFrame) saat modesetting.
    local had_hyprexpo=false
    if unload_hyprexpo; then
        had_hyprexpo=true
    fi

    # 3. Drain pending pageflips sebelum mulai modesetting
    drain_pageflips

    # 4. Apply monitor config (atomic keyword, mirror-aware)
    switch_monitor_profile "$profile"

    # 5. Tunggu Hyprland settle setelah modesetting
    echo "[safe-monitor-switch] Menunggu post-modeset settle (${POST_MODESET_SETTLE}s)..."
    sleep "$POST_MODESET_SETTLE"

    # 6. Reload hyprexpo plugin setelah modesetting selesai
    if [[ "$had_hyprexpo" == true ]]; then
        reload_hyprexpo
    fi

    # 7. Restart portal
    restart_portal

    notify "low" "Monitor Switch" "Selesai: profil '$profile' aktif."
    echo "[safe-monitor-switch] === Selesai ==="
}

main "$@"
