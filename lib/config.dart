import 'dart:developer';

import 'package:shared_preferences/shared_preferences.dart';

class Config {
  static String aapt2Path = "";
  static String adbPath = "";

  static const KEY_AAPT2_PATH = "aapt2_path";
  static const KEY_ADB_PATH = "adb_path";

  static void loadConfig(SharedPreferences prefs) {
    aapt2Path = prefs.getString(KEY_AAPT2_PATH) ?? aapt2Path;
    adbPath = prefs.getString(KEY_ADB_PATH) ?? adbPath;
    log("aapt2Path=$aapt2Path, adbPath=$adbPath");
  }
}
