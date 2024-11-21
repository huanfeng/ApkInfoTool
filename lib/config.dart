import 'dart:developer';

import 'package:shared_preferences/shared_preferences.dart';

class Config {
  static String _aapt2Path = "";
  static String _adbPath = "";
  static String _apksignerPath = "";

  static const KEY_AAPT2_PATH = "aapt2_path";
  static const KEY_ADB_PATH = "adb_path";
  static const KEY_APKSIGNER_PATH = "apksigner_path";

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

  static void loadConfig() {
    final prefs = gPrefs;
    aapt2Path = prefs.getString(KEY_AAPT2_PATH) ?? aapt2Path;
    adbPath = prefs.getString(KEY_ADB_PATH) ?? adbPath;
    apksignerPath = prefs.getString(KEY_APKSIGNER_PATH) ?? apksignerPath;
    log("aapt2Path=$aapt2Path, adbPath=$adbPath, apksignerPath=$apksignerPath");
  }
}
