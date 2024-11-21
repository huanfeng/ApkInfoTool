import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

import 'config.dart';
import 'utils/log.dart';

Future<ApkInfo?> getApkInfo(String apk) async {
  log("getApkInfo: apk=$apk start");
  final aapt = Config.aapt2Path;

  final start = DateTime.now();
  final apkInfo = ApkInfo();
  apkInfo.apkPath = apk;
  apkInfo.apkSize = File(apk).lengthSync();

  try {
    var result = await Process.run(
      aapt,
      ['dump', 'badging', apk],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(
      const Duration(seconds: 120),
      onTimeout: () {
        throw TimeoutException('Parse timeout');
      },
    );

    final end = DateTime.now();
    var exitCode = result.exitCode;
    final cost = end.difference(start).inMilliseconds;
    log("getApkInfo: end exitCode=$exitCode, cost=${cost}ms");

    if (exitCode == 0) {
      parseApkInfoFromOutput(result.stdout.toString(), apkInfo);

      // 如果启用了签名检查，获取签名信息
      if (Config.enableSignature) {
        try {
          final signInfo = await getSignatureInfo(apk);
          apkInfo.signatureInfo = signInfo;
        } catch (e) {
          log("获取签名信息失败: $e");
          apkInfo.signatureInfo = "获取签名信息失败: $e";
        }
      }

      // 获取图标
      try {
        apkInfo.mainIconImage = await apkInfo.loadIcon();
      } catch (e) {
        log("获取图标失败: $e");
      }

      return apkInfo;
    }
  } on TimeoutException {
    log("getApkInfo: timeout");
  } catch (e) {
    log("getApkInfo: error=$e");
  }

  return null;
}

Future<String> getSignatureInfo(String apkPath) async {
  final apksigner = Config.apksignerPath;
  if (apksigner.isEmpty) {
    throw Exception('请先设置 apksigner 路径');
  }

  try {
    final result = await Process.run(
      apksigner,
      ['verify', '--print-certs', '--verbose', apkPath],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    if (result.exitCode == 0) {
      return result.stdout.toString();
    } else {
      throw Exception('获取签名失败: ${result.stderr}');
    }
  } catch (e) {
    log('获取签名信息失败: $e');
    rethrow;
  }
}

void parseApkInfoFromOutput(String output, ApkInfo apkInfo) {
  final lines = output.split("\n");
  for (final (index, item) in lines.indexed) {
    log("[$index] $item");
    apkInfo.parseLine(item);
  }
  log("apkInfo=$apkInfo");
}

final _kNoneSingleQuotePattern = RegExp(r"[^']");

extension StringExt on String {
  // 去除前后的单引号
  String trimSQ() {
    final start = indexOf(_kNoneSingleQuotePattern);
    final end = lastIndexOf(_kNoneSingleQuotePattern);
    return substring(start < 0 ? 0 : start, end < 0 ? length : end + 1);
  }
}

class ApkInfo {
  String apkPath = "";
  int apkSize = 0;

  String? packageName;
  int? versionCode;
  String? versionName;
  String? platformBuildVersionName;
  int? platformBuildVersionCode;
  int? compileSdkVersion;
  String? compileSdkVersionCodename;
  int? sdkVersion;
  int? targetSdkVersion;
  String? label;
  String? mainIconPath; // 主图标路径
  Image? mainIconImage;
  Map<String, String> labels = {};
  List<String> usesPermissions = [];
  Map<String, String> icons = {};
  Component application = Component();
  List<Component> launchableActivity = [];
  List<String> userFeatures = [];
  List<String> userFeaturesNotRequired = [];
  List<String> userImpliedFeatures = [];
  List<String> supportsScreens = [];
  List<String> locales = [];
  List<String> densities = [];
  bool? supportsAnyDensity;
  List<String> nativeCodes = [];

  List<String> others = [];
  String signatureInfo = "";

  (String, String) parseToKeyValue(String line, String separator) {
    final pos = line.indexOf(separator);
    if (pos != -1) {
      final key = line.substring(0, pos).trim();
      final value = line.substring(pos + 1).trim();
      return (key, value);
    }
    return (line.trim(), "");
  }

  (String, String) parseLineToKeyValue(String line) {
    return parseToKeyValue(line, ":");
  }

  (String, String) parseValueToKeyValue(String line) {
    return parseToKeyValue(line, "=");
  }

  String? parseString(String line) {
    final items = line.split(":");
    if (items.length == 2) {
      return items[1].trim();
    } else {
      others.add(line);
    }
    return null;
  }

  int? parseInt(String value) {
    return int.tryParse(value.trimSQ());
  }

  String parseValueForName(String text) {
    final (_, value) = parseValueToKeyValue(text);
    return value.trimSQ();
  }

  void parseLine(String line) {
    final (key, value) = parseLineToKeyValue(line);
    switch (key) {
      case "package":
        parsePackage(value);
        break;
      case "sdkVersion":
      case "minSdkVersion":
        sdkVersion = parseInt(value);
        break;
      case "targetSdkVersion":
        targetSdkVersion = parseInt(value);
        break;
      case "application-label":
        label = value.trimSQ();
        break;
      case "uses-permission":
        usesPermissions.add(parseValueForName(value));
        break;
      case "application":
        parseComponent(value, application);
        // 从application中获取主图标
        if (mainIconPath == null && application.icon != null) {
          mainIconPath = application.icon;
        }
        break;
      case "launchable-activity":
        final component = Component();
        parseComponent(value, component);
        launchableActivity.add(component);
        // 如果没有主图标且launchable-activity有图标，则使用它
        if (mainIconPath == null && component.icon != null) {
          mainIconPath = component.icon;
        }
        break;
      case "supports-screens":
        parseStringList(value, supportsScreens);
        break;
      case "locales":
        parseStringList(value, locales);
        break;
      case "densities":
        parseStringList(value, densities);
        break;
      case "supports-any-density":
        supportsAnyDensity = value.trimSQ() == "true";
        break;
      case "native-code":
        parseStringList(value, nativeCodes);
        break;
      default:
        {
          if (key.startsWith("application-label-")) {
            labels[key.substring("application-label-".length + 1)] =
                value.trimSQ();
          } else if (key.startsWith("application-icon-")) {
            icons[key.substring("application-icon-".length + 1)] =
                value.trimSQ();
          } else {
            others.add(line);
          }
          break;
        }
    }
  }

  void parsePackage(String text) {
    final items = text.split(" ");
    for (final item in items) {
      final (key, value) = parseValueToKeyValue(item);
      switch (key) {
        case "name":
          packageName = value.trimSQ();
          break;
        case "versionCode":
          versionCode = parseInt(value);
          break;
        case "versionName":
          versionName = value.trimSQ();
          break;
        case "platformBuildVersionName":
          platformBuildVersionName = value.trimSQ();
          break;
        case "platformBuildVersionCode":
          platformBuildVersionCode = parseInt(value);
          break;
        case "compileSdkVersion":
          compileSdkVersion = parseInt(value);
          break;
        case "compileSdkVersionCodename":
          compileSdkVersionCodename = value.trimSQ();
          break;
      }
    }
  }

  void parseComponent(String value, Component component) {
    final items = value.split(" ");
    for (final item in items) {
      final (key, value) = parseValueToKeyValue(item);
      switch (key) {
        case "name":
          component.name = value.trimSQ();
          break;
        case "label":
          component.label = value.trimSQ();
          break;
        case "icon":
          component.icon = value.trimSQ();
          break;
      }
    }
  }

  void parseStringList(String value, List<String> out) {
    final items = value.split(" ");
    for (final item in items) {
      out.add(item.trimSQ());
    }
  }

  /// 加载APK图标
  /// 返回图标的字节数据，如果加载失败返回null
  Future<Image?> loadIcon() async {
    if (mainIconPath == null || apkPath.isEmpty) {
      return null;
    }

    final iconPath = mainIconPath!;

    try {
      if (iconPath.endsWith('.png') ||
          iconPath.endsWith('.webp') ||
          iconPath.endsWith('.jpg')) {
        final inputStream = InputFileStream(apkPath);
        final archive = ZipDecoder().decodeBuffer(inputStream);
        final iconFile = archive.findFile(iconPath);

        if (iconFile != null) {
          // 只读取图标文件的内容
          final codec =
              await instantiateImageCodec(iconFile.content as Uint8List);
          final frame = await codec.getNextFrame();
          return frame.image;
        } else {
          log('找不到图标文件: $iconPath');
        }
      } else if (iconPath.endsWith('.xml')) {
        // TODO: 处理XML格式的图标
        log('暂不支持XML格式的图标: $iconPath');
        return null;
      }
    } catch (e) {
      log('加载图标失败: $e');
    }
    return null;
  }

  @override
  String toString() {
    return 'ApkInfo{apkPath: $apkPath, apkSize: $apkSize, packageName: $packageName, versionCode: $versionCode, versionName: $versionName, platformBuildVersionName: $platformBuildVersionName, platformBuildVersionCode: $platformBuildVersionCode, compileSdkVersion: $compileSdkVersion, compileSdkVersionCodename: $compileSdkVersionCodename, sdkVersion: $sdkVersion, targetSdkVersion: $targetSdkVersion, label: $label, mainIcon: $mainIconPath, labels: $labels, usesPermissions: $usesPermissions, icons: $icons, application: $application, launchableActivity: $launchableActivity, userFeatures: $userFeatures, userFeaturesNotRequired: $userFeaturesNotRequired, userImpliedFeatures: $userImpliedFeatures, supportsScreens: $supportsScreens, locales: $locales, densities: $densities, supportsAnyDensity: $supportsAnyDensity, nativeCodes: $nativeCodes, others: $others, signatureInfo: $signatureInfo}';
  }

  void reset() {
    apkPath = "";
    apkSize = 0;
    packageName = null;
    versionCode = null;
    versionName = null;
    platformBuildVersionName = null;
    platformBuildVersionCode = null;
    compileSdkVersion = null;
    compileSdkVersionCodename = null;
    sdkVersion = null;
    targetSdkVersion = null;
    label = null;
    mainIconPath = null;
    mainIconImage = null;
    labels.clear();
    usesPermissions.clear();
    icons.clear();
    application = Component();
    launchableActivity.clear();
    userFeatures.clear();
    userFeaturesNotRequired.clear();
    userImpliedFeatures.clear();
    supportsScreens.clear();
    locales.clear();
    densities.clear();
    supportsAnyDensity = null;
    nativeCodes.clear();
    others.clear();
    signatureInfo = "";
  }
}

class Component {
  String? name;
  String? label;
  String? icon;

  Component({this.name, this.label, this.icon});

  @override
  String toString() {
    return 'Component{name: $name, label: $label, icon: $icon}';
  }
}
