#!/usr/bin/env bash
# apply-monitors-keyword.sh v2
# Pengganti "hyprctl reload" untuk post_apply_exec hyprdynamicmonitors.
#
# Script ini dipanggil oleh hyprdynamicmonitors daemon setiap kali
# monitor hotplug terdeteksi. Membaca monitors.conf dan apply tiap
# baris monitor= via "hyprctl keyword monitor" satu per satu.
#
# Perbaikan v2:
#   - SELALU stop/restart portal (bukan hanya saat screenshare)
#   - Mirror-aware: apply source monitor dulu, tunggu settle, baru mirror
#   - Delay lebih panjang antar keyword (0.3s bukan 0.15s)
#   - Retry logic untuk keyword yang gagal
#   - Unload hyprexpo dengan delay lebih panjang (0.5s)

set -euo pipefail

MONITORS_CONF="${1:-$HOME/.config/hypr/monitors.conf}"
HYPREXPO_SO="/var/cache/hyprpm/miku/hyprland-plugins/hyprexpo.so"

KEYWORD_DELAY=0.3
MIRROR_SETTLE_DELAY=0.8
POST_MODESET_SETTLE=1.0

if [[ ! -f "$MONITORS_CONF" ]]; then
    echo "[apply-monitors-keyword] ERROR: $MONITORS_CONF not found" >&2
    exit 1
fi

# ── Stop portal sebelum modesetting ──────────────────────────────────────
echo "[apply-monitors-keyword] Stopping portal..."
systemctl --user stop xdg-desktop-portal-hyprland.service 2>/dev/null || true
systemctl --user stop xdg-desktop-portal.service 2>/dev/null || true
sleep 0.3

# ── Unload hyprexpo jika loaded (penyebab crash saat modesetting) ─────────
had_hyprexpo=false
if hyprctl plugin list 2>/dev/null | grep -q "hyprexpo"; then
    echo "[apply-monitors-keyword] Unloading hyprexpo plugin..."
    hyprctl plugin unload "$HYPREXPO_SO" 2>/dev/null && had_hyprexpo=true || true
    sleep 0.5
fi

# ── Drain pending pageflips ──────────────────────────────────────────────
sleep 0.1

echo "[apply-monitors-keyword] Applying monitors from: $MONITORS_CONF"

# ── Apply single keyword with retry ──────────────────────────────────────
apply_single_keyword() {
    local val="$1"
    local attempt=0
    local max_attempts=3

    while (( attempt < max_attempts )); do
        echo "[apply-monitors-keyword]   keyword monitor '$val' (attempt $((attempt+1)))"
        if hyprctl keyword monitor "$val" 2>/dev/null; then
            return 0
        fi
        (( attempt++ ))
        sleep 0.3
    done

    echo "[apply-monitors-keyword] WARN: '$val' failed after $max_attempts attempts" >&2
    return 1
}

# ── Detect mirror and collect lines ──────────────────────────────────────
is_mirror=false
if grep -q ",mirror," "$MONITORS_CONF" 2>/dev/null; then
    is_mirror=true
    echo "[apply-monitors-keyword] Mirror profile detected — sequential apply mode"
fi

declare -a source_lines=()
declare -a mirror_lines=()
declare -a other_lines=()

while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue

    val=$(echo "$line" | sed -n 's/^[[:space:]]*monitor[[:space:]]*=[[:space:]]*//p')
    [[ -z "$val" ]] && continue

    if [[ "$is_mirror" == true ]] && echo "$val" | grep -q ",mirror,"; then
        mirror_lines+=("$val")
    elif [[ "$is_mirror" == true ]]; then
        source_lines+=("$val")
    else
        other_lines+=("$val")
    fi
done < "$MONITORS_CONF"

# ── Apply keywords ───────────────────────────────────────────────────────
if [[ "$is_mirror" == true ]]; then
    # Apply source monitors first
    for val in "${source_lines[@]}"; do
        apply_single_keyword "$val"
        sleep "$KEYWORD_DELAY"
    done

    # Wait for source to settle before mirror
    echo "[apply-monitors-keyword] Waiting for source monitor settle (${MIRROR_SETTLE_DELAY}s)..."
    sleep "$MIRROR_SETTLE_DELAY"

    # Apply mirror targets
    for val in "${mirror_lines[@]}"; do
        apply_single_keyword "$val"
        sleep "$KEYWORD_DELAY"
    done
else
    for val in "${other_lines[@]}"; do
        apply_single_keyword "$val"
        sleep "$KEYWORD_DELAY"
    done
fi

# ── Post-modeset settle ──────────────────────────────────────────────────
echo "[apply-monitors-keyword] Waiting for post-modeset settle (${POST_MODESET_SETTLE}s)..."
sleep "$POST_MODESET_SETTLE"

# ── Reload hyprexpo setelah modesetting selesai ──────────────────────────
if [[ "$had_hyprexpo" == true ]] && [[ -f "$HYPREXPO_SO" ]]; then
    echo "[apply-monitors-keyword] Reloading hyprexpo plugin..."
    hyprctl plugin load "$HYPREXPO_SO" 2>/dev/null || {
        echo "[apply-monitors-keyword] WARN: failed to reload hyprexpo" >&2
    }
fi

# ── Restart portal ───────────────────────────────────────────────────────
echo "[apply-monitors-keyword] Restarting portal..."
systemctl --user start xdg-desktop-portal.service 2>/dev/null || true
sleep 0.8
systemctl --user start xdg-desktop-portal-hyprland.service 2>/dev/null || true

echo "[apply-monitors-keyword] Done."
