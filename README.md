# APK Info Tool

[简体中文](README.md) | [English](README_en.md)

一个用于查看 APK/XAPK/APKM/APKS 文件信息并进行安装的简单工具。

## 功能特性

- 查看 APK/XAPK/APKM/APKS 基本信息（包名、版本、SDK、权限等）
- XAPK/APKM/APKS 分包信息展示（Split APK 列表、OBB 列表）
- 图标显示（PNG/WebP，XAPK/APKM/APKS 支持 icon.png 或 manifest 指定路径）
- 文件重命名（APK/XAPK/APKM/APKS）
- 通过 ADB 安装（支持 split APK 与 OBB 推送）

## 已知问题
- 某些 APK/XAPK/APKM/APKS 解析速度慢：使用 aapt2 解析 base.apk，速度依赖于 aapt2 的性能表现。
- 某些 APK 不显示图标：目前仅支持 png 和 webp 格式的图标，xml 格式的图标目前不支持显示。
- macOS 因沙箱原因，有以下问题
  - 重命名功能无法工作
  - 无法指定外部的 adb 和 aapt2，只能使用内置的
- macOS 平台 因 apksigner 依赖 Java Runtime, 所以没有做集成，暂时屏蔽了功能入口
- macOS 平台因没有开发者账号, 签名为调试版本, 需要手动信任
- Linux 环境未经过实测，欢迎反馈问题。

## 系统要求

### Android SDK 工具

本工具依赖以下 Android SDK 组件：

- **Android Build Tools**：用于解析和分析 APK 文件
  - 需要 `aapt2`（用于解析 APK 信息）
  - 需要 `apksigner`（可选，用于验证 APK 签名）
- **Android Debug Bridge (adb)**：用于安装和卸载 APK

你可以通过以下方式获取这些工具：

1. 安装 Android Studio 并使用 SDK Manager 下载
2. 或直接下载 [Android Command Line Tools](https://developer.android.com/studio#command-tools)，然后使用 `sdkmanager` 安装：
   ```bash
   sdkmanager "build-tools;35.0.0" "platform-tools"
   ```

请确保这些工具在系统的环境变量中可访问并在设置指定路径。

## 下载安装

从 [Releases](https://github.com/huanfeng/ApkInfoTool/releases) 页面下载对应平台的安装包：

- Windows: `.exe` 安装包
- Windows: `.zip` 压缩包, 解压后运行
- macOS: `.dmg` 安装包
- Linux: `.AppImage` 可执行文件

### Windows Scoop 安装

```bash
scoop bucket add huanfeng https://github.com/huanfeng/scoop-bucket
scoop install apk_info_tool
```

## 开发构建

本项目使用 Flutter 开发。确保已安装 Flutter SDK 后,执行：

```bash
# 获取依赖
flutter pub get
# 运行代码生成
dart run build_runner build
# 运行调试版本
flutter run
# 构建发布版本
flutter build macos # macOS
flutter build windows # Windows
flutter build linux # Linux
```

## 国际化

本应用支持以下语言：

- 简体中文
- English

语言文件位于 `assets/i18n` 目录下。

## 贡献代码

1. Fork 本仓库
2. 创建您的特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交您的改动 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 提交 Pull Request

## 致谢
- 本应用 ICON 使用 [AppIcon Forge](https://github.com/zhangyu1818/appicon-forge) 工具制作

## 开源协议

本项目采用 MIT 协议开源。

