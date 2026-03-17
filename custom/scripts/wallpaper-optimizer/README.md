# Wallpaper Optimizer for Qt Quick

**Lokasi:** `~/.config/hypr/custom/scripts/wallpaper-optimizer/`

## Cara Kerja

Sistem ini **100% otomatis** - tidak perlu command manual:

1. **Hook terintegrasi** di `switchwall.sh` (baris 16-17, 195)
2. **Background.qml ter-patch** untuk full resolution
3. Setiap ganti wallpaper via Quickshell selector → otomatis di-optimasi

## Apa yang Dilakukan

1. **Preserve resolusi penuh** - Tidak ada downscale
2. **Convert ke sRGB** - Warna akurat, tidak gelap
3. **HDR tone mapping** - Jika wallpaper HDR
4. **Auto cleanup** - Cache maks 20 file, backup maks 5 file

## File Structure

```
~/.config/hypr/custom/scripts/
├── wallpaper-optimizer.sh              # CLI tool (optional)
└── wallpaper-optimizer/
    ├── optimize-wallpaper.sh           # Core optimizer
    ├── optimizer-hook.sh               # Hook untuk switchwall.sh
    ├── patch-background.sh             # Background.qml patcher
    ├── patch_background_qml.py         # Python patcher
    └── README.md
```

## Perubahan Sistem

| File | Perubahan |
|------|-----------|
| `switchwall.sh` | +2 baris hook (baris 16-17, 195) |
| `Background.qml` | sourceSize patched (baris 176) |
| `switchwall.sh.backup` | Backup original |

## Command (Opsional)

```bash
# Cek status
~/.config/hypr/custom/scripts/wallpaper-optimizer.sh status

# Unpatch (kembalikan ke asli)
~/.config/hypr/custom/scripts/wallpaper-optimizer.sh unpatch

# Bersihkan cache
~/.config/hypr/custom/scripts/wallpaper-optimizer.sh cache-clear

# Restore switchwall.sh original
cp ~/.config/quickshell/ii/scripts/colors/switchwall.sh.backup \
   ~/.config/quickshell/ii/scripts/colors/switchwall.sh
```

## Notes

- Restart quickshell setelah patch: `pkill -f 'qs -c ii' && qs -c ii &`
- Hook aman - jika optimizer-hook.sh tidak ada, sistem tetap jalan normal
- Cache disimpan di `~/.cache/hypr/wallpaper-optimizer/processed/`
