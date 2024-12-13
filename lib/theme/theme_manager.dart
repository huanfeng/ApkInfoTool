import 'dart:io';

import 'package:apk_info_tool/config.dart';
import 'package:apk_info_tool/gen/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ThemeManager extends ChangeNotifier {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;
  ThemeManager._internal();

  int _themeColor = Config.themeColor.value;

  int get themeColor => _themeColor;

  ThemeData get themeData => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Color(themeColor)),
        useMaterial3: true,
        fontFamily: getFontFamily(),
      );

  void updateThemeColor(Color color) {
    _themeColor = color.value;
    Config.themeColor.updateValue(color.value);
    notifyListeners();
  }

  String? getFontFamily() {
    if (Platform.isWindows) {
      final locale = LocaleSettings.currentLocale;
      return switch (locale) {
        AppLocale.ja => 'Yu Gothic UI',
        AppLocale.ko => 'Malgun Gothic',
        AppLocale.zhCn => 'Microsoft YaHei UI',
        AppLocale.zhHk || AppLocale.zhTw => 'Microsoft JhengHei UI',
        _ => 'Segoe UI Variable Display',
      };
    } else {
      return null;
    }
  }
}

final themeManagerProvider = ChangeNotifierProvider((ref) => ThemeManager());
