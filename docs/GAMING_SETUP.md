# 🎮 Ryzen APU Gaming Setup for Linux

> Last updated: 2026-02-07
> 
> **Purpose:** Complete guide for optimizing gaming on Linux with AMD Ryzen APU (integrated graphics). Works on Arch Linux, Hyprland, and similar setups. Can be used as reference by AI assistants for Ryzen APU optimization.

---

## 🚀 Quick Start Guide (TL;DR)

### For Any Ryzen APU System

**1. Install Required Packages:**
```bash
# Arch Linux
sudo pacman -S gamemode lib32-gamemode mangohud lib32-mangohud vulkan-radeon lib32-vulkan-radeon power-profiles-daemon
paru -S protonup-qt ryzenadj

# Fedora/Nobara
sudo dnf install gamemode mangohud vulkan-loader ryzenadj
```

**2. Setup Hardware TDP Control:**
```bash
# Copy ryzenadj-profile script
cp ~/.config/hypr/scripts/ryzenadj-profile /usr/local/bin/
chmod +x /usr/local/bin/ryzenadj-profile

# Setup passwordless sudo for TDP changes
echo "$USER ALL=(root) NOPASSWD: /usr/local/bin/ryzenadj-profile" | sudo tee /etc/sudoers.d/99-ryzenadj-profile
sudo chmod 440 /etc/sudoers.d/99-ryzenadj-profile
```

**3. Steam Game Setup:**
- Right-click game → Properties
- Compatibility → Force → **GE-Proton** (latest)
- Launch Options: `gamemoderun mangohud %command%`
- In-game resolution: Lower than native for 60 FPS

**4. Enable FSR Upscaling:**
```bash
# Add to your environment config
export WINE_FULLSCREEN_FSR=1
```

---

## 📊 Hardware TDP Profiles

### ryzenadj-profile Script

Location: `~/.config/hypr/scripts/ryzenadj-profile`

| Profile | STAPM | Fast | Slow | Temp Limit | VRM | Use Case |
|---------|-------|------|------|------------|-----|----------|
| **power-saver** | 15W | 18W | 15W | 100°C | 60A | Battery life, light tasks |
| **balanced** | 28W | 35W | 28W | 100°C | 90A | Normal use, light gaming |
| **performance** | 45W | 54W | 45W | 100°C | 120A | Gaming, heavy workloads |

### Usage
```bash
# Apply performance profile
sudo ryzenadj-profile performance

# Apply balanced profile
sudo ryzenadj-profile balanced

# Apply power saver profile
sudo ryzenadj-profile power-saver

# Check current profile
ryzenadj-profile current

# Show hardware status (requires sudo)
sudo ryzenadj-profile status
```

### Customizing for Your APU

Edit `~/.config/hypr/scripts/ryzenadj-profile` and adjust values based on your APU:

| APU | Recommended STAPM | Max Fast | Notes |
|-----|-------------------|----------|-------|
| Ryzen 5 6600H | 45W | 54W | Default in script |
| Ryzen 7 6800H | 45-54W | 65W | Higher TDP capable |
| Ryzen 5 7535HS | 35-45W | 54W | Efficient variant |
| Ryzen 7 7840HS | 45-54W | 65W | Phoenix, very capable |
| Ryzen Z1 Extreme | 25-30W | 35W | Handheld optimized |

---

## 🎯 Quickshell Integration

### Game Mode Toggle
Location: `~/.config/quickshell/ii/modules/common/models/quickToggles/GameModeToggle.qml`

**When ENABLED:**
- ✅ Hyprland visual optimizations (no blur, shadows, animations)
- ✅ Feral GameMode (CPU governor → performance)
- ✅ Power Profile → Performance
- ✅ **ryzenadj → 45W TDP** (hardware unlock)
- ✅ Idle inhibitor (no screen sleep)
- ✅ Notification: "Game Mode ON"

**When DISABLED:**
- ✅ Restore Hyprland config
- ✅ Deactivate Feral GameMode
- ✅ Restore previous Power Profile
- ✅ **ryzenadj → restore previous TDP**
- ✅ Release idle inhibitor
- ✅ Notification: "Game Mode OFF"

