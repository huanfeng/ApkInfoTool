import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// 文件关联管理类
class FileAssociationManager {
  /// 检查当前平台是否支持文件关联设置
  static bool get isSupported => Platform.isWindows || Platform.isMacOS;

  /// 打开系统默认应用设置
  ///
  /// 尝试打开默认应用设置页面
  /// 如果无法打开，会抛出 [UnsupportedError]
  static Future<void> openDefaultAppsSettings() async {
    if (!isSupported) {
      throw UnsupportedError(
          'This feature is only supported on Windows and macOS');
    }

    final uri = Uri.parse(Platform.isWindows
        ? 'ms-settings:defaultapps'
        : 'x-apple.systempreferences:com.apple.preferences.extensions');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      throw UnsupportedError('Cannot launch settings URL');
    }
  }
}
