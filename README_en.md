<p align="center">
  <img src="assets/image/icon_512.png" width="120" alt="APK Info Tool">
</p>

<h1 align="center">APK Info Tool</h1>

<p align="center">
  <strong>Lightweight yet powerful cross-platform Android package analyzer</strong><br>
  Drag, drop, done — simple and intuitive.
</p>

<p align="center">
  <a href="https://github.com/huanfeng/ApkInfoTool/releases/latest"><img src="https://img.shields.io/github/v/release/huanfeng/ApkInfoTool?style=flat-square&color=28a745" alt="Release"></a>
  <a href="https://github.com/huanfeng/ApkInfoTool/actions/workflows/build.yml"><img src="https://img.shields.io/github/actions/workflow/status/huanfeng/ApkInfoTool/build.yml?style=flat-square" alt="Build"></a>
  <a href="https://github.com/huanfeng/ApkInfoTool/blob/main/LICENSE"><img src="https://img.shields.io/github/license/huanfeng/ApkInfoTool?style=flat-square" alt="License"></a>
  <img src="https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-blue?style=flat-square" alt="Platform">
  <a href="https://github.com/huanfeng/ApkInfoTool/stargazers"><img src="https://img.shields.io/github/stars/huanfeng/ApkInfoTool?style=flat-square" alt="Stars"></a>
</p>

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README_en.md">English</a>
</p>

---

## Highlights

📦 **All Formats** — APK / XAPK / APKM / APKS with automatic split structure and OBB detection

🔍 **Deep Analysis** — Package name, version, SDK levels, permissions, activities, signatures, file hashes (MD5/SHA1)

📋 **Split Package Details** — Clear view of split APK lists and OBB file lists for XAPK/APKM/APKS

🎨 **Icon Preview & Export** — Renders PNG / WebP / XML adaptive icons (including gradient vectors), multi-candidate switching, export as PNG / SVG / raw, configurable icon display size (2 or 3 rows)

📝 **File Renaming** — Rename APK / XAPK / APKM / APKS files by custom rules

🚀 **One-Click ADB Install** — Handles split APK installs and OBB push automatically

⬇️ **One-Click Dependency Download** — Download adb / aapt2 / apksigner directly from Settings, no manual Android SDK setup needed

🧩 **Built-in Parser** — Pure Dart APK parser, no aapt2 dependency needed — faster parsing with obfuscated APK support

🌍 **Multi-Language & Themes** — Simplified Chinese, Traditional Chinese, English, Japanese, Korean; customizable theme colors

## Screenshots

<!-- Add screenshots or GIF demos here -->
<!-- <p align="center">
  <img src="screenshots/main.png" width="800" alt="Main UI">
</p> -->

> Screenshots coming soon — download and try it out!

## Installation

### Package Managers

**Windows — Scoop (Recommended)**

```bash
scoop bucket add huanfeng https://github.com/huanfeng/scoop-bucket
scoop install apk_info_tool
```

**macOS — Homebrew**

```bash
brew install --cask huanfeng/homebrew-tap/apk-info-tool
```

### Manual Download

Grab the latest release for your platform from [Releases](https://github.com/huanfeng/ApkInfoTool/releases/latest):

| Platform | Format | Notes |
|----------|--------|-------|
| Windows | `.exe` | Installer |
| Windows | `.zip` | Portable, run directly |
| macOS | `.dmg` | Disk image |
| Linux | `.AppImage` | Executable |

## Built-in APK Parser

Starting from v2.0, the **built-in parser engine** is enabled by default — a pure Dart implementation that requires no external tools:

- Binary XML decompression and structured AndroidManifest.xml parsing
- Full resources.arsc parsing (string pools, resource values, type configs, etc.)
- BCP-47 packed locale support (e.g., `ast`, `sr-Latn`, `zh-Hans-CN`)
- Deep compatibility with obfuscated APKs (invalid path filtering, non-standard attribute tolerance)
- aapt2 dump badging style text output

> You can switch between aapt2 and the built-in engine in Settings. Advanced features like signature verification still require Android SDK tools.

> The built-in parser is still being actively improved. If you encounter any issues, please provide feedback.

## Comparison

| Capability | APK Info Tool | CLI aapt | Other GUI Tools |
|------------|:---:|:---:|:---:|
| XAPK / APKM / APKS support | ✅ | ❌ | ⚠️ Partial |
| Full adaptive icon rendering | ✅ | ❌ | ❌ |
| Built-in parsing (no aapt2) | ✅ | — | ❌ |
| Drag & drop | ✅ | ❌ | ✅ |
| Cross-platform (Win/Mac/Linux) | ✅ | ✅ | ⚠️ Partial |
| One-click ADB install | ✅ | ❌ | ⚠️ Partial |
| Icon export PNG/SVG | ✅ | ❌ | ❌ |

## Development

This project is built with [Flutter](https://flutter.dev/). With Flutter SDK installed:

```bash
# Get dependencies
flutter pub get

# Run code generation
dart run build_runner build

# Run in debug mode
flutter run

# Build release
flutter build windows   # Windows
flutter build macos     # macOS
flutter build linux     # Linux
```

## Internationalization

The app supports the following languages. Language files are located in `assets/i18n`:

| Language | Code |
|----------|------|
| Simplified Chinese | `zh-CN` |
| Traditional Chinese (HK) | `zh-HK` |
| Traditional Chinese (TW) | `zh-TW` |
| English | `en` |
| Japanese | `ja` |
| Korean | `ko` |

## Platform Notes

**macOS**
- Sandbox restrictions limit the rename feature; only built-in adb/aapt2 can be used
- apksigner requires Java Runtime and is not bundled on macOS
- No developer certificate — first launch requires manual trust: `System Settings → Privacy & Security → Open Anyway`

**Linux**
- Not fully tested — please [open an issue](https://github.com/huanfeng/ApkInfoTool/issues) if you encounter problems

**Icon Display**
- Rendering of XML adaptive icons may differ slightly from the actual device display

## Android SDK Tools (Optional)

The built-in parser covers most use cases. For ADB installation or signature verification, you can download the required tools (adb / aapt2 / apksigner) with one click in the app **Settings** — no manual Android SDK setup needed.

## Contributing

Contributions are welcome!

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## Acknowledgments

- App icon created with [AppIcon Forge](https://github.com/zhangyu1818/appicon-forge)

## License

This project is licensed under the [MIT License](LICENSE).
