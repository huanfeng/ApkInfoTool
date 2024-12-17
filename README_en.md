# APK Info Tool

[简体中文](README.md) | [English](README_en.md)

A simple tool for viewing APK file information and installation.

## Features

- View APK basic information
- APK renaming
- APK file installation

## Known Issues
- Slow parsing of certain APKs: This tool uses aapt2 as the parsing tool, and speed depends on aapt2's performance.
- Some APK icons are not displayed: Currently only supports PNG and WebP format icons. XML format icons are not supported yet, will try to optimize in the future.
- Due to sandbox restrictions on macOS, there are the following issues:
  - Rename function does not work
  - Cannot specify external adb and aapt2, can only use built-in ones
- On macOS platform, due to apksigner's dependency on Java Runtime, integration is not done and feature entry is temporarily disabled
- On macOS platform, due to lack of developer account, signature is debug version, manual trust is required
- Linux environment has not been fully tested, feedback is welcome.

## System Requirements

### Android SDK Tools

This tool depends on the following Android SDK components:

- **Android Build Tools**: For parsing and analyzing APK files
  - Requires `aapt2` (for parsing APK information)
  - Requires `apksigner` (optional, for verifying APK signatures)
- **Android Debug Bridge (adb)**: For installing and uninstalling APKs

You can obtain these tools by:

1. Installing Android Studio and downloading through SDK Manager
2. Or downloading [Android Command Line Tools](https://developer.android.com/studio#command-tools) directly, then installing using `sdkmanager`:
   ```bash
   sdkmanager "build-tools;35.0.0" "platform-tools"
   ```

Please ensure these tools are accessible in your system's environment variables and specify their paths in settings.

## Download & Installation

Download the installation package for your platform from the [Releases](https://github.com/huanfeng/ApkInfoTool/releases) page:

- Windows: `.exe` installer
- Windows: `.zip` archive, run after extracting
- macOS: `.dmg` installer
- Linux: `.AppImage` executable

## Development & Building

This project is developed using Flutter. After ensuring Flutter SDK is installed, run:

```bash
# Get dependencies
flutter pub get
# Run code generation
dart run build_runner build
# Run debug version
flutter run
# Build release version
flutter build macos # macOS
flutter build windows # Windows
flutter build linux # Linux
```

## Internationalization

The application supports the following languages:

- Simplified Chinese
- English

Language files are located in the `lib/i18n` directory.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## Acknowledgments
- The application icon was created using [AppIcon Forge](https://github.com/zhangyu1818/appicon-forge)

## License

This project is licensed under the MIT License.
