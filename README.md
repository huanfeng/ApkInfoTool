# APK Info Tool

[简体中文](README.md) | [English](README_en.md)

一个用于查看 APK 文件信息的简单工具。

## 功能特性

- 查看 APK 基本信息(包名、应用名称、版本等)
- 查看 APK 支持的屏幕尺寸和密度
- 查看 APK 支持的 CPU 架构
- 查看 APK 支持的语言列表
- 查看 APK 申请的权限列表

## 下载安装

从 [Releases](https://github.com/huanfeng/ApkInfoTool/releases) 页面下载对应平台的安装包:

- Windows: `.exe` 安装包
- macOS: `.dmg` 安装包
- Linux: `.AppImage` 可执行文件

## 开发构建

本项目使用 Flutter 开发。确保已安装 Flutter SDK 后,执行:

```bash
#获取依赖
flutter pub get
#运行调试版本
flutter run
#构建发布版本
flutter build macos # macOS
flutter build windows # Windows
flutter build linux # Linux
```

## 国际化

本应用支持以下语言:

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
