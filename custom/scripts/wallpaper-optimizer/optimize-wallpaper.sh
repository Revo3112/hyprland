#!/usr/bin/env bash
#
# Wallpaper Optimizer for Qt Quick (Quickshell)
# - Converts color profile to sRGB for correct display
# - Pre-scales wallpaper to optimal size (3x monitor resolution)
# - Smart caching with auto-cleanup
#
# NOTE: Requires QT_IMAGEIO_MAXALLOC to be set for large images (8K+)
# See: ~/.config/hypr/hyprland/env.conf
#

set -euo pipefail

XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
CACHE_DIR="$XDG_CACHE_HOME/hypr/wallpaper-optimizer"
PROCESSED_DIR="$CACHE_DIR/processed"
MAX_CACHE_FILES=20
MAX_BACKUP_FILES=5

# Optimal scale factor: 4x monitor resolution for parallax quality
# This reduces extreme downscaling (e.g., 11K→1920 = 5.7x) to manageable (7680→1920 = 4x)
OPTIMAL_SCALE_FACTOR=4
# Max downscaling ratio before we pre-scale (if >3x, we resize)
MAX_DOWNSCALE_RATIO=3.0

mkdir -p "$PROCESSED_DIR"

log() {
    echo "[wallpaper-optimizer] $1"
}

error() {
    echo "[wallpaper-optimizer] ERROR: $1" >&2
}

cleanup_old_cache() {
    local count
    count=$(find "$PROCESSED_DIR" -type f 2>/dev/null | wc -l)
    
    if [[ $count -gt $MAX_CACHE_FILES ]]; then
        local to_delete=$((count - MAX_CACHE_FILES))
        find "$PROCESSED_DIR" -type f -printf '%T@ %p\n' 2>/dev/null | \
            sort -n | head -n "$to_delete" | cut -d' ' -f2- | \
            xargs rm -f 2>/dev/null || true
    fi
}

cleanup_old_backups() {
    local backup_dir="$CACHE_DIR/backups"
    if [[ -d "$backup_dir" ]]; then
        local count
        count=$(find "$backup_dir" -name "*.backup.*" -type f 2>/dev/null | wc -l)
        
        if [[ $count -gt $MAX_BACKUP_FILES ]]; then
            local to_delete=$((count - MAX_BACKUP_FILES))
            find "$backup_dir" -name "*.backup.*" -type f -printf '%T@ %p\n' 2>/dev/null | \
                sort -n | head -n "$to_delete" | cut -d' ' -f2- | \
                xargs rm -f 2>/dev/null || true
        fi
    fi
}

get_image_info() {
    identify -verbose "$1" 2>/dev/null
}

has_color_profile() {
    local img="$1"
    if get_image_info "$img" | grep -qi "icc\|color profile\|profile:"; then
        return 0
    fi
    return 1
}

get_colorspace() {
    local img="$1"
    local colorspace
    colorspace=$(get_image_info "$img" | grep -i "Colorspace:" | head -1 | awk '{print $2}')
    echo "${colorspace:-sRGB}"
}

get_bit_depth() {
    local img="$1"
    local depth
    depth=$(get_image_info "$img" | grep -i "Depth:" | head -1 | awk '{print $2}')
    echo "${depth:-8-bit}"
}

get_image_resolution() {
    identify -format "%wx%h" "$1" 2>/dev/null
}

get_image_format() {
    identify -format "%m" "$1" 2>/dev/null
}

get_monitor_resolution() {
    # Get max monitor resolution using hyprctl
    local max_width max_height
    max_width=$(hyprctl monitors -j 2>/dev/null | jq '([.[].width] | max)' 2>/dev/null || echo "1920")
    max_height=$(hyprctl monitors -j 2>/dev/null | jq '([.[].height] | max)' 2>/dev/null || echo "1080")
    echo "${max_width}x${max_height}"
}

calculate_optimal_size() {
    local img_width="$1"
    local img_height="$2"
    local mon_width="$3"
    local mon_height="$4"
    
    # Calculate downscale ratio
    local ratio_width ratio_height max_ratio
    ratio_width=$(echo "scale=2; $img_width / $mon_width" | bc)
    ratio_height=$(echo "scale=2; $img_height / $mon_height" | bc)
    
    if (( $(echo "$ratio_width > $ratio_height" | bc -l) )); then
        max_ratio="$ratio_width"
    else
        max_ratio="$ratio_height"
    fi
    
    echo "$max_ratio"
}

