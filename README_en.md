# APK Info Tool

[简体中文](README.md) | [English](README_en.md)

A simple tool for viewing APK file information.

## Features

- View APK basic information
- APK renaming
- APK file installation

## System Requirements

### Android SDK Tools

This tool depends on the following Android SDK components:

- **Android Build Tools**: For parsing and analyzing APK files
  - Requires `aapt2` (for parsing APK information)
  - Requires `apksigner` (for verifying APK signatures)
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
- macOS: `.dmg` installer
- Linux: `.AppImage` executable

## Development & Building

This project is developed using Flutter. After ensuring Flutter SDK is installed, run:

```bash
# Get dependencies
flutter pub get
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

Language files are located in the `lib/l10n` directory.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License.
