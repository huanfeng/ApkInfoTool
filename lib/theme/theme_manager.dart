import 'package:flutter/material.dart';

import '../config.dart';

class ThemeManager extends ChangeNotifier {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;
  ThemeManager._internal();

  ThemeData get themeData => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Config.themeColor),
        useMaterial3: true,
      );

  void updateThemeColor(Color color) {
    Config.themeColor = color;
    notifyListeners();
  }
}
