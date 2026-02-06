# 🎮 Advan Workplus Gaming Setup

> Last updated: 2026-01-05
> 
> **Purpose:** This document serves as a complete guide for optimizing gaming on Arch Linux with AMD APU (integrated graphics). Can be used as reference by AI assistants for similar hardware optimization requests.

---

## 🚀 Quick Start Guide (TL;DR)

### For AI Assistants / New Setup

**1. Install Required Packages:**
```bash
sudo pacman -S gamemode lib32-gamemode mangohud lib32-mangohud gamescope vulkan-radeon lib32-vulkan-radeon
yay -S protonup-qt
```

**2. Download Proton-GE:**
```bash
python -m pupgui2  # GUI to download GE-Proton
```

**3. Steam Game Setup:**
- Right-click game → Properties
- Compatibility → Force → **GE-Proton10-28**
- Launch Options: `gamemoderun mangohud %command%`
- In-game resolution: **960p** (for 60 FPS on Radeon 660M)

**4. Enable FSR Upscaling (960p → 1080p):**
Add to `~/.config/hypr/custom/env.conf`:
```conf
env = WINE_FULLSCREEN_FSR, 1
```

**5. Key Files:**
- Game Mode Toggle: `~/.config/quickshell/ii/modules/common/models/quickToggles/GameModeToggle.qml`
- Environment Variables: `~/.config/hypr/custom/env.conf`
- Feral GameMode: `/etc/gamemode.ini`

### Performance Results (Tested on Radeon 660M)

| Resolution | FPS | FSR Upscale |
|------------|-----|-------------|
| **960p** | **60 FPS** ✅ | → 1080p |
| 720p | 60+ FPS | → 1080p |
| 1080p | 25-30 FPS ❌ | No upscale needed |

### Known Issues
- ⚠️ **Gamescope**: Black screen on this laptop - use `gamemoderun mangohud` instead
- ⚠️ **allow_tearing / misc:vfr**: Causes screen blink with Steam notifications - removed from toggle

---

## Hardware Specs

| Component | Detail |
|-----------|--------|
| **Laptop** | Advan Workplus (Model: 1701) |
| **CPU** | AMD Ryzen 5 6600H (6C/12T, Zen 3+) |
| **CPU TDP** | 45W |
| **CPU Max Boost** | 4.57 GHz |
| **GPU** | AMD Radeon 660M (6 CU, RDNA2) |
| **GPU Base Clock** | 1500 MHz |
| **GPU Max Boost** | 1899 MHz |
| **Driver** | RADV (Mesa Vulkan) |

---

## Game Mode Toggle (Quickshell)

Location: `~/.config/quickshell/ii/modules/common/models/quickToggles/GameModeToggle.qml`

### What it does when ENABLED:

#### Hyprland Optimizations
- `animations:enabled 0` - Disable animations
- `decoration:shadow:enabled 0` - Disable shadows
- `decoration:blur:enabled 0` - Disable blur
- `general:gaps_in 0` - Remove inner gaps
- `general:gaps_out 0` - Remove outer gaps
- `general:border_size 1` - Minimal border
- `decoration:rounding 0` - No rounded corners
- `decoration:dim_inactive 0` - No dim on inactive windows

> **Note:** `allow_tearing` and `misc:vfr` were removed because they caused screen blinking with Steam notifications.

#### Feral GameMode (gamemoded)
- CPU Governor → `performance`
- GPU Performance Level → `high`
- Process Renice → 10 (higher priority)
- I/O Priority → optimized

#### Power Profile
- Switches to `performance` via `powerprofilesctl`
- Uses AMD amd_pstate driver

#### Idle Inhibitor
- Prevents screen sleep during gaming
- Prevents lid switch actions
- Uses `systemd-inhibit`

### What it does when DISABLED:
- Reloads Hyprland config (restores all settings)
- Deactivates Feral GameMode
- Switches power profile back to `balanced`
- Releases idle inhibitor

---

## ✅ TESTED & WORKING - Steam Launch Options

### Recommended Launch Options (Stable 60 FPS)
```
gamemoderun mangohud %command%
```

This is the **tested working configuration** for this hardware.

| Resolution | FPS | Notes |
|------------|-----|-------|
| **960p** (in-game) | **60 FPS stable** ✅ | Best performance/visual balance |
| 1080p | 25-30 FPS | Too demanding for Radeon 660M |
| 720p | 60+ FPS | If you need extra headroom |

### Steam Game Setup
1. Right-click game → **Properties**
2. **Compatibility** → Check "Force..." → Select **GE-Proton10-28**
3. **General** → Launch Options: `gamemoderun mangohud %command%`
4. **In-game**: Set resolution to **960p** (1704×960 or similar)

