# AGENTS.md - Hyprland Configuration Guidelines

## Project Overview

This is a **Hyprland (Wayland compositor) configuration** based on end-4/dots-hyprland. It's a Linux desktop environment configuration, not a traditional code project. The configuration is modular, separating upstream defaults from user customizations.

## Configuration Validation & Testing

### Reload Configuration
```bash
hyprctl reload
```

### Validate Hyprland Config Syntax
```bash
hyprctl reload 2>&1 | head -50
```

### Check Monitor Status
```bash
hyprctl monitors all
```

### Validate Shell Scripts
```bash
bash -n path/to/script.sh
shellcheck path/to/script.sh  # If shellcheck is installed
```

### Test Single Keybind/Binding
```bash
hyprctl dispatch <dispatcher> <args>
hyprctl keyword <keyword> <value>
```

## Directory Structure & File Organization

```
~/.config/hypr/
├── hyprland.conf          # Entry point - sources other files
├── hyprland/              # UPSTREAM CORE - DO NOT MODIFY
│   ├── env.conf          # Environment variables
│   ├── execs.conf        # Core startup apps
│   ├── general.conf      # Animations, blur, gestures
│   ├── keybinds.conf     # Default keybinds
│   ├── rules.conf        # Window/layer rules
│   ├── colors.conf       # Theme (auto-generated)
│   └── scripts/          # Upstream helper scripts
├── custom/                # USER CUSTOMIZATIONS - SAFE TO MODIFY
│   ├── env.conf          # Custom env vars
│   ├── execs.conf        # Custom startup apps
│   ├── general.conf      # Custom general settings
│   ├── keybinds.conf     # Custom keybinds
│   ├── rules.conf        # Custom window rules
│   └── scripts/          # Custom user scripts
├── scripts/               # Dynamic lock/gaming scripts
├── monitors.conf          # HyprDynamicMonitors managed
├── workspaces.conf        # nwg-displays managed
├── hyprlock.conf          # Lock screen config
└── hypridle.conf          # Idle management config
```

### CRITICAL RULE: File Modification Safety
- **NEVER** modify files in `hyprland/` directory - they are upstream and will be overwritten
- **ALWAYS** put user modifications in `custom/` directory
- Files in `custom/` override/supplement files in `hyprland/`

## Hyprland Configuration Syntax

### Variable Definitions
```ini
$variable = value
$qsConfig = ii
```

### Environment Variables
```ini
env = VARIABLE_NAME,value
env = QT_QPA_PLATFORM,wayland
```

### Keybindings
```ini
bind = MOD, key, dispatcher, arg
bind = Super, Q, killactive,
bindd = Super, V, Description, dispatcher, arg  # With description for cheatsheet
bindl = , XF86AudioMute, exec, command           # No mod
binde = Super, Equal, exec, command              # On release
bindm = Super, mouse:272, movewindow             # Mouse bind
```

### Window Rules
```ini
windowrule = property on, match:class ^(appname)$
windowrule = float on, match:title ^(Open File)(.*)$
windowrule = size (monitor_w*.60) (monitor_h*.65), match:class ^(pavucontrol)$
```

### Layer Rules
```ini
layerrule = property layername
layerrule = blur gtk-layer-shell
layerrule = no_anim quickshell:overview
```

### Monitor Configuration
```ini
monitor=NAME,RESOLUTION@REFRESH,POSITION,SCALE
monitor=eDP-1,1920x1200@60,0x0,1
monitor=HDMI-A-1,preferred,auto,1,mirror,eDP-1
```

## Shell Script Conventions

### Script Header
```bash
#!/usr/bin/env bash
set -euo pipefail
```

### Logging Pattern
```bash
echo "[script-name] Message"
echo "[script-name] ERROR: $1" >&2
```

### Notify User
```bash
notify-send -u "normal" -t 5000 "Title" "Message"
```

### Error Handling
```bash
die() {
    notify-send -u "critical" "Error" "$1"
    echo "[script] ERROR: $1" >&2
    exit 1
}

[[ -f "$file" ]] || die "File not found: $file"
```

### Hyprctl IPC
```bash
hyprctl dispatch <dispatcher> <args>
hyprctl keyword <keyword> <value>
hyprctl monitors -j | jq -r '.[] | .name'
hyprctl activeworkspace -j | jq -r '.id'
```

### Quickshell IPC
```bash
qs -c $qsConfig ipc call <method>
qs -c $qsConfig ipc call TEST_ALIVE
hyprctl dispatch global quickshell:lock
```

### Conditional Fallback Pattern
```bash
# Try Quickshell first, fallback to standalone tool
qs -c $qsConfig ipc call TEST_ALIVE || command || fallback
qs -c $qsConfig ipc call TEST_ALIVE || pkill fuzzel || fuzzel
```

### App Launcher Pattern
```bash
#!/usr/bin/env bash
for cmd in "$@"; do
    [[ -z "$cmd" ]] && continue
    eval "command -v ${cmd%% *}" >/dev/null 2>&1 || continue
    eval "$cmd" &
    exit
done
```

## Naming Conventions

### Files
- Config files: `*.conf` (lowercase)
- Scripts: `*.sh` or executable without extension
- Documentation: `UPPERCASE.md` or `Title-Case.md`

### Config Variables
- Hyprland variables: `$camelCase` (`$qsConfig`, `$lock_cmd`)
- Theme variables: `$snake_case` (`$text_color`, `$font_family`)

### Script Naming
- `snake_case.sh` for utility scripts
- `kebab-case.sh` for user-facing scripts

### Keybind Comments
```ini
bind = Super, Q, killactive, # Close
bindd = Super, V, Clipboard history, exec, command # Description for cheatsheet
bind = Super, Q, killactive, # [hidden]  # Don't show on cheatsheet
```

## Common Patterns

### Dynamic Configuration Reading
```bash
CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
USE_HYPRLOCK=$(jq -r '.lock.useHyprlock // true' "$CONFIG_FILE")
```

### Safe Monitor Switching
```bash
# Stop portal before switching
systemctl --user stop xdg-desktop-portal-hyprland.service
# Apply monitor changes
hyprctl keyword monitor "$value"
# Restart portal
systemctl --user start xdg-desktop-portal.service
```

### Cheatsheet Sections
```ini
#! Column marker
##! Section header
```

## Dependencies

- `hyprland` - Window manager
- `hypridle` - Idle management
- `hyprlock` - Lock screen
- `quickshell` - Desktop shell
- `jq` - JSON parsing
- `notify-send` - Notifications
- `hyprctl` - Hyprland IPC

## Quick Reference

| Task | Command |
|------|---------|
| Reload config | `hyprctl reload` |
| Check monitors | `hyprctl monitors all` |
| Check active workspace | `hyprctl activeworkspace -j` |
| Dispatch command | `hyprctl dispatch <cmd>` |
| Set keyword | `hyprctl keyword <key> <val>` |
| List plugins | `hyprctl plugin list` |
| Test keybind | Direct from terminal |

## Notes

- Quickshell uses `$qsConfig = ii` (Illogical Impulse config)
- Lock system is dynamic - reads from `~/.config/illogical-impulse/config.json`
- Monitor config is managed by HyprDynamicMonitors daemon
- Colors are auto-generated by matugen from wallpaper