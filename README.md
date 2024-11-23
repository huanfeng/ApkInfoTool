# APK Info Tool

[简体中文](README.md) | [English](README_en.md)

一个用于查看 APK 文件信息的简单工具。

## 功能特性

- 查看 APK 基本信息
- APK 重命名 
- APK 文件安装

## 系统要求

### Android SDK 工具

本工具依赖以下 Android SDK 组件：

- **Android Build Tools**：用于解析和分析 APK 文件
  - 需要 `aapt2`（用于解析 APK 信息）
  - 需要 `apksigner`（用于验证 APK 签名）
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
- macOS: `.dmg` 安装包
- Linux: `.AppImage` 可执行文件

## 开发构建

本项目使用 Flutter 开发。确保已安装 Flutter SDK 后,执行：

```bash
# 获取依赖
flutter pub get
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

语言文件位于 `lib/l10n` 目录下。

## 贡献代码

1. Fork 本仓库
2. 创建您的特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交您的改动 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 提交 Pull Request

## 开源协议

本项目采用 MIT 协议开源。