get_optimal_dimensions() {
    local img_width="$1"
    local img_height="$2"
    local mon_width="$3"
    local mon_height="$4"
    
    # Target: OPTIMAL_SCALE_FACTOR x monitor resolution
    local target_width=$((mon_width * OPTIMAL_SCALE_FACTOR))
    local target_height=$((mon_height * OPTIMAL_SCALE_FACTOR))
    
    # Calculate scale to fit within target while preserving aspect ratio
    local scale_width scale_height scale
    scale_width=$(echo "scale=4; $target_width / $img_width" | bc)
    scale_height=$(echo "scale=4; $target_height / $img_height" | bc)
    
    # Use the smaller scale to fit within bounds
    if (( $(echo "$scale_width < $scale_height" | bc -l) )); then
        scale="$scale_width"
    else
        scale="$scale_height"
    fi
    
    # Only downscale, never upscale
    if (( $(echo "$scale >= 1.0" | bc -l) )); then
        echo "${img_width}x${img_height}"
        return
    fi
    
    local new_width new_height
    new_width=$(echo "$img_width * $scale / 1" | bc)
    new_height=$(echo "$img_height * $scale / 1" | bc)
    
    echo "${new_width}x${new_height}"
}

is_hdr() {
    local img="$1"
    local depth
    depth=$(get_bit_depth "$img")
    if [[ "$depth" == *"16"* ]] || [[ "$depth" == *"32"* ]]; then
        return 0
    fi
    
    if get_image_info "$img" | grep -qi "hdr\|pq\|hlg\|scRGB"; then
        return 0
    fi
    
    return 1
}

process_wallpaper() {
    local input="$1"
    local output="$2"
    
    if [[ ! -f "$input" ]]; then
        error "Input file not found: $input"
        return 1
    fi
    
    local filename
    filename=$(basename "$input")
    
    local resolution colorspace depth format
    resolution=$(get_image_resolution "$input")
    colorspace=$(get_colorspace "$input")
    depth=$(get_bit_depth "$input")
    format=$(get_image_format "$input")
    
    # Get monitor resolution
    local monitor_res mon_width mon_height
    monitor_res=$(get_monitor_resolution)
    mon_width=$(echo "$monitor_res" | cut -d'x' -f1)
    mon_height=$(echo "$monitor_res" | cut -d'x' -f2)
    
    # Get image dimensions
    local img_width img_height
    img_width=$(echo "$resolution" | cut -d'x' -f1)
    img_height=$(echo "$resolution" | cut -d'x' -f2)
    
    # Calculate downscale ratio
    local downscale_ratio
    downscale_ratio=$(calculate_optimal_size "$img_width" "$img_height" "$mon_width" "$mon_height")
    
    # Determine if we need to pre-scale
    local needs_resizing="no"
    local optimal_dims="${img_width}x${img_height}"
    
    if (( $(echo "$downscale_ratio > $MAX_DOWNSCALE_RATIO" | bc -l) )); then
        needs_resizing="yes"
        optimal_dims=$(get_optimal_dimensions "$img_width" "$img_height" "$mon_width" "$mon_height")
        log "Pre-scaling enabled: ${resolution} → ${optimal_dims} (ratio: ${downscale_ratio}x → ~3x)"
    fi
    
    log "Processing: $filename"
    log "  Resolution: $resolution"
    log "  Monitor: ${mon_width}x${mon_height}"
    log "  Downscale ratio: ${downscale_ratio}x"
    log "  Pre-scale: $needs_resizing"
    log "  Colorspace: $colorspace"
    log "  Bit depth: $depth"
    
    local has_profile="no"
    if has_color_profile "$input"; then
        has_profile="yes"
        log "  ICC Profile: detected"
    fi
    
    local is_hdr_img="no"
    if is_hdr "$input"; then
        is_hdr_img="yes"
        log "  HDR: detected (will be tone-mapped)"
    fi
    
    local needs_processing="no"
    if [[ "$is_hdr_img" == "yes" || "$has_profile" == "yes" || "$colorspace" != "sRGB" || "$needs_resizing" == "yes" ]]; then
        needs_processing="yes"
    fi
    
    if [[ "$needs_processing" == "no" ]]; then
        log "  Image optimal, copying..."
        cp "$input" "$output"
        log "  Output: $output"
        log "  Done!"
        return 0
    fi
    
    log "  Processing image..."
    
    local temp_output="${output}.tmp.$$"
    local magick_opts=""
    
    # Build ImageMagick command
    magick_opts="$input"
    
    # SAFE PROCESSING: Build ImageMagick command array (avoid eval issues)
    local magick_cmd=("$input")
    
    # Add resize if needed (use Mitchell filter for safe, high-quality downscaling)
    # Mitchell filter is safer than RobidouxSharp and avoids color artifacts
    if [[ "$needs_resizing" == "yes" ]]; then
        log "  Resizing to optimal dimensions: $optimal_dims..."
        log "  Using Mitchell filter (safe, artifact-free)..."
        magick_cmd+=("-filter" "Mitchell")
        magick_cmd+=("-resize" "${optimal_dims}")
        # Preserve exact pixel values
        magick_cmd+=("+dither")
    fi
    
    # HATI-HATI: Colorspace conversion bisa menyebabkan magenta/corruption
    # Hanya lakukan jika benar-benar diperlukan (bukan sRGB dan bukan PNG dengan alpha)
    if [[ "$is_hdr_img" == "yes" ]]; then
        log "  Processing HDR image..."
        magick_cmd+=("-colorspace" "sRGB")
        magick_cmd+=("-auto-level")
    elif [[ "$has_profile" == "yes" && "$colorspace" != "sRGB" ]]; then
        # Hanya convert colorspace jika ada ICC profile dan bukan sRGB
        log "  Converting colorspace with ICC profile..."
        magick_cmd+=("-colorspace" "sRGB")
        magick_cmd+=("-intent" "relative")
    fi
    
    # Add quality settings (preserve transparency)
    magick_cmd+=("-quality" "100")
    magick_cmd+=("-define" "png:compression-level=3")
    magick_cmd+=("-define" "png:format=png32")  # Force 32-bit PNG to preserve alpha
    
    # Execute ImageMagick command safely
    magick "${magick_cmd[@]}" "$temp_output"
    
    # Validate output file
    if [[ -f "$temp_output" && -s "$temp_output" ]]; then
        # Validasi: cek apakah file corrupt (size terlalu kecil atau tidak bisa di-identify)
        local output_res
        output_res=$(identify -format "%wx%h" "$temp_output" 2>/dev/null)
        if [[ -z "$output_res" ]]; then
            error "  Output file corrupt (cannot identify), using original"
            rm -f "$temp_output"
            cp "$input" "$output"
        else
            mv "$temp_output" "$output"
            log "  Output: $output"
            log "  New resolution: $output_res"
            log "  Done!"
            save_cache_mapping "$output" "$input"
        fi
        cleanup_old_cache
        return 0
    else
        error "  Failed to create output file, using original"
        cp "$input" "$output"
        return 0
    fi
}