---

## FSR Upscaling (960p → 1080p)

FSR (FidelityFX Super Resolution) upscales lower resolution to your monitor's native resolution.

### Method 1: In-Game FSR (Recommended)
Many games have built-in FSR. Look for:
- Settings → Graphics → AMD FSR / FidelityFX
- Set to "Quality" or "Balanced"

### Method 2: Wine/Proton FSR (Environment Variable)
Already enabled in `~/.config/hypr/custom/env.conf`:
```conf
env = WINE_FULLSCREEN_FSR, 1
```

For per-game FSR strength, add to launch options:
```
WINE_FULLSCREEN_FSR=1 WINE_FULLSCREEN_FSR_STRENGTH=2 gamemoderun mangohud %command%
```

| FSR Strength | Quality |
|--------------|---------|
| 0 | Maximum sharpness |
| 2 | Balanced (default) |
| 5 | Softer/smoother |

### Method 3: Gamescope (⚠️ Black screen on this laptop)
Gamescope had display issues on this hardware. Use Method 1 or 2 instead.

---

## Proton-GE (Better Wine/Proton)

**Installed Version:** GE-Proton10-28

**Proton-GE** is a custom Proton build with:
- Latest DXVK/VKD3D
- Better game compatibility patches
- FSR built-in
- ESYNC/FSYNC support

### Installation
Managed via **ProtonUp-Qt** (`python -m pupgui2`)

### Location
`~/.steam/steam/compatibilitytools.d/GE-Proton10-28/`

### How to Use
1. Right-click game → **Properties**
2. Go to **Compatibility** tab
3. Check "Force the use of a specific Steam Play..."
4. Select **GE-Proton10-28** from dropdown

---

## Environment Variables (~/.config/hypr/custom/env.conf)

```conf
# AMD Gaming Optimizations
env = AMD_VULKAN_ICD, RADV          # Use Mesa RADV driver
env = RADV_PERFTEST, gpl            # Faster shader compilation
env = VKD3D_CONFIG, dxr             # DXR/Raytracing support
env = DXVK_ASYNC, 1                 # Async shader compilation
env = PROTON_ENABLE_NVAPI, 0        # Disable NVIDIA stuff
env = WINE_FULLSCREEN_FSR, 1        # Enable FSR for Wine/Proton
```

---

## Feral GameMode Config (/etc/gamemode.ini)

```ini
[general]
reaper_freq=5
desiredgov=performance
softrealtime=auto
renice=10
ioprio=0

[gpu]
apply_gpu_optimisations=accept-responsibility
gpu_device=1
amd_performance_level=high

[custom]
start=notify-send -a "GameMode" "🎮 Gaming Mode" "Performance mode activated"
end=notify-send -a "GameMode" "🎮 Gaming Mode" "Performance mode deactivated"
```

---

## Performance Targets

| Metric | Idle | Gaming (Game Mode ON) |
|--------|------|----------------------|
| CPU Governor | powersave | performance |
| CPU Freq | ~2.3 GHz | Up to 4.57 GHz |
| GPU Clock | 200-700 MHz | Up to 1899 MHz |
| Power Profile | balanced | performance |
| GPU DPM Level | auto | high |

---

## Useful Commands

```bash
# Check GameMode status
gamemoded --status

# Check power profile
powerprofilesctl get

# Check CPU governor
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# Check GPU clock states
cat /sys/class/drm/card1/device/pp_dpm_sclk

# Check GPU performance level
cat /sys/class/drm/card1/device/power_dpm_force_performance_level

# Check idle inhibitors
systemd-inhibit --list

# Manual GameMode test
gamemoderun glxgears
```

---

## Overclock Potential (NOT APPLIED)

The Radeon 660M can be overclocked from 1900 MHz to ~2400 MHz using:
- AMD APU Tuning Utility (GUI)
- Manual via `/sys/class/drm/card1/device/pp_od_clk_voltage`

**Safe limits:**
- Max Clock: 2350-2400 MHz
- Max Voltage: 1.10V (DO NOT exceed 1.20V)
- Max Temp: 85°C
- Max Package Power: 45W

**Current status: Stock (1899 MHz) - Already optimal for stability**

---

## Notes

- Game Mode toggle is in Quickshell sidebar (gamepad icon)
- Original `gaming.conf` was removed to prevent conflict with Quickshell toggle
- All optimizations are inspired by Nobara, CachyOS, and Garuda gaming distros
- Hyprland window rules for tearing (`immediate`) are in `~/.config/hypr/hyprland/rules.conf`
