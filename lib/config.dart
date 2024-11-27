import 'package:apk_info_tool/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Config {
  static String _aapt2Path = "";
  static String _apksignerPath = "";
  static String _adbPath = "";
  static bool _enableSignature = false;
  static bool _enableDebug = false;
  static int _maxLines = 6;
  static int _themeColor = Colors.blue.value;
  static double _titleWidth = 100;

  static const kKeyAapt2PathKey = "aapt2_path";
  static const kKeyApksignerPathKey = "apksigner_path";
  static const kKeyAdbPathKey = "adb_path";
  static const kKeyEnableSignatureKey = "enable_signature";
  static const kKeyEnableDebugKey = "enable_debug";
  static const kKeyMaxLinesKey = "max_lines";
  static const kKeyThemeColorKey = "theme_color";
  static const kKeyTitleWidthKey = "title_width";

  static late SharedPreferences gPrefs;

  static Future<void> init() async {
    gPrefs = await SharedPreferences.getInstance();
  }

  static String get aapt2Path => _aapt2Path;

  static set aapt2Path(String value) {
    _aapt2Path = value.trim();
    gPrefs.setString(kKeyAapt2PathKey, aapt2Path);
  }

  static String get apksignerPath => _apksignerPath;

  static set apksignerPath(String value) {
    _apksignerPath = value.trim();
    gPrefs.setString(kKeyApksignerPathKey, apksignerPath);
  }

  static String get adbPath => _adbPath;

  static set adbPath(String value) {
    _adbPath = value.trim();
    gPrefs.setString(kKeyAdbPathKey, adbPath);
  }

  static bool get enableSignature => _enableSignature;

  static set enableSignature(bool value) {
    _enableSignature = value;
    gPrefs.setBool(kKeyEnableSignatureKey, value);
  }

  static bool get enableDebug => _enableDebug;

  static set enableDebug(bool value) {
    _enableDebug = value;
    gPrefs.setBool(kKeyEnableDebugKey, value);
  }

  static int get maxLines => _maxLines;

  static set maxLines(int value) {
    _maxLines = value;
    gPrefs.setInt(kKeyMaxLinesKey, value);
  }

  static Color get themeColor => Color(_themeColor);

  static set themeColor(Color value) {
    _themeColor = value.value;
    gPrefs.setInt(kKeyThemeColorKey, value.value);
  }

  static double get titleWidth => _titleWidth;

  static set titleWidth(double value) {
    _titleWidth = value;
    gPrefs.setDouble(kKeyTitleWidthKey, value);
  }

  static Future<void> loadConfig() async {
    final prefs = gPrefs;
    aapt2Path = prefs.getString(kKeyAapt2PathKey) ?? aapt2Path;
    apksignerPath = prefs.getString(kKeyApksignerPathKey) ?? apksignerPath;
    adbPath = prefs.getString(kKeyAdbPathKey) ?? adbPath;
    _enableSignature =
        prefs.getBool(kKeyEnableSignatureKey) ?? _enableSignature;
    _enableDebug = prefs.getBool(kKeyEnableDebugKey) ?? _enableDebug;
    _maxLines = prefs.getInt(kKeyMaxLinesKey) ?? _maxLines;
    _themeColor = prefs.getInt(kKeyThemeColorKey) ?? _themeColor;
    _titleWidth = prefs.getDouble(kKeyTitleWidthKey) ?? _titleWidth;

    await LoggerInit.initLogger();

    log.info(
        "loadConfig: aapt2Path=$aapt2Path, apksignerPath=$apksignerPath, adbPath=$adbPath");
    log.info(
        "loadConfig: enableSignature=$_enableSignature, enableDebug=$_enableDebug, maxLines=$_maxLines, themeColor=$_themeColor, titleWidth=$_titleWidth");
  }
}
