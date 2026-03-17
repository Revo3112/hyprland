#!/usr/bin/env bash
#
# Wallpaper Optimizer - Main Entry Point
#
# Location: ~/.config/hypr/custom/scripts/
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPTIMIZER_DIR="$SCRIPT_DIR/wallpaper-optimizer"
OPTIMIZE_SCRIPT="$OPTIMIZER_DIR/optimize-wallpaper.sh"
SWITCH_SCRIPT="$OPTIMIZER_DIR/switchwall-optimized.sh"
PATCH_SCRIPT="$OPTIMIZER_DIR/patch-background.sh"

XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
CACHE_DIR="$XDG_CACHE_HOME/hypr/wallpaper-optimizer"

log() {
    echo "[wallpaper-optimizer] $1"
}

show_help() {
    cat << 'EOF'
Wallpaper Optimizer for Qt Quick
================================

COMMANDS:
  optimize <file>       Optimize wallpaper (convert to sRGB, preserve resolution)
  switch <file> [args]  Switch wallpaper with auto-optimization
  patch                 Patch Background.qml for full resolution
  unpatch               Revert Background.qml patch
  status                Show current status
  cache-clear           Clear optimization cache
  cleanup               Remove old cache and backup files
  help                  Show this help

EXAMPLES:
  wallpaper-optimizer.sh optimize ~/Pictures/wallpaper.jpg
  wallpaper-optimizer.sh switch ~/Pictures/wallpaper.jpg --mode dark
  wallpaper-optimizer.sh patch
  wallpaper-optimizer.sh status

LOCATION:
  Scripts: ~/.config/hypr/custom/scripts/wallpaper-optimizer/
  Cache:   ~/.cache/hypr/wallpaper-optimizer/
EOF
}

optimize_cmd() {
    "$OPTIMIZE_SCRIPT" "$@"
}

switch_cmd() {
    "$SWITCH_SCRIPT" "$@"
}

patch_cmd() {
    "$PATCH_SCRIPT" apply
    log ""
    log "Restart quickshell: pkill -f 'qs -c ii' && qs -c ii &"
}

unpatch_cmd() {
    "$PATCH_SCRIPT" revert
    log ""
    log "Restart quickshell: pkill -f 'qs -c ii' && qs -c ii &"
}

status_cmd() {
    echo "=== Wallpaper Optimizer Status ==="
    echo ""
    
    echo "--- Background.qml Patch ---"
    "$PATCH_SCRIPT" status
    
    echo ""
    echo "--- Cache ---"
    local processed_dir="$CACHE_DIR/processed"
    if [[ -d "$processed_dir" ]]; then
        local count size
        count=$(find "$processed_dir" -type f 2>/dev/null | wc -l)
        size=$(du -sh "$processed_dir" 2>/dev/null | awk '{print $1}')
        echo "Cached: $count files, $size"
        echo "Location: $processed_dir"
    else
        echo "Cache is empty"
    fi
    
    echo ""
    echo "--- Current Wallpaper ---"
    local current
    current=$(cat ~/.local/state/quickshell/user/generated/wallpaper/path.txt 2>/dev/null || echo "Not set")
    echo "Path: $current"
    
    if [[ -f "$current" ]]; then
        local res
        res=$(identify -format "%wx%h" "$current" 2>/dev/null || echo "Unknown")
        echo "Resolution: $res"
    fi
}

cache_clear_cmd() {
    local processed_dir="$CACHE_DIR/processed"
    local backup_dir="$CACHE_DIR/backups"
    
    rm -rf "$processed_dir"/* 2>/dev/null || true
    rm -rf "$backup_dir"/* 2>/dev/null || true
    log "Cache and backups cleared"
}

cleanup_cmd() {
    "$OPTIMIZE_SCRIPT" --cleanup
    log "Cleanup completed"
}

main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        optimize)   optimize_cmd "$@" ;;
        switch)     switch_cmd "$@" ;;
        patch)      patch_cmd ;;
        unpatch)    unpatch_cmd ;;
        status)     status_cmd ;;
        cache-clear) cache_clear_cmd ;;
        cleanup)    cleanup_cmd ;;
        help|--help|-h) show_help ;;
        *)
            log "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