### Power Profile Toggle
Location: `~/.config/quickshell/ii/modules/common/models/quickToggles/PowerProfilesToggle.qml`

**Cycle: Power Saver → Balanced → Performance → Power Saver**

Each profile change:
- ✅ Updates kernel power profile (powerprofilesctl)
- ✅ **Updates hardware TDP (ryzenadj)**
- ✅ Shows notification with current TDP
- ✅ Warns if Game Mode is active

### Conflict Prevention

The toggles are designed to work together:
- **Game Mode** saves your current Power Profile and restores it when disabled
- **Power Profile** warns you if Game Mode is active and you try to lower power
- Both show notifications so you always know the current state

---

## 🔧 Installation Files

### 1. ryzenadj-profile Script

```bash
#!/bin/bash
# ryzenadj-profile - Hardware TDP management for Ryzen APU
# Location: ~/.config/hypr/scripts/ryzenadj-profile

set -euo pipefail

PROFILE="${1:-}"
RYZENADJ="/usr/bin/ryzenadj"

if [[ ! -x "$RYZENADJ" ]]; then
    echo "Error: ryzenadj not found at $RYZENADJ" >&2
    exit 1
fi

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This command requires sudo" >&2
        exit 1
    fi
}

apply_power_saver() {
    require_root
    "$RYZENADJ" \
        --stapm-limit=15000 \
        --fast-limit=18000 \
        --slow-limit=15000 \
        --tctl-temp=100 \
        --vrm-current=60000 \
        --vrmmax-current=60000 \
        2>/dev/null
    echo "power-saver" > /tmp/.ryzenadj_current_profile
    echo "Applied: Power Saver (15W STAPM)"
}

apply_balanced() {
    require_root
    "$RYZENADJ" \
        --stapm-limit=28000 \
        --fast-limit=35000 \
        --slow-limit=28000 \
        --tctl-temp=100 \
        --vrm-current=90000 \
        --vrmmax-current=90000 \
        2>/dev/null
    echo "balanced" > /tmp/.ryzenadj_current_profile
    echo "Applied: Balanced (28W STAPM)"
}

apply_performance() {
    require_root
    "$RYZENADJ" \
        --stapm-limit=45000 \
        --fast-limit=54000 \
        --slow-limit=45000 \
        --tctl-temp=100 \
        --vrm-current=120000 \
        --vrmmax-current=120000 \
        2>/dev/null
    echo "performance" > /tmp/.ryzenadj_current_profile
    echo "Applied: Performance (45W STAPM - FULL POWER)"
}

get_current() {
    if [[ -f /tmp/.ryzenadj_current_profile ]]; then
        cat /tmp/.ryzenadj_current_profile
    else
        echo "unknown"
    fi
}

show_status() {
    require_root
    echo "=== Current Profile: $(get_current) ==="
    "$RYZENADJ" -i 2>/dev/null | grep -E "(STAPM|PPT|THM|Temperature)" || true
}

case "$PROFILE" in
    power-saver|powersaver|saver) apply_power_saver ;;
    balanced|balance|default) apply_balanced ;;
    performance|perf|gaming|game) apply_performance ;;
    status) show_status ;;
    current) get_current ;;
    *) echo "Usage: $0 <power-saver|balanced|performance|status|current>" ;;
esac
```

### 2. Sudoers Configuration

```bash
# File: /etc/sudoers.d/99-ryzenadj-profile
# Allow user to run ryzenadj-profile without password

YOUR_USERNAME ALL=(root) NOPASSWD: /home/YOUR_USERNAME/.config/hypr/scripts/ryzenadj-profile
YOUR_USERNAME ALL=(root) NOPASSWD: /usr/bin/ryzenadj
```

---

## 🖥️ Hardware Reference

### Tested Configuration (Advan Workplus)

| Component | Detail |
|-----------|--------|
| **CPU** | AMD Ryzen 5 6600H (6C/12T, Zen 3+) |
| **GPU** | AMD Radeon 660M (6 CU, RDNA2) |
| **GPU Max Clock** | 1899 MHz |
| **Default TDP** | 15-28W (BIOS limited) |
| **Unlocked TDP** | 45W STAPM, 54W Fast |

### Performance Results

