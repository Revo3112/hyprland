#!/bin/bash
# Check if Caps Lock is on and display warning

# Find any capslock LED that is on
for led in /sys/class/leds/*::capslock/brightness; do
    if [[ -f "$led" ]] && [[ "$(cat "$led")" == "1" ]]; then
        echo "⚠️ Caps Lock ON"
        exit 0
    fi
done

# Caps Lock is off - output nothing
echo ""
