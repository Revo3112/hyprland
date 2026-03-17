#!/usr/bin/env bash
#
# Wallpaper Optimizer Hook
# Sourced by switchwall.sh to automatically optimize wallpapers
#
# Location: ~/.config/hypr/custom/scripts/wallpaper-optimizer/
#

WALLPAPER_OPTIMIZER_DIR="$HOME/.config/hypr/custom/scripts/wallpaper-optimizer"
WALLPAPER_OPTIMIZER_SCRIPT="$WALLPAPER_OPTIMIZER_DIR/optimize-wallpaper.sh"
WALLPAPER_OPTIMIZER_CACHE_DIR="$HOME/.cache/hypr/wallpaper-optimizer/processed"
WALLPAPER_OPTIMIZER_MAP_FILE="$HOME/.cache/hypr/wallpaper-optimizer/cache_map.txt"

mkdir -p "$WALLPAPER_OPTIMIZER_CACHE_DIR"

_wallpaper_optimizer_is_image() {
    local file="$1"
    [[ ! -f "$file" ]] && return 1
    local ext="${file##*.}"
    ext="${ext,,}"
    case "$ext" in
        jpg|jpeg|png|webp|bmp|tiff|tif|gif|avif) return 0 ;;
        *) return 1 ;;
    esac
}

_wallpaper_optimizer_is_video() {
    local file="$1"
    local ext="${file##*.}"
    ext="${ext,,}"
    case "$ext" in
        mp4|webm|mkv|avi|mov) return 0 ;;
        *) return 1 ;;
    esac
}

_wallpaper_optimizer_get_hash() {
    md5sum "$1" 2>/dev/null | awk '{print $1}'
}

_wallpaper_optimizer_get_cached() {
    local input="$1"
    local hash
    hash=$(_wallpaper_optimizer_get_hash "$input")
    local ext="${input##*.}"
    echo "$WALLPAPER_OPTIMIZER_CACHE_DIR/${hash}.${ext}"
}

_wallpaper_optimizer_save_mapping() {
    local cache_file="$1"
    local original="$2"
    local cache_name
    cache_name=$(basename "$cache_file")
    
    # Remove old entry, add new
    touch "$WALLPAPER_OPTIMIZER_MAP_FILE"
    grep -v "^$cache_name" "$WALLPAPER_OPTIMIZER_MAP_FILE" 2>/dev/null > "${WALLPAPER_OPTIMIZER_MAP_FILE}.tmp" || true
    echo -e "${cache_name}\t${original}" >> "${WALLPAPER_OPTIMIZER_MAP_FILE}.tmp"
    mv "${WALLPAPER_OPTIMIZER_MAP_FILE}.tmp" "$WALLPAPER_OPTIMIZER_MAP_FILE" 2>/dev/null || true
}

_wallpaper_optimizer_get_original() {
    local cache_file="$1"
    local cache_name
    cache_name=$(basename "$cache_file")
    
    if [[ -f "$WALLPAPER_OPTIMIZER_MAP_FILE" ]]; then
        grep "^$cache_name" "$WALLPAPER_OPTIMIZER_MAP_FILE" 2>/dev/null | head -1 | cut -f2
    fi
}

_wallpaper_optimizer_process() {
    local input="$1"
    
    # Video - pass through tanpa modifikasi
    if _wallpaper_optimizer_is_video "$input"; then
        echo "$input"
        return 0
    fi
    
    # Non-image - pass through
    if ! _wallpaper_optimizer_is_image "$input"; then
        echo "$input"
        return 0
    fi
    
    # Cek cache
    local cached
    cached=$(_wallpaper_optimizer_get_cached "$input")
    
    if [[ -f "$cached" ]]; then
        # Cache ada, cek apakah masih valid
        local input_mtime cached_mtime
        input_mtime=$(stat -c %Y "$input")
        cached_mtime=$(stat -c %Y "$cached")
        
        if [[ "$input_mtime" -le "$cached_mtime" ]]; then
            # Validasi cache tidak corrupt (check size)
            if [[ -s "$cached" ]]; then
                echo "$cached"
                return 0
            fi
        fi
    fi
    
    # Proses wallpaper dengan pre-scaling
    if [[ -x "$WALLPAPER_OPTIMIZER_SCRIPT" ]]; then
        local processed
        processed=$("$WALLPAPER_OPTIMIZER_SCRIPT" -i "$input" 2>/dev/null)
        # Validasi output tidak kosong/corrupt
        if [[ -f "$processed" && -s "$processed" ]]; then
            _wallpaper_optimizer_save_mapping "$processed" "$input"
            echo "$processed"
            return 0
        fi
    fi
    
    # Fallback ke original jika processing gagal
    echo "$input"
    return 0
}

# Cleanup old cache files
_wallpaper_optimizer_cleanup() {
    local max_files=20
    local count
    count=$(find "$WALLPAPER_OPTIMIZER_CACHE_DIR" -type f -name "*.jpg" -o -name "*.png" -o -name "*.webp" 2>/dev/null | wc -l)
    
    if [[ $count -gt $max_files ]]; then
        local to_delete=$((count - max_files))
        find "$WALLPAPER_OPTIMIZER_CACHE_DIR" -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.webp" \) -printf '%T@ %p\n' 2>/dev/null | \
            sort -n | head -n "$to_delete" | cut -d' ' -f2- | \
            xargs rm -f 2>/dev/null || true
    fi
}

# Validate cached wallpaper - recreate if missing
_wallpaper_optimizer_validate() {
    local config_path="$1"
    
    # Check if it's a cache path
    if [[ "$config_path" == *"$WALLPAPER_OPTIMIZER_CACHE_DIR"* ]]; then
        # Cache exists - ok
        if [[ -f "$config_path" ]]; then
            return 0
        fi
        
        # Cache missing - try to recover
        local original
        original=$(_wallpaper_optimizer_get_original "$config_path")
        
        if [[ -n "$original" && -f "$original" ]]; then
            # Recreate cache
            "$WALLPAPER_OPTIMIZER_SCRIPT" -i "$original" 2>/dev/null
            return 0
        fi
        
        return 1
    fi
    
    return 0
}