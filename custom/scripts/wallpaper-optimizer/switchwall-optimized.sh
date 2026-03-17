#!/usr/bin/env bash
#
# Wallpaper Switcher Wrapper with Optimizer
# Wraps switchwall.sh with automatic wallpaper optimization
#
# Location: ~/.config/hypr/custom/scripts/wallpaper-optimizer/
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPTIMIZER="$SCRIPT_DIR/optimize-wallpaper.sh"
ORIGINAL_SWITCHWALL="$HOME/.config/quickshell/ii/scripts/colors/switchwall.sh"

log() {
    echo "[wallpaper-wrapper] $1"
}

is_image_file() {
    local file="$1"
    local ext="${file##*.}"
    ext="${ext,,}"
    
    case "$ext" in
        jpg|jpeg|png|webp|bmp|tiff|tif|gif)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_video_file() {
    local file="$1"
    local ext="${file##*.}"
    ext="${ext,,}"
    
    case "$ext" in
        mp4|webm|mkv|avi|mov)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

optimize_if_needed() {
    local imgpath="$1"
    
    if is_video_file "$imgpath"; then
        log "Video detected, skipping optimization"
        echo "$imgpath"
        return 0
    fi
    
    if ! is_image_file "$imgpath"; then
        echo "$imgpath"
        return 0
    fi
    
    if [[ ! -f "$imgpath" ]]; then
        echo "$imgpath"
        return 1
    fi
    
    log "Optimizing: $(basename "$imgpath")"
    
    local optimized
    optimized=$("$OPTIMIZER" -i "$imgpath" 2>&1)
    
    if [[ -f "$optimized" ]]; then
        log "Optimized successfully"
        echo "$optimized"
        return 0
    else
        log "Optimization failed, using original"
        echo "$imgpath"
        return 1
    fi
}

main() {
    local args=()
    local imgpath=""
    local imgpath_index=-1
    
    for ((i=1; i<=$#; i++)); do
        local arg="${!i}"
        case "$arg" in
            --image)
                imgpath_index=$((i+1))
                args+=("$arg")
                ;;
            *)
                if [[ $imgpath_index -eq $i ]]; then
                    imgpath="$arg"
                    args+=("$arg")
                elif [[ -z "$imgpath" && -f "$arg" && $imgpath_index -eq -1 ]]; then
                    imgpath="$arg"
                    args+=("$arg")
                else
                    args+=("$arg")
                fi
                ;;
        esac
    done
    
    if [[ -n "$imgpath" && -f "$imgpath" ]]; then
        local optimized_path
        optimized_path=$(optimize_if_needed "$imgpath")
        
        for ((i=0; i<${#args[@]}; i++)); do
            if [[ "${args[$i]}" == "$imgpath" ]]; then
                args[$i]="$optimized_path"
                break
            fi
        done
    fi
    
    "$ORIGINAL_SWITCHWALL" "${args[@]}"
}

main "$@"