get_cache_path() {
    local input="$1"
    local hash
    hash=$(md5sum "$input" | awk '{print $1}')
    local ext="${input##*.}"
    echo "$PROCESSED_DIR/${hash}.${ext}"
}

save_cache_mapping() {
    local cache_file="$1"
    local original="$2"
    local cache_name
    cache_name=$(basename "$cache_file")
    local map_file="$CACHE_DIR/cache_map.txt"
    
    mkdir -p "$CACHE_DIR"
    
    grep -v "^$cache_name" "$map_file" 2>/dev/null > "${map_file}.tmp" || true
    echo -e "${cache_name}\t${original}" >> "${map_file}.tmp"
    mv "${map_file}.tmp" "$map_file" 2>/dev/null || true
}

optimize_and_cache() {
    local input="$1"
    local cached
    cached=$(get_cache_path "$input")
    
    if [[ -f "$cached" ]]; then
        local input_mtime cached_mtime
        input_mtime=$(stat -c %Y "$input")
        cached_mtime=$(stat -c %Y "$cached" 2>/dev/null || echo "0")
        
        if [[ "$input_mtime" -le "$cached_mtime" ]]; then
            log "Using cached: $cached"
            echo "$cached"
            return 0
        fi
    fi
    
    log "Processing new file..."
    if process_wallpaper "$input" "$cached"; then
        echo "$cached"
        return 0
    fi
    
    echo "$input"
    return 1
}

main() {
    local input=""
    local output=""
    local force="no"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--input)
                input="$2"
                shift 2
                ;;
            -o|--output)
                output="$2"
                shift 2
                ;;
            -f|--force)
                force="yes"
                shift
                ;;
            --cleanup)
                cleanup_old_cache
                cleanup_old_backups
                log "Cleanup completed"
                return 0
                ;;
            -h|--help)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  -i, --input FILE    Input wallpaper file"
                echo "  -o, --output FILE   Output file (default: cached location)"
                echo "  -f, --force         Force reprocessing"
                echo "  --cleanup           Clean old cache and backups"
                echo "  -h, --help          Show this help"
                echo ""
                echo "NOTE: QT_IMAGEIO_MAXALLOC must be set for images > 256 MB"
                echo "      Set in ~/.config/hypr/hyprland/env.conf"
                return 0
                ;;
            *)
                if [[ -z "$input" ]]; then
                    input="$1"
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$input" ]]; then
        error "No input file specified"
        return 1
    fi
    
    cleanup_old_backups
    
    if [[ -z "$output" ]]; then
        if [[ "$force" == "yes" ]]; then
            local cached
            cached=$(get_cache_path "$input")
            rm -f "$cached" 2>/dev/null || true
        fi
        optimize_and_cache "$input"
    else
        process_wallpaper "$input" "$output"
    fi
}

main "$@"