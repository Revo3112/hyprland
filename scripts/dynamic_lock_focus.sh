#!/bin/bash
# Dynamic Lock Focus Script - Reads useHyprlock setting from config.json
# Used by hypridle after_sleep_cmd

CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    hyprctl dispatch dpms on
    exit 0
fi

# Read useHyprlock setting from config.json
USE_HYPRLOCK=$(jq -r '.lock.useHyprlock | if . == null then true else . end' "$CONFIG_FILE")

if [[ "$USE_HYPRLOCK" == "true" ]]; then
    # Hyprlock mode - just turn on display
    hyprctl dispatch dpms on
else
    # Quickshell mode - refocus lock screen
    qs -c ii ipc call lock focus
fi
