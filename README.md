# APK Info Tool

[English](README.md) | [简体中文](README_zh.md)

A simple tool for viewing APK file information.

## Features

- View basic APK information (package name, app name, version, etc.)
- View supported screen sizes and densities
- View supported CPU architectures
- View list of supported languages
- View list of requested permissions

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

- English
- Simplified Chinese

Language files are located in the `lib/l10n` directory.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License.
