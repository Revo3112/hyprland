#!/bin/bash
# Dynamic Lock Script - Reads useHyprlock setting from config.json
# Used by hypridle to ensure lock system follows Quickshell settings

CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    pidof hyprlock || hyprlock
    exit 0
fi

# Read useHyprlock setting from config.json
# Note: we use explicit null check because // operator treats false as null
USE_HYPRLOCK=$(jq -r '.lock.useHyprlock | if . == null then true else . end' "$CONFIG_FILE")

if [[ "$USE_HYPRLOCK" == "true" ]]; then
    # Use Hyprlock
    pidof hyprlock || hyprlock
else
    # Use Quickshell lock via GlobalShortcut
    hyprctl dispatch global quickshell:lock
fi
