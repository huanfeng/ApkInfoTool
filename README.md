<p align="center">
  <img src="assets/image/icon_512.png" width="120" alt="APK Info Tool">
</p>

<h1 align="center">APK Info Tool</h1>

<p align="center">
  <strong>轻量、强大的跨平台 Android 应用包解析工具</strong><br>
  拖拽即用，简单直观
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

## 功能亮点

📦 **全格式支持** — APK / XAPK / APKM / APKS 一网打尽，自动识别分包结构与 OBB 文件

🔍 **深度解析** — 包名、版本、SDK 版本、权限清单、Activity、签名信息、文件哈希（MD5/SHA1）

📋 **分包信息展示** — XAPK/APKM/APKS 的 Split APK 列表与 OBB 文件列表一目了然

🎨 **图标预览与导出** — 完美渲染 PNG / WebP / XML 自适应图标（含渐变矢量图标），支持多候选图标切换，导出为 PNG / SVG / 原始文件，图标显示大小可配置（2行/3行）

📝 **文件重命名** — 支持对 APK / XAPK / APKM / APKS 文件按规则重命名

🚀 **一键 ADB 安装** — 自动处理 Split APK 安装与 OBB 推送

⬇️ **一键依赖下载** — 在设置中直接下载 adb / aapt2 / apksigner，无需手动安装 Android SDK

🧩 **内置解析引擎** — 纯 Dart 实现的 APK 解析器，无需依赖 aapt2，解析更快，兼容混淆 APK

🌍 **多语言 & 主题** — 支持简体中文、繁體中文、English、日本語、한국어，主题颜色可自定义

## 界面预览

<!-- 在此放置应用截图或 GIF 动图 -->
<!-- <p align="center">
  <img src="screenshots/main.png" width="800" alt="主界面">
</p> -->

> 截图即将更新，欢迎下载体验！

## 安装

### 包管理器安装

**Windows — Scoop（推荐）**

```bash
scoop bucket add huanfeng https://github.com/huanfeng/scoop-bucket
scoop install apk_info_tool
```

**macOS — Homebrew**

```bash
brew install --cask huanfeng/homebrew-tap/apk-info-tool
```

### 手动下载

从 [Releases](https://github.com/huanfeng/ApkInfoTool/releases/latest) 页面下载对应平台的安装包：

| 平台 | 格式 | 说明 |
|------|------|------|
| Windows | `.exe` | 安装程序 |
| Windows | `.zip` | 解压即用 |
| macOS | `.dmg` | 磁盘映像 |
| Linux | `.AppImage` | 可执行文件 |

## 内置 APK 解析引擎

v2.0 起默认启用**内置解析引擎**，纯 Dart 实现，无需安装任何外部工具即可解析 APK：

- 二进制 XML 解压与 AndroidManifest.xml 结构化解析
- resources.arsc 资源表完整解析（字符串池、资源值、类型配置等）
- 支持 BCP-47 packed 语言码（如 `ast`、`sr-Latn`、`zh-Hans-CN`）
- 混淆 APK 深度兼容（无效路径过滤、非标准属性容错）
- aapt2 dump badging 风格的文本信息输出

> 可在设置中切换 aapt2 与内置引擎。若需签名验证等高级功能，仍需配置 Android SDK 工具。

> 内置解析引擎还在不断完善中，如遇到问题，请进行反馈

## 对比

| 能力 | APK Info Tool | 命令行 aapt | 其他 GUI 工具 |
|------|:---:|:---:|:---:|
| XAPK / APKM / APKS 支持 | ✅ | ❌ | ⚠️ 部分 |
| 自适应图标完整渲染 | ✅ | ❌ | ❌ |
| 内置解析（无需 aapt2） | ✅ | — | ❌ |
| 拖拽即看 | ✅ | ❌ | ✅ |
| 跨平台（Win/Mac/Linux） | ✅ | ✅ | ⚠️ 部分 |
| ADB 一键安装 | ✅ | ❌ | ⚠️ 部分 |
| 图标导出 PNG/SVG | ✅ | ❌ | ❌ |

## 开发构建

本项目使用 [Flutter](https://flutter.dev/) 开发。确保已安装 Flutter SDK，然后执行：

```bash
# 获取依赖
flutter pub get

# 运行代码生成
dart run build_runner build

# 运行调试版本
flutter run

# 构建发布版本
flutter build windows   # Windows
flutter build macos     # macOS
flutter build linux     # Linux
```

## 国际化

应用支持以下语言，语言文件位于 `assets/i18n` 目录：

| 语言 | 代码 |
|------|------|
| 简体中文 | `zh-CN` |
| 繁體中文（香港） | `zh-HK` |
| 繁體中文（台灣） | `zh-TW` |
| English | `en` |
| 日本語 | `ja` |
| 한국어 | `ko` |

## 使用须知

**macOS 平台**
- 因沙箱限制，重命名功能受限，且只能使用内置的 adb/aapt2
- apksigner 依赖 Java Runtime，macOS 版本暂不集成该功能
- 未签署开发者证书，首次运行需手动信任：`系统设置 → 隐私与安全性 → 仍要打开`

**Linux 平台**
- 未经完整测试，如遇问题欢迎 [提交 Issue](https://github.com/huanfeng/ApkInfoTool/issues)

**图标显示**
- XML 格式的自适应图标渲染效果可能与实际设备上有轻微差异

## Android SDK 工具（可选）

内置解析引擎已可满足大部分需求。如需 ADB 安装或签名验证功能，可在应用 **设置** 中一键下载所需工具（adb / aapt2 / apksigner），无需手动安装 Android SDK。

## 贡献

欢迎参与贡献！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交改动 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 提交 Pull Request

## 致谢

- 应用图标使用 [AppIcon Forge](https://github.com/zhangyu1818/appicon-forge) 制作

## 开源协议

本项目基于 [MIT License](LICENSE) 开源。