| Resolution | TDP | FPS | Notes |
|------------|-----|-----|-------|
| 1080p | 28W | 25-30 | Too demanding |
| 1080p | 45W | 35-40 | Playable |
| **960p** | **45W** | **60** ✅ | **Sweet spot** |
| 720p | 45W | 60+ | Extra headroom |

---

## 🌍 Environment Variables

Add to `~/.config/hypr/custom/env.conf` or `~/.profile`:

```bash
# AMD Vulkan Driver (use RADV)
export AMD_VULKAN_ICD=RADV

# RADV Performance
export RADV_PERFTEST=gpl

# VKD3D (DirectX 12 translation)
export VKD3D_CONFIG=dxr

# DXVK Async Shader Compilation
export DXVK_ASYNC=1

# FSR for Wine/Proton
export WINE_FULLSCREEN_FSR=1
export WINE_FULLSCREEN_FSR_STRENGTH=2

# Disable NVIDIA stuff
export PROTON_ENABLE_NVAPI=0
```

---

## 🎮 Steam Configuration

### Launch Options
```
gamemoderun mangohud %command%
```

### Proton Selection
1. Install **ProtonUp-Qt**: `paru -S protonup-qt`
2. Download latest **GE-Proton**
3. Right-click game → Properties → Compatibility
4. Force: **GE-Proton** (latest version)

### Per-Game Settings
For demanding games, add resolution override:
```
gamemoderun mangohud WINE_FULLSCREEN_FSR=1 %command% -w 1704 -h 960
```

---

## 🔋 Battery vs Gaming Mode

### For Battery Life (Not Gaming)
```bash
# Apply power saver
sudo ryzenadj-profile power-saver

# Or use Power Profile toggle (cycle to Power Saver)
```

### For Gaming
```bash
# Enable Game Mode toggle in Quickshell
# OR manually:
sudo ryzenadj-profile performance
powerprofilesctl set performance
```

### Auto-Switch on AC/Battery (Optional)

Create `/etc/udev/rules.d/99-power-switch.rules`:
```
# On AC power → balanced
ACTION=="change", SUBSYSTEM=="power_supply", ATTR{online}=="1", RUN+="/home/YOUR_USER/.config/hypr/scripts/ryzenadj-profile balanced"

# On battery → power-saver
ACTION=="change", SUBSYSTEM=="power_supply", ATTR{online}=="0", RUN+="/home/YOUR_USER/.config/hypr/scripts/ryzenadj-profile power-saver"
```

---

## ❓ Troubleshooting

### "Unable to get memory access" Error
This is **normal** if `ryzen_smu` kernel module is not installed. Settings still apply correctly. To fix:
```bash
paru -S ryzen_smu-dkms-git
```

### TDP Not Applying
1. Check ryzenadj is installed: `which ryzenadj`
2. Check sudo works: `sudo ryzenadj-profile performance`
3. Check output for "Sucessfully set..."

### Game Mode Toggle Stuck
```bash
# Manually reset
rm -f /tmp/.qs_gamemode_active
rm -f /tmp/.qs_gamemode_inhibit_pid
hyprctl reload
```

### Low FPS Despite High TDP
- Check GPU clock: `cat /sys/class/drm/card*/device/pp_dpm_sclk`
- Check VRAM usage (Radeon 660M only has 2GB)
- Lower in-game resolution and use FSR

---

## 📝 Useful Commands

```bash
# Check current TDP profile
ryzenadj-profile current

# Check power profile
powerprofilesctl get

# Check GameMode status
gamemoded --status

# Check GPU clocks
cat /sys/class/drm/card*/device/pp_dpm_sclk

# Check GPU power
cat /sys/class/hwmon/hwmon*/power1_input  # in microwatts

# Check CPU temperature
sensors | grep -i temp

# Check idle inhibitors
systemd-inhibit --list
```

---

## 📚 References

- [ryzenadj GitHub](https://github.com/FlyGoat/RyzenAdj)
- [Feral GameMode](https://github.com/FeralInteractive/gamemode)
- [Arch Wiki - Gaming](https://wiki.archlinux.org/title/Gaming)
- [ProtonDB](https://www.protondb.com/)
- [GE-Proton](https://github.com/GloriousEggroll/proton-ge-custom)