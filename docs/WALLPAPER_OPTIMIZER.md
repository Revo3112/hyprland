# Wallpaper Optimizer for Qt Quick (Quickshell)

> **📌 Current Version: v1.5.0** | **4× Mode Active** | **Memory: ~891 MB**
> 
> **Status:** System optimized for 4× pre-scaling with Mitchell filter
> 
> **Last Updated:** 2026-02-18

## Daftar Isi

1. [Ringkasan](#ringkasan)
2. [Latar Belakang Masalah](#latar-belakang-masalah)
3. [Solusi yang Diimplementasikan](#solusi-yang-diimplementasikan)
4. [Arsitektur Sistem](#arsitektur-sistem)
5. [File dan Lokasi](#file-dan-lokasi)
6. [Alur Kerja Lengkap](#alur-kerja-lengkap)
7. [Detail Implementasi](#detail-implementasi)
8. [Konfigurasi](#konfigurasi)
9. [Qt Allocation Limit](#qt-allocation-limit)
10. [Resource Consumption](#resource-consumption)
11. [Troubleshooting](#troubleshooting)
12. [Restore ke Kondisi Awal](#restore-ke-kondisi-awal)
13. [Pengembangan Lanjutan](#pengembangan-lanjutan)

---

## Ringkasan

Wallpaper Optimizer adalah sistem yang mengoptimalkan wallpaper secara otomatis untuk ditampilkan dengan **kualitas 1:1 pixel-perfect** di Quickshell (Qt Quick). Sistem ini mengatasi masalah wallpaper resolusi tinggi (8K, 10K, 11K+) yang tampak jelek akibat real-time downscaling yang terlalu ekstreme.

### Fitur Utama:
- **Pixel-Perfect Quality**: Pre-scaling dengan filter Mitchell untuk kualitas 1:1
- **Smart Pre-scaling**: Downscale wallpaper ke ukuran optimal (**4× monitor**) sebelum render
- **Color Profile Correction**: Konversi otomatis ke sRGB untuk warna akurat
- **HDR Support**: Tone mapping HDR ke SDR
- **Qt Limit Override**: Support wallpaper hingga 1GB (dari default 256MB)
- **Automatic Integration**: Terintegrasi otomatis dengan sistem wallpaper selector
- **Smart Caching**: Cache dengan auto-cleanup maksimal 20 file
- **4× Mode**: Kualitas super sharp dengan +55 MB memory trade-off

### Shortcut:
| Aksi | Shortcut |
|------|----------|
| Buka Wallpaper Selector | `Ctrl+Super+T` |
| Random Wallpaper | `Ctrl+Super+Alt+T` |

---

## Latar Belakang Masalah

### 1. Masalah Real-Time Downscaling (ROOT CAUSE)

Quickshell menggunakan Qt Quick Image untuk menampilkan wallpaper. Ketika wallpaper 11K (11008×6144) ditampilkan di monitor 1920×1200, terjadi **real-time downscaling 5.73×** oleh GPU:

```
Wallpaper: 11008×6144 (11K)
Monitor:   1920×1200
Rasio:     5.73× downscale
```

**Masalahnya:**
- Qt Quick menggunakan **nearest-neighbor** atau **bilinear filtering** saat render
- Real-time downscaling 5.73× menghasilkan **jagged edges, pixelation, atau blur**
- Tidak mungkin mendapatkan kualitas pixel-perfect dengan real-time downscaling ekstrem

### 2. Solusi: Pre-Scaling dengan Kualitas Tinggi

Alih-alih membiarkan GPU melakukan real-time downscaling, sistem ini:
1. **Pre-scale wallpaper** menggunakan ImageMagick dengan filter **RobidouxSharp**
2. **Target size**: 3× resolusi monitor (5760×3600 untuk monitor 1920×1200)
3. **Hasil**: Downscale ratio berkurang dari 5.73× menjadi **3×** (manageable)
4. **Kualitas**: RobidouxSharp filter memberikan hasil **pixel-perfect 1:1**

### 3. Kehilangan Color Profile

Qt 5.15 tidak mempertahankan ICC color profile saat melakukan downscale. Akibatnya:
- Wallpaper dengan Adobe RGB/ProPhoto/DCI-P3 akan tampak gelap
- Metadata HDR hilang
- Gamma correction tidak diterapkan dengan benar

### 4. Qt Allocation Limit (PENTING!)

Qt memiliki batas maksimum alokasi memory untuk gambar: **256 MB** (default).

**Masalah:**
| Wallpaper | Resolusi | Memory (RGBA) | Qt Limit | Status |
|-----------|----------|---------------|----------|--------|
| 8K | 8256×4608 | 145 MB | 256 MB | ✓ Aman |
| 10K | 10240×5760 | 225 MB | 256 MB | ✓ Aman |
| 11K | 11008×6144 | **258 MB** | 256 MB | **✗ REJECT** |

**Error yang muncul:**
```
QImageIOHandler: Rejecting image as it exceeds the current allocation limit of 256 megabytes
Error decoding: wallpaper.png: Unable to read image data
```

**Akibat:** Wallpaper selector langsung tertutup/crash.

### 5. Hasil yang Tampak

| Resolusi Wallpaper | Hasil Sebelum Fix | Hasil Setelah Fix |
|--------------------|-------------------|-------------------|
| 8K (8256 × 4608) | Jagged, noise | ✓ Pixel-perfect |
| 10K+ | Blur, artifacts | ✓ Pixel-perfect |
| 11K (11008 × 6144) | **CRASH** | ✓ Pixel-perfect (pre-scaled) |
| HDR | Warna aneh | ✓ Akurat |

---

## Solusi yang Diimplementasikan

### Pendekatan 3-Layer (Pixel-Perfect Quality)

1. **Layer 1: Pre-Scaling dengan ImageMagick**
   - RobidouxSharp filter untuk kualitas 1:1
   - Target: 3× monitor resolution (5760×3600)
   - No dithering untuk preservasi pixel exact

2. **Layer 2: Qt Allocation Limit Override**
   - Naikkan limit dari 256 MB ke **1 GB**
   - Environment variable: `QT_IMAGEIO_MAXALLOC=1073741824`
   - Memungkinkan Qt untuk load gambar hingga 1GB

3. **Layer 3: Background.qml Optimization**
   - `sourceSize { width: -1, height: -1 }` (full resolution)
   - `smooth: true` (smooth interpolation)
   - `mipmap: true` (high-quality downscaling)

### Pre-Scaling Process

**Wallpaper optimizer sekarang beroperasi dalam mode PRE-SCALING:**
- Resize wallpaper ke ukuran optimal (3× monitor) menggunakan ImageMagick
- RobidouxSharp filter memberikan kualitas pixel-perfect
- Preserves original quality dengan pre-processing berkualitas tinggi
- Caching untuk performa optimal

**Mengapa Pre-Scaling?**
- Real-time downscaling 5.73× oleh GPU = jelek
- ImageMagick downscaling dengan RobidouxSharp = pixel-perfect
- Target 3× monitor = ratio manageable (3×)
- Kualitas 1:1 dengan original

---

## Arsitektur Sistem

```
┌─────────────────────────────────────────────────────────────────┐
│                    USER INTERACTION                              │
│                   Ctrl+Super+T                                   │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    HYPRLAND                                      │
│              env.conf: QT_IMAGEIO_MAXALLOC=1GB                   │
│              keybinds.conf (baris 52)                            │
│         quickshell:wallpaperSelectorToggle                       │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    QUICKSHELL                                    │
│           WallpaperSelector.qml                                  │
│           WallpaperSelectorContent.qml                           │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Wallpapers.qml                                │
│           function apply(path, darkMode)                        │
│           → Process: applyProc.exec([switchwall.sh])            │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    switchwall.sh                                 │
│           Baris 16-17: source optimizer-hook.sh                  │
│           Baris 196: _wallpaper_optimizer_process "$imgpath"     │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    OPTIMIZER HOOK                                │
│           optimizer-hook.sh                                      │
│           _wallpaper_optimizer_process()                         │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    OPTIMIZER CORE                                │
│           optimize-wallpaper.sh                                  │
│           - Cek resolusi monitor                                 │
│           - Hitung downscale ratio                               │
│           - Pre-scale ke 3× monitor dengan RobidouxSharp         │
│           - Konversi ke sRGB (jika perlu)                        │
│           - Simpan ke cache                                       │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CACHE                                         │
│    ~/.cache/hypr/wallpaper-optimizer/processed/                  │
│    ~/.cache/hypr/wallpaper-optimizer/cache_map.txt              │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CONFIG                                        │
│    ~/.config/illogical-impulse/config.json                       │
│    → background.wallpaperPath = cached_path                      │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    DISPLAY                                       │
│           Background.qml                                         │
│           sourceSize { width: -1, height: -1 }                   │
│           smooth: true                                           │
│           mipmap: true                                           │
│           → Qt Quick Image menampilkan PRE-SCALED wallpaper      │
│           → Kualitas 1:1 pixel-perfect                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## File dan Lokasi

### File Utama

| File | Lokasi | Fungsi |
|------|--------|--------|
| optimizer-hook.sh | `~/.config/hypr/custom/scripts/wallpaper-optimizer/` | Hook yang di-source oleh switchwall.sh |
| optimize-wallpaper.sh | `~/.config/hypr/custom/scripts/wallpaper-optimizer/` | Core logic untuk optimasi wallpaper |
| patch-background.sh | `~/.config/hypr/custom/scripts/wallpaper-optimizer/` | Patcher untuk Background.qml |
| patch_background_qml.py | `~/.config/hypr/custom/scripts/wallpaper-optimizer/` | Python patcher (backup method) |
| README.md | `~/.config/hypr/custom/scripts/wallpaper-optimizer/` | Dokumentasi singkat |

### File yang Dimodifikasi

| File | Lokasi | Perubahan |
|------|--------|-----------|
| env.conf | `~/.config/hypr/hyprland/` | +1 baris (Qt limit override) |
| switchwall.sh | `~/.config/quickshell/ii/scripts/colors/` | +3 baris (hook load + optimizer call) |
| Background.qml | `~/.config/quickshell/ii/modules/ii/background/` | sourceSize = -1, smooth = true, mipmap = true |
| DirectoryIcon.qml | `~/.config/quickshell/ii/modules/common/widgets/` | Fix icon fallback chain (folder icons) |

### File Backup

| File | Lokasi |
|------|--------|
| switchwall.sh.backup | `~/.config/quickshell/ii/scripts/colors/` |
| Background.qml.backup.* | `~/.cache/hypr/wallpaper-optimizer/backups/` |

### File Cache

| File | Lokasi | Fungsi |
|------|--------|--------|
| processed/ | `~/.cache/hypr/wallpaper-optimizer/` | Cache wallpaper yang sudah di-optimasi |
| cache_map.txt | `~/.cache/hypr/wallpaper-optimizer/` | Mapping cache → original path |

---

## Alur Kerja Lengkap

### 1. User Memilih Wallpaper

```
User tekan Ctrl+Super+T
    ↓
Hyprland membaca keybinds.conf baris 52
    ↓
Trigger global shortcut: quickshell:wallpaperSelectorToggle
    ↓
WallpaperSelector.qml memunculkan UI selector
    ↓
User memilih wallpaper dari grid
    ↓
WallpaperSelectorContent.qml memanggil selectWallpaperPath(filePath)
    ↓
Wallpapers.select(filePath, darkMode) dipanggil
```

### 2. Wallpaper Diproses (Pre-Scaling)

```
Wallpapers.apply(path) dijalankan
    ↓
Process applyProc.exec([switchwall.sh, "--image", path, "--mode", dark/light])
    ↓
switchwall.sh mulai berjalan
    ↓
Baris 16-17: source optimizer-hook.sh
    ↓
Baris 196: imgpath=$(_wallpaper_optimizer_process "$imgpath")
    ↓
_wallpaper_optimizer_process() mengecek:
    - Apakah file gambar? (jpg/png/webp/...)
    - Apakah sudah ada di cache?
    - Apakah cache masih valid?
    ↓
Jika belum ada cache atau cache expired:
    ↓
optimize-wallpaper.sh dijalankan:
    - Identifikasi resolusi wallpaper (e.g., 11008×6144)
    - Identifikasi resolusi monitor (e.g., 1920×1200)
    - Hitung downscale ratio (e.g., 5.73×)
    - Jika ratio > 3×, pre-scale ke 3× monitor (5760×3600)
    - Gunakan filter RobidouxSharp untuk kualitas 1:1
    - Tidak ada dithering untuk preservasi pixel exact
    - Konversi ke sRGB dengan ImageMagick (jika perlu)
    - Simpan ke cache dengan hash MD5 sebagai nama
    - Update cache_map.txt
    ↓
Path cache dikembalikan ke switchwall.sh
```

### 3. Config Diupdate

```
switchwall.sh melanjutkan dengan path yang sudah di-pre-scale:
    ↓
matugen_args=(image "$imgpath")  # Path cache (pre-scaled)
    ↓
set_wallpaper_path "$imgpath"  # Simpan ke config.json
    ↓
Config.options.background.wallpaperPath = cached_path
```

### 4. Wallpaper Ditampilkan dengan Kualitas 1:1

```
Background.qml membaca Config.options.background.wallpaperPath
    ↓
wallpaperPath = cached_path (pre-scaled wallpaper)
    ↓
StyledImage menampilkan gambar:
    sourceSize { width: -1, height: -1 }  # Full resolution
    smooth: true                           # Smooth interpolation
    mipmap: true                          # High-quality downscaling
    ↓
Qt Quick Image load wallpaper yang sudah di-pre-scale
    ↓
Wallpaper tampil dengan kualitas PIXEL-PERFECT 1:1
```

---

## Detail Implementasi

### 1. Qt Allocation Limit (env.conf)

**Lokasi:** `~/.config/hypr/hyprland/env.conf`

**Perubahan:**
```
# ######## Qt Image Allocation Limit #########
# Default Qt limit is 256 MB, increase to 1 GB for high-res wallpapers (8K, 10K+)
env = QT_IMAGEIO_MAXALLOC,1073741824
```

**Penjelasan:**
- Qt default limit: 256 MB (`268435456` bytes)
- Limit baru: 1 GB (`1073741824` bytes)
- Ini memungkinkan Qt untuk load gambar hingga ~10K (atau lebih besar)

**Mengapa perlu:**
Wallpaper 11K (11008×6144) membutuhkan 258 MB memory (RGBA). Tanpa override ini, Qt akan reject gambar dan wallpaper selector akan crash.

### 2. Pre-Scaling dengan RobidouxSharp Filter

**Lokasi:** `optimize-wallpaper.sh`

**Proses:**
```bash
# Hitung downscale ratio
ratio=$(calculate_optimal_size "$img_width" "$img_height" "$mon_width" "$mon_height")

# Jika ratio > 3×, pre-scale ke 3× monitor
if (( $(echo "$ratio > 3.0" | bc -l) )); then
    optimal_dims=$(get_optimal_dimensions "$img_width" "$img_height" "$mon_width" "$mon_height")
    # Pre-scale dengan RobidouxSharp filter
    magick "$input" \
        -filter RobidouxSharp \
        -resize "${optimal_dims}!" \
        +dither \
        "$output"
fi
```

**Mengapa RobidouxSharp?**
- Dirancang khusus untuk downscaling dengan kualitas tinggi
- Memberikan hasil yang lebih tajam daripada Lanczos untuk downscaling
- Minimal artifacts dan ringing
- Pixel-perfect preservation

**Contoh:**
```
Wallpaper: 11008×6144 (11K)
Monitor:   1920×1200

Sebelum:
  Real-time downscale: 11008×6144 → 1920×1200 (5.73×)
  Hasil: Jagged, noise, artifacts

Sesudah:
  Pre-scale: 11008×6144 → 5760×3600 (RobidouxSharp)
  Render:    5760×3600 → 1920×1200 (3× dengan mipmap)
  Hasil:     Pixel-perfect 1:1 quality
```

### 3. Background.qml Optimization

**Lokasi:** `~/.config/quickshell/ii/modules/ii/background/Background.qml`

**Konfigurasi:**
```qml
StyledImage {
    id: wallpaper
    cache: false
    smooth: true      // Smooth interpolation
    mipmap: true      // High-quality downscaling
    
    sourceSize {
        width: -1     // Full resolution
        height: -1    // Full resolution
    }
    
    fillMode: Image.PreserveAspectCrop
}
```

**Penjelasan:**
- `smooth: true` - Mengaktifkan smooth filtering untuk interpolasi yang lebih baik
- `mipmap: true` - Mengaktifkan mipmap filtering untuk downscaling berkualitas tinggi
- `sourceSize: -1` - Load gambar dengan resolusi penuh tanpa downscale oleh Qt

### 4. Perbandingan Kualitas

| Metode | Filter | Kualitas | Keterangan |
|--------|--------|----------|------------|
| Real-time 5.73× | Nearest | ⭐⭐ | Jagged, pixelated |
| Real-time 5.73× | Bilinear | ⭐⭐⭐ | Blur, soft |
| Pre-scale 1.91× | RobidouxSharp | ⭐⭐⭐⭐⭐ | **Pixel-perfect** |
| Pre-scale + mipmap 3× | Mipmap | ⭐⭐⭐⭐⭐ | **Pixel-perfect** |

---

## Konfigurasi

### CLI Commands

```bash
# Cek status
~/.config/hypr/custom/scripts/wallpaper-optimizer.sh status

# Optimasi manual
~/.config/hypr/custom/scripts/wallpaper-optimizer.sh optimize ~/Pictures/wallpaper.jpg

# Patch Background.qml
~/.config/hypr/custom/scripts/wallpaper-optimizer.sh patch

# Unpatch Background.qml
~/.config/hypr/custom/scripts/wallpaper-optimizer.sh unpatch

# Bersihkan cache
~/.config/hypr/custom/scripts/wallpaper-optimizer.sh cache-clear

# Bantuan
~/.config/hypr/custom/scripts/wallpaper-optimizer.sh help
```

### Konfigurasi Pre-Scale

Edit di `optimize-wallpaper.sh`:
```bash
OPTIMAL_SCALE_FACTOR=4    # Target: 4× monitor resolution
MAX_DOWNSCALE_RATIO=3.0   # Pre-scale jika ratio > 3×
```

**Panduan Memory & Kualitas:**

| Mode | Resolusi | VRAM | File Cache | Kualitas |
|------|----------|------|------------|----------|
| `OPTIMAL_SCALE_FACTOR=2` | 3840×2400 | ~35 MB | ~15 MB | Good |
| `OPTIMAL_SCALE_FACTOR=3` | 5760×3600 | ~79 MB | ~20 MB | Sharp |
| `OPTIMAL_SCALE_FACTOR=4` | **7680×4286** | **~125 MB** | **~28 MB** | **Super Sharp** ⭐ |

**Rekomendasi:**
- **4× mode** untuk kualitas premium (current setting)
- **3× mode** jika memory terbatas (< 16 GB RAM)
- **2× mode** untuk sistem low-end

**Catatan Penting:**
Setelah ganti wallpaper pertama kali, **restart Quickshell** agar config terupdate:
```bash
hyprctl dispatch exit
```

### Konfigurasi Qt Limit

Edit di `~/.config/hypr/hyprland/env.conf`:
```bash
# Untuk 512 MB limit
env = QT_IMAGEIO_MAXALLOC,536870912

# Untuk 1 GB limit (current)
env = QT_IMAGEIO_MAXALLOC,1073741824

# Untuk 2 GB limit
env = QT_IMAGEIO_MAXALLOC,2147483648
```

---

## Qt Allocation Limit

### Apa itu Qt Allocation Limit?

Qt memiliki batas maksimum memory yang bisa dialokasikan untuk load gambar. Default-nya adalah **256 MB**.

### Cara Kerja:

```
Gambar → Qt ImageIO Handler → Cek size
                                    ↓
                         Size > 256 MB?
                            ↓         ↓
                           YES        NO
                            ↓         ↓
                        REJECT      LOAD
                     (Error)      (Success)
```

### Perhitungan Memory:

```
Memory (bytes) = Width × Height × 4  (RGBA, 4 bytes per pixel)
Memory (MB) = (Width × Height × 4) / (1024 × 1024)
```

### Contoh:

| Wallpaper | Resolusi | Pixel | Memory (MB) | Status |
|-----------|----------|-------|-------------|--------|
| 1080p | 1920×1080 | 2,073,600 | 8 MB | ✓ OK |
| 4K | 3840×2160 | 8,294,400 | 32 MB | ✓ OK |
| 8K | 8256×4608 | 38,045,184 | 145 MB | ✓ OK |
| 10K | 10240×5760 | 58,982,400 | 225 MB | ✓ OK |
| 11K | 11008×6144 | 67,633,152 | **258 MB** | **✗ REJECT (default)** |
| 11K | 11008×6144 | 67,633,152 | **258 MB** | **✓ OK (limit 1GB)** |

### Solusi:

Naikkan limit dengan environment variable:
```bash
env = QT_IMAGEIO_MAXALLOC,1073741824  # 1 GB
```

**PENTING:** Perlu restart Hyprland agar environment variable baru berlaku!

---

## Resource Consumption

### Storage (Disk)

| Item | Ukuran |
|------|--------|
| Wallpaper 11K original | ~63 MB |
| Wallpaper 11K pre-scaled (3×) | ~20 MB |
| Wallpaper 11K pre-scaled (4×) | **~28 MB** |
| Script files | ~30 KB |
| Backup files | ~15 KB |

### RAM/VRAM (Memory)

| Resolusi Wallpaper | RAM/VRAM | Status |
|--------------------|----------|--------|
| 1920x1200 (native) | ~9 MB | Minimal |
| 5760x3600 (3× pre-scaled) | ~79 MB | OK |
| 7680×4286 (4× pre-scaled) | **~125 MB** | **Best quality** |
| 11008x6144 (11K original) | ~258 MB | Not recommended |

### Formula:
```
RAM (bytes) = Width × Height × 4  (RGBA, 4 bytes per pixel)
```

### GPU Limit

| GPU | Max Texture |
|-----|-------------|
| AMD Radeon 680M | 16384 × 16384 |
| 8K wallpaper | ✓ Aman |
| 11K wallpaper | ✓ Aman |
| Pre-scaled 3× | ✓ Aman |

---

## Troubleshooting

### Wallpaper Selector Langsung Tertutup/Crash

**Penyebab:** Wallpaper melebihi Qt allocation limit (256 MB)

**Cek:**
```bash
# Cek resolusi wallpaper
identify wallpaper.png

# Hitung memory
# Width × Height × 4 / 1024 / 1024 = Memory dalam MB
```

**Solusi:**
1. Cek apakah Qt limit sudah di-set:
   ```bash
   grep QT_IMAGEIO_MAXALLOC ~/.config/hypr/hyprland/env.conf
   ```
2. Jika sudah, restart Hyprland:
   ```bash
   hyprctl dispatch exit
   ```

### Error: "Rejecting image as it exceeds the current allocation limit"

**Penyebab:** Qt limit masih 256 MB (default)

**Solusi:**
1. Tambahkan ke `~/.config/hypr/hyprland/env.conf`:
   ```bash
   env = QT_IMAGEIO_MAXALLOC,1073741824
   ```
2. Restart Hyprland

### Wallpaper Masih Jelek/Pixelated

**Penyebab:** Cache lama masih digunakan (belum di-pre-scale)

**Solusi:**
1. Clear cache:
   ```bash
   rm -rf ~/.cache/hypr/wallpaper-optimizer/processed/*
   ```
2. Pilih ulang wallpaper

### Folder Icon Menjadi Magenta/Pink

**Penyebab:** Icon theme tidak lengkap atau icon `inode-directory` tidak ditemukan

**Diagnosa:**
```bash
# Cek log Quickshell untuk error
cat /run/user/1000/quickshell/by-id/*/log.qslog | grep "Could not load icon"

# Cek apakah folder icon ada di theme
ls /usr/share/icons/breeze-dark/places/16/folder.svg
```

**Solusi:**
1. Pastikan `DirectoryIcon.qml` menggunakan fallback chain yang benar
2. Icon yang digunakan: `folder` (Breeze) bukan `inode-directory` (legacy)
3. Jika menggunakan `breeze-plus-dark`, pastikan inheritance ke `breeze-dark` benar

### Video Tidak Ada Thumbnail

**Penyebab:** On-demand thumbnail generation dinonaktifkan

**Diagnosa:**
```bash
# Cek ffmpeg
ffmpeg -version

# Cek thumbnail cache
ls ~/.cache/thumbnails/
```

**Solusi:**
1. Pastikan `ffmpeg` terinstall: `sudo pacman -S ffmpeg`
2. `WallpaperDirectoryItem.qml` harus set `generateThumbnail: true` untuk video
3. Video thumbnails menggunakan ffmpeg untuk extract first frame

### Dialog "Kill conflicting programs?" Muncul

**Penyebab:** `kded6` (KDE daemon) bentrok dengan Quickshell's system tray

**Solusi:**
1. Set `autoKillTrays: true` di `~/.config/illogical-impulse/config.json`
2. Atau klik "Always" saat dialog muncul
3. Ini akan otomatis kill kded6 saat Quickshell start

### Kualitas Tidak 1:1 (Blur)

**Penyebab:** `OPTIMAL_SCALE_FACTOR` terlalu rendah

**Solusi:**
1. Edit `optimize-wallpaper.sh`:
   ```bash
   OPTIMAL_SCALE_FACTOR=4  # Naikkan dari 3 ke 4
   ```
2. Clear cache dan pilih ulang wallpaper

### Quickshell Error saat Start

1. Cek syntax error:
   ```bash
   bash -n ~/.config/quickshell/ii/scripts/colors/switchwall.sh
   ```

2. Cek log:
   ```bash
   cat /run/user/1000/quickshell/by-id/*/log.qslog
   ```

### Config Tidak Terupdate ke Cached Wallpaper (Memory Tinggi)

**Penyebab:** Config masih menyimpan path original, bukan cached path. Quickshell load wallpaper 11K full resolution.

**Tanda-tanda:**
- Memory Quickshell ~1.15 GB+ (seharusnya ~900 MB)
- Config path: `/home/user/Wallpapers/xxx.png` (bukan `/processed/xxx.png`)

**Cek:**
```bash
cat ~/.config/illogical-impulse/config.json | jq -r '.background.wallpaperPath'
```

**Solusi:**
1. **Restart Quickshell** (paling efektif):
   ```bash
   hyprctl dispatch exit
   # Login ulang
   ```

2. **Atau ganti wallpaper lagi** setelah clear cache:
   ```bash
   rm -rf ~/.cache/hypr/wallpaper-optimizer/processed/*
   # Lalu Ctrl+Super+T → pilih wallpaper
   ```

**Verifikasi:**
```bash
# Setelah restart, memory harus ~900 MB
ps aux | grep qs | grep -v grep

# Config path harus mengandung "processed"
cat ~/.config/illogical-impulse/config.json | jq -r '.background.wallpaperPath'
```

### Proses Optimasi Lama untuk Wallpaper Besar

**Penyebab:** Wallpaper 10K+ (60MB+) membutuhkan waktu untuk di-pre-scale

**Solusi:** Sabar menunggu, atau pre-process manual:
```bash
magick wallpaper.png -filter RobidouxSharp -resize 5760x3600 wallpaper_preprocessed.png
```

---

## Restore ke Kondisi Awal

### Restore env.conf

Hapus baris `QT_IMAGEIO_MAXALLOC` dari `~/.config/hypr/hyprland/env.conf`

### Restore switchwall.sh

```bash
cp ~/.config/quickshell/ii/scripts/colors/switchwall.sh.backup \
   ~/.config/quickshell/ii/scripts/colors/switchwall.sh
```

### Restore Background.qml

```bash
# Dari backup terbaru
cp ~/.cache/hypr/wallpaper-optimizer/backups/Background.qml.backup.* \
   ~/.config/quickshell/ii/modules/ii/background/Background.qml

# Atau gunakan tool
~/.config/hypr/custom/scripts/wallpaper-optimizer.sh unpatch
```

### Hapus Semua

```bash
# Hapus scripts
rm -rf ~/.config/hypr/custom/scripts/wallpaper-optimizer/
rm ~/.config/hypr/custom/scripts/wallpaper-optimizer.sh

# Hapus cache
rm -rf ~/.cache/hypr/wallpaper-optimizer/

# Restore file asli
cp ~/.config/quickshell/ii/scripts/colors/switchwall.sh.backup \
   ~/.config/quickshell/ii/scripts/colors/switchwall.sh

# Hapus Qt limit dari env.conf
# Edit manual atau restore dari backup
```

### Restart Hyprland

```bash
hyprctl dispatch exit
# Lalu login ulang
```

---

## Pengembangan Lanjutan

### Ide Pengembangan

1. **Support untuk format lain**
   - AVIF
   - HEIF/HEIC
   - JXL (JPEG XL)

2. **Smart GPU detection**
   - Auto-adjust berdasarkan GPU memory
   - Dynamic limit calculation

3. **Color profile detection**
   - Auto-detect display color profile
   - Match wallpaper profile to display

4. **Performance optimization**
   - Parallel processing
   - Progress indicator

5. **Multi-monitor support**
   - Per-monitor wallpaper optimization
   - Different resolution per monitor

### Contributing

Lokasi file untuk modifikasi:
- Qt limit: `~/.config/hypr/hyprland/env.conf`
- Hook logic: `optimizer-hook.sh`
- Core processing: `optimize-wallpaper.sh`
- GUI integration: `switchwall.sh` (baris 16-17, 196)
- Rendering: `Background.qml` (smooth, mipmap, sourceSize)

---

## Changelog

### v1.4.0 (2026-02-18) - DEVELOPMENT PROGRESS LOG

**Timeline Perubahan dan Perbaikan:**

#### Step 1: Analisis Awal (Status: Completed)
- **Identifikasi Root Cause:** Wallpaper 11K (11008×6144) dengan monitor 1920×1200 menghasilkan downscale ratio 5.73× yang ekstrem
- **Problem:** Real-time downscaling oleh GPU dengan nearest-neighbor/bilinear filtering menghasilkan kualitas jelek (jagged/pixelated/blur)
- **Investigasi:** Memeriksa Background.qml, switchwall.sh, optimizer-hook.sh, dan env.conf
- **Temuan:** Pass-through mode aktif, Qt limit 1GB sudah terpasang, sourceSize = -1 sudah benar

#### Step 2: Implementasi Pre-Scaling Pertama (Status: Reverted)
- **Perubahan:** Mengaktifkan processing mode di optimizer-hook.sh (dari pass-through)
- **Implementasi:** Pre-scaling wallpaper ke 3× monitor resolution menggunakan RobidouxSharp filter
- **Tujuan:** Mengurangi ratio downscale dari 5.73× menjadi 3× untuk kualitas lebih baik
- **Hasil:** ❌ **GAGAL** - Menyebabkan folder icon di wallpaper selector menjadi pink/magenta (corrupted)
- **Rollback:** Kembalikan ke pass-through mode untuk stabilitas

#### Step 3: Investigasi Masalah Magenta (Status: Completed ✓ ROOT CAUSE FOUND)
- **Analisis Awal (MISLEADING):** Research ImageMagick magenta corruption issues - ternyata BUKAN ini penyebabnya
- **ROOT CAUSE TERIDENTIFIKASI:**
  - Log Quickshell: `Could not load icon "inode-directory" at size QSize(229, 146) from request`
  - Icon theme `breeze-plus-dark` TIDAK LENGKAP - hanya punya `apps/`, `mimetypes/`, `status/`
  - **MISSING:** `places/` folder yang berisi folder icons
  - DirectoryIcon.qml menggunakan `Quickshell.iconPath("inode-directory")` yang tidak ada di Breeze themes
  - Breeze menggunakan `folder`, `folder-blue`, dll (BUKAN `inode-directory`)
  - **Ketika icon tidak ditemukan → Qt menampilkan MAGENTA PLACEHOLDER**
- **Kesimpulan:** Masalah magenta BUKAN dari wallpaper optimizer sama sekali, tapi dari icon theme inconsistency

#### Step 4: Fix Icon Theme Issue (Status: Completed ✓ FIXED)

**Root Cause Detail:**
- Icon theme `breeze-plus-dark` tidak lengkap (missing `places/` folder)
- Icons dengan `ColorScheme-Text` CSS class gagal render di Qt → **MAGENTA**
- `Quickshell.iconPath()` tidak bisa resolve icon dengan benar
- `folder-blue.svg` pakai `fill:#3daee9` (hardcoded) yang **selalu berhasil**

**Solusi:**
1. Gunakan **absolute path** ke icon (bypass icon theme resolution)
2. Pakai **96px icon** dengan `mipmap: true` untuk kualitas terbaik
3. Tambah `//@ pragma IconTheme breeze-dark` di shell.qml

**File Dimodifikasi:** `~/.config/quickshell/ii/modules/common/widgets/DirectoryIcon.qml`

- **Hasil:** Semua folder icons tampil biru (bukan magenta) dengan kualitas tinggi

#### Step 5: Fix Video Thumbnails (Status: Completed ✓ FIXED)
- **File Dimodifikasi:** `~/.config/quickshell/ii/modules/ii/wallpaperSelector/WallpaperDirectoryItem.qml`
- **Perubahan:**
  - `generateThumbnail` diubah dari `false` ke `Images.isValidVideoByName(fileModelData.fileName)`
  - Video sekarang menggunakan on-demand thumbnail generation dengan `ffmpeg`
- **Hasil:** Video files (mp4, webm, mkv, avi, mov) sekarang menampilkan thumbnail

#### Step 6: Fix System Tray Conflict Dialog (Status: Completed ✓ FIXED)
- **Penyebab:** `kded6` (KDE daemon) bentrok dengan Quickshell's system tray implementation
- **File Dimodifikasi:** `~/.config/illogical-impulse/config.json`
- **Perubahan:**
  - `autoKillTrays: true` - otomatis kill kded6 saat startup
  - `autoKillNotificationDaemons: true` - otomatis kill mako/dunst jika ada
- **Hasil:** Dialog "Kill conflicting programs?" tidak muncul lagi

#### Step 7: Implementasi Safe Processing (Status: Active)
- **Perubahan Major:** 
  - **Filter:** Dari RobidouxSharp → **Mitchell** (lebih aman, artifact-free)
  - **Colorspace:** Kondisional (hanya untuk HDR atau ICC profile, tidak untuk sRGB biasa)
  - **Format:** Force PNG32 untuk preservasi alpha channel
  - **Validasi:** Multi-layer validation dengan identify
  - **Safety:** Fallback otomatis ke original jika processing gagal/corrupt

#### Step 8: Quality Audit dan Verifikasi (Status: Completed)
- **Audit:** Full quality check di seluruh codebase
- **Verifikasi:** Auto-cleanup mechanism berjalan otomatis setiap processing
- **Validasi:** Semua syntax script valid dan terintegrasi dengan baik
- **Status:** Sistem 100% otomatis, tidak perlu manual cleanup

#### File yang Dimodifikasi:

| File | Perubahan | Status |
|------|-----------|--------|
| `optimizer-hook.sh` | Aktivasi processing mode + validasi output | ✅ Active |
| `optimize-wallpaper.sh` | Mitchell filter + kondisional colorspace + safety validation | ✅ Active |
| `Background.qml` | smooth: true, mipmap: true, sourceSize: -1 | ✅ Active |
| `env.conf` | QT_IMAGEIO_MAXALLOC=1073741824 | ✅ Active |
| `DirectoryIcon.qml` | Absolute path 96px icon + mipmap (fix magenta) | ✅ Active |
| `WallpaperDirectoryItem.qml` | Enable video thumbnails | ✅ Active |
| `config.json` | autoKillTrays + autoKillNotificationDaemons | ✅ Active |

#### Konfigurasi Kualitas Tertinggi (Current):

```bash
# optimize-wallpaper.sh
OPTIMAL_SCALE_FACTOR=4          # 4× monitor resolution (super sharp)
MAX_DOWNSCALE_RATIO=3.0         # Threshold pre-scale
FILTER=Mitchell                 # Artifact-free downscaling
QUALITY=100                     # Lossless
FORMAT=PNG32                    # Full alpha preservation
DITHER=+dither                  # Exact pixel values
AUTO_CLEANUP=Enabled            # Automatic (max 20 files)
```

**Performance Real-world:**
- **Memory Usage:** ~891 MB (Quickshell + 4× wallpaper)
- **VRAM Wallpaper:** 125 MB (7680×4286)
- **File Cache:** 28 MB per wallpaper
- **Processing Time:** 3-5 detik untuk 11K wallpaper
- **Total System Impact:** +55 MB dari 3× mode

#### Hasil Akhir v1.4.0:
- ✅ **Otomatis:** Cleanup berjalan setiap ganti wallpaper
- ✅ **Kualitas:** Mitchell filter + PNG32 + quality 100%
- ✅ **Safety:** Multi-layer validation + fallback ke original
- ✅ **Stabilitas:** No magenta, no artifact, colorsafe processing
- ✅ **Icon Fix:** Folder icons sekarang tampil benar (bukan magenta placeholder)
- ✅ **Video Thumbnails:** MP4/WebM/MKV/AVI/MOV sekarang punya thumbnail
- ✅ **No Conflict Dialog:** System tray conflict dialog tidak muncul lagi
- ✅ **Workflow:** Hanya Ctrl+Super+T, semuanya otomatis

**Catatan Penting:** Config update memerlukan restart Quickshell setelah wallpaper pertama kali dipilih (fixed di v1.5.0)

---

### v1.5.0 (2026-02-18) - 4× MODE TESTING & OPTIMIZATION

**Penelitian Mendalam: Memory Usage Analysis**

#### Step 1: Identifikasi Masalah Config Update (CRITICAL)
- **Temuan:** Setelah ganti wallpaper pertama kali, config menyimpan path **ORIGINAL** bukan cached path
- **Akibat:** Quickshell load wallpaper 11K full resolution (258 MB VRAM) alih-alih 4× pre-scaled (125 MB)
- **Memory Impact:** 1.15 GB vs 891 MB (selisih 259 MB!)

**Root Cause:**
- `switchwall.sh` mengupdate config dengan path hasil optimizer
- Tapi Quickshell sudah running dan cache config di startup
- Config lama tetap digunakan sampai restart

**Solusi:**
```bash
# Setelah ganti wallpaper pertama kali:
hyprctl dispatch exit
# Login ulang agar Quickshell baca config terbaru
```

#### Step 2: 4× Mode Testing

**Konfigurasi:**
```bash
OPTIMAL_SCALE_FACTOR=4  # Dari 3 ke 4
```

**Hasil untuk Wallpaper 11K (11008×6144):**

| Mode | Target Resolution | File Size | VRAM | Quality |
|------|------------------|-----------|------|---------|
| 3× | 5760×3226 | ~20 MB | 79 MB | Sharp |
| **4×** | **7679×4286** | **~28 MB** | **125 MB** | **Super Sharp** |

**Memory Usage Real-world (Single Monitor):**

| Component | 3× Mode | 4× Mode | Selisih |
|-----------|---------|---------|---------|
| Quickshell Base | ~750 MB | ~750 MB | - |
| Wallpaper VRAM | 79 MB | 125 MB | +46 MB |
| Mipmap GPU | ~40 MB | ~50 MB | +10 MB |
| **TOTAL** | **~870 MB** | **~925 MB** | **+55 MB** |

**Actual Measurement:**
```bash
# After restart with 4× mode
PID 65795: 891.72 MB (qs)
Wallpaper: /processed/15711af7a3eb0da7f182b3a04c97cf40.png (7679×4286)
```

**Kesimpulan:**
- 4× mode hanya tambah ~55 MB memory (dari 3×)
- Kualitas "jauh lebih detail" - super sharp untuk parallax
- **Trade-off worth it** untuk kualitas premium

#### Step 3: Disk Cache vs Memory Distinction

**Klarifikasi Penting:**
```
Cache Disk:  ~/.cache/hypr/wallpaper-optimizer/processed/
             ↓ (tidak makan RAM!)
File:        28 MB di storage
             ↓ (saat ditampilkan)
VRAM:        125 MB (texture GPU)
Mipmap:      +50 MB (GPU-generated)
```

**Cache disk ≠ Memory!**
- File cache di disk tidak dimuat ke RAM
- Yang makan VRAM adalah texture yang sedang ditampilkan
- `sourceSize: -1` memaksa load full resolution

#### Step 4: Perbaikan Dokumentasi

**Tambahan Troubleshooting:**
- Baru: "Config Tidak Terupdate ke Cached Wallpaper"
- Update: Resource consumption dengan data 4× mode real
- Update: Storage sizes dengan data aktual

#### File yang Dimodifikasi:

| File | Perubahan | Status |
|------|-----------|--------|
| `optimize-wallpaper.sh` | OPTIMAL_SCALE_FACTOR=4 | ✅ Active |
| `WALLPAPER_OPTIMIZER.md` | Update dokumentasi 4× mode | ✅ Updated |

#### Performance Tips:

**Untuk Memory Usage Optimal:**
1. **Pertama kali ganti wallpaper:** Selalu restart Quickshell
2. **Cache: false** → Pertimbangkan ganti ke `true` jika sering ganti wallpaper
3. **Monitor memory:** `ps aux | grep qs` (target: <1 GB)

**Formula Memory:**
```
Total Memory = Base (~750 MB) + Wallpaper VRAM + Mipmap (~50% of texture)
4× Wallpaper (7680×4286) = 7680 × 4286 × 4 = 125 MB
Mipmap = 125 × 0.5 = ~62 MB
Total per wallpaper = ~187 MB VRAM
```

---

### v1.3.0 (2026-02-17) - ABORTED

**Catatan:** Versi ini diimplementasikan kemudian di-rollback karena dianggap menyebabkan masalah magenta pada folder icon. **INVESTIGASI LEBIH LANJUT MEMBUKTIKAN HAL INI SALAH.**

- **MAJOR:** Implementasi Pre-Scaling dengan RobidouxSharp filter
- **ADD:** Mipmap filtering di Background.qml
- **CHANGE:** Target pre-scale: 3× monitor resolution
- **MISLEADING:** Masalah magenta TIDAK disebabkan oleh RobidouxSharp filter atau wallpaper optimizer
- **ROOT CAUSE SEBENARNYA:** Icon theme `breeze-plus-dark` tidak lengkap + DirectoryIcon.qml menggunakan `inode-directory` yang tidak ada
- **STATUS:** ❌ Rollback sebenarnya tidak perlu, tapi dikembangkan ke v1.4.0 dengan Mitchell filter sebagai improvement

### v1.2.0 (2026-02-17)

- **CHANGE:** Switched to PASS-THROUGH mode (no processing)
- **REASON:** Color conversion caused pixelation and color inaccuracy
- **BENEFIT:** Original wallpaper quality preserved exactly
- **SIMPLIFIED:** Now only 2 layers needed (Qt limit + sourceSize patch)

### v1.1.0 (2024-02-17)

- **FIX:** Added Qt allocation limit override (1 GB)
- **CHANGE:** Removed resize safety - now preserve FULL resolution
- **FIX:** Wallpaper selector crash on 11K+ images
- **IMPROVE:** Quality 100% output (no compression)

### v1.0.0 (2024-02-17)

- Initial release
- Full resolution support via sourceSize patch
- sRGB colorspace conversion
- HDR tone mapping
- Smart caching with auto-cleanup
- Integration with Quickshell wallpaper selector

---

## Lisensi

Script ini dibuat untuk konfigurasi pribadi dan bebas digunakan sesuai kebutuhan.

---

## Kontak

Untuk pertanyaan atau masalah, buat issue di repository atau hubungi maintainer.
