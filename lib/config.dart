import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Config {
  static String _aapt2Path = "";
  static String _adbPath = "";
  static String _apksignerPath = "";
  static bool _enableSignature = true;
  static int _maxLines = 6;
  static int _themeColor = Colors.blue.value;

  static const KEY_AAPT2_PATH = "aapt2_path";
  static const KEY_ADB_PATH = "adb_path";
  static const KEY_APKSIGNER_PATH = "apksigner_path";
  static const KEY_ENABLE_SIGNATURE = "enable_signature";
  static const KEY_MAX_LINES = "max_lines";
  static const KEY_THEME_COLOR = "theme_color";

  static late SharedPreferences gPrefs;

  static Future<void> init() async {
    gPrefs = await SharedPreferences.getInstance();
  }

  static String get aapt2Path => _aapt2Path;

  static set aapt2Path(String value) {
    _aapt2Path = value.trim();
    gPrefs.setString(KEY_AAPT2_PATH, aapt2Path);
  }

  static String get adbPath => _adbPath;

  static set adbPath(String value) {
    _adbPath = value.trim();
    gPrefs.setString(KEY_ADB_PATH, adbPath);
  }

  static String get apksignerPath => _apksignerPath;

  static set apksignerPath(String value) {
    _apksignerPath = value.trim();
    gPrefs.setString(KEY_APKSIGNER_PATH, apksignerPath);
  }

  static bool get enableSignature => _enableSignature;

  static set enableSignature(bool value) {
    _enableSignature = value;
    gPrefs.setBool(KEY_ENABLE_SIGNATURE, value);
  }

  static int get maxLines => _maxLines;

  static set maxLines(int value) {
    _maxLines = value;
    gPrefs.setInt(KEY_MAX_LINES, value);
  }

  static Color get themeColor => Color(_themeColor);

  static set themeColor(Color value) {
    _themeColor = value.value;
    gPrefs.setInt(KEY_THEME_COLOR, value.value);
  }

  static void loadConfig() {
    final prefs = gPrefs;
    aapt2Path = prefs.getString(KEY_AAPT2_PATH) ?? aapt2Path;
    adbPath = prefs.getString(KEY_ADB_PATH) ?? adbPath;
    apksignerPath = prefs.getString(KEY_APKSIGNER_PATH) ?? apksignerPath;
    _enableSignature = prefs.getBool(KEY_ENABLE_SIGNATURE) ?? _enableSignature;
    _maxLines = prefs.getInt(KEY_MAX_LINES) ?? _maxLines;
    _themeColor = prefs.getInt(KEY_THEME_COLOR) ?? _themeColor;
    
    log("aapt2Path=$aapt2Path, adbPath=$adbPath, apksignerPath=$apksignerPath");
    log("enableSignature=$_enableSignature, maxLines=$_maxLines, themeColor=$_themeColor");
  }
}
