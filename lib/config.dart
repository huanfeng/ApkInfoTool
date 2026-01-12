import 'dart:async';

import 'package:apk_info_tool/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConfigItem<T> {
  final String key;
  T _value;

  T get value => _value;

  ConfigItem(this.key, this._value);

  Timer? _applyTimer;

  void _applyValue() {
    final value = this._value;
    if (value is String) {
      Config.gPrefs.setString(key, value);
    } else if (value is bool) {
      Config.gPrefs.setBool(key, value);
    } else if (value is int) {
      Config.gPrefs.setInt(key, value);
    } else if (value is double) {
      Config.gPrefs.setDouble(key, value);
    }
  }

  Future<void> updateValue(T value) async {
    this._value = value;
    _applyTimer?.cancel();
    _applyTimer = Timer(const Duration(milliseconds: 100), () {
      _applyTimer = null;
      _applyValue();
    });
  }

  void loadValue() {
    if (_value is String) {
      _value = (Config.gPrefs.getString(key) ?? _value) as T;
    } else if (value is bool) {
      _value = (Config.gPrefs.getBool(key) ?? _value) as T;
    } else if (value is int) {
      _value = (Config.gPrefs.getInt(key) ?? _value) as T;
    } else if (value is double) {
      _value = (Config.gPrefs.getDouble(key) ?? _value) as T;
    }
  }
}

class Config {
  static late SharedPreferences gPrefs;

  static const kLanguageAuto = "auto";
  static const kToolSourceSystem = "system";
  static const kToolSourceBuiltin = "builtin";
  static const kToolSourceCustom = "custom";

  static final aapt2Path = ConfigItem("aapt2_path", "");
  static final apksignerPath = ConfigItem("apksigner_path", "");
  static final adbPath = ConfigItem("adb_path", "");
  static final aapt2Source = ConfigItem("aapt2_source", kToolSourceBuiltin);
  static final apksignerSource =
      ConfigItem("apksigner_source", kToolSourceBuiltin);
  static final adbSource = ConfigItem("adb_source", kToolSourceBuiltin);
  static final downloadDir = ConfigItem("download_dir", "");
  static final enableSignature = ConfigItem("enable_signature", false);
  static final enableHash = ConfigItem("enable_hash", true);
  static final enableDebug = ConfigItem("enable_debug", false);
  static final maxLines = ConfigItem("max_lines", 6);
  static final themeColor = ConfigItem("theme_color", Colors.blue.value);
  static final titleWidth = ConfigItem("title_width", 100.0);
  static final language = ConfigItem("language", kLanguageAuto);

  static final List<ConfigItem> _globalItems = [
    aapt2Path,
    apksignerPath,
    adbPath,
    aapt2Source,
    apksignerSource,
    adbSource,
    downloadDir,
    enableSignature,
    enableHash,
    enableDebug,
    maxLines,
    themeColor,
    titleWidth,
    language
  ];

  static Future<void> init() async {
    gPrefs = await SharedPreferences.getInstance();
  }

  static Future<void> loadConfig() async {
    for (final item in _globalItems) {
      item.loadValue();
    }

    await LoggerInit.initLogger();

    for (final item in _globalItems) {
      log.info("loadConfig: ${item.key}=${item.value}");
    }
  }
}
