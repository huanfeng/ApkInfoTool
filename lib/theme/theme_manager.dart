import 'dart:io';

import 'package:apk_info_tool/config.dart';
import 'package:apk_info_tool/gen/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class ThemeState {
  final int themeColor;

  const ThemeState({required this.themeColor});

  ThemeData get themeData => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Color(themeColor)),
        useMaterial3: true,
        fontFamily: getFontFamily(),
      );
}

class ThemeManager extends Notifier<ThemeState> {
  @override
  ThemeState build() => ThemeState(themeColor: Config.themeColor.value);

  void updateThemeColor(Color color) {
    state = ThemeState(themeColor: color.value);
    Config.themeColor.updateValue(color.value);
  }
}

final themeManagerProvider =
    NotifierProvider<ThemeManager, ThemeState>(ThemeManager.new);
