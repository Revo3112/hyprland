#!/usr/bin/env bash
#
# Background.qml Patcher for Qt Quick Image Quality
#
# Location: ~/.config/hypr/custom/scripts/wallpaper-optimizer/
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
BACKUP_DIR="$XDG_CACHE_HOME/hypr/wallpaper-optimizer/backups"

BACKGROUND_QML="$HOME/.config/quickshell/ii/modules/ii/background/Background.qml"
MAX_BACKUPS=5

mkdir -p "$BACKUP_DIR"

log() {
    echo "[qml-patcher] $1"
}

cleanup_old_backups() {
    local count
    count=$(find "$BACKUP_DIR" -name "*.backup.*" -type f 2>/dev/null | wc -l)
    
    if [[ $count -gt $MAX_BACKUPS ]]; then
        local to_delete=$((count - MAX_BACKUPS))
        find "$BACKUP_DIR" -name "*.backup.*" -type f -printf '%T@ %p\n' 2>/dev/null | \
            sort -n | head -n "$to_delete" | cut -d' ' -f2- | \
            xargs rm -f 2>/dev/null || true
    fi
}

backup_file() {
    local file="$1"
    local backup_name
    backup_name=$(basename "$file").backup.$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/$backup_name"
    
    cp "$file" "$backup_path"
    log "Backup created: $backup_path"
    
    cleanup_old_backups
}

apply_patch() {
    log "Patching Background.qml for full resolution support..."
    
    if [[ ! -f "$BACKGROUND_QML" ]]; then
        log "ERROR: Background.qml not found at $BACKGROUND_QML"
        return 1
    fi
    
    if grep -q "sourceSize { width: -1, height: -1 }" "$BACKGROUND_QML" 2>/dev/null; then
        log "Already patched!"
        return 0
    fi
    
    backup_file "$BACKGROUND_QML"
    
    local temp_file="${BACKGROUND_QML}.patched.$$"
    
    log "Applying patch..."
    python3 "$SCRIPT_DIR/patch_background_qml.py" "$BACKGROUND_QML" "$temp_file"
    
    if [[ ! -f "$temp_file" ]]; then
        log "ERROR: Failed to create patched file"
        return 1
    fi
    
    if diff -q "$BACKGROUND_QML" "$temp_file" > /dev/null 2>&1; then
        log "No changes made - pattern not found in file"
        rm -f "$temp_file"
        return 1
    fi
    
    mv "$temp_file" "$BACKGROUND_QML"
    log "Patch applied successfully!"
    log ""
    log "Restart quickshell: pkill -f 'qs -c ii' && qs -c ii &"
    
    return 0
}

revert_patch() {
    log "Reverting Background.qml patch..."
    
    local latest_backup
    latest_backup=$(ls -t "$BACKUP_DIR"/Background.qml.backup.* 2>/dev/null | head -1)
    
    if [[ -z "$latest_backup" ]]; then
        log "No backup found to revert"
        return 1
    fi
    
    cp "$latest_backup" "$BACKGROUND_QML"
    log "Reverted to: $latest_backup"
    log ""
    log "Restart quickshell: pkill -f 'qs -c ii' && qs -c ii &"
    
    return 0
}

status() {
    log "Checking patch status..."
    
    if [[ ! -f "$BACKGROUND_QML" ]]; then
        log "Background.qml not found"
        return 1
    fi
    
    if grep -q "PATCHED" "$BACKGROUND_QML" 2>/dev/null || \
       grep -q "sourceSize { width: -1" "$BACKGROUND_QML" 2>/dev/null; then
        log "Status: PATCHED"
        log "File: $BACKGROUND_QML"
        return 0
    else
        log "Status: NOT PATCHED (using original sourceSize)"
        return 1
    fi
}

main() {
    local action="${1:-status}"
    
    case "$action" in
        apply)
            apply_patch
            ;;
        revert)
            revert_patch
            ;;
        status)
            status
            ;;
        *)
            echo "Usage: $0 {apply|revert|status}"
            return 1
            ;;
    esac
}

main "$@"
