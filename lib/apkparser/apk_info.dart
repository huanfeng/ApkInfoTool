import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:apk_info_tool/config.dart';
import 'package:apk_info_tool/gen/strings.g.dart';
import 'package:apk_info_tool/utils/command_tools.dart';
import 'package:apk_info_tool/utils/logger.dart';
import 'package:apk_info_tool/utils/zip_helper.dart';
import 'package:path/path.dart' as path;
import 'xapk_info.dart';

bool _isArchiveApk(String apkPath) {
  final extension = path.extension(apkPath).toLowerCase();
  return extension == '.xapk' || extension == '.apkm';
}

String _archiveTypeFromExtension(String extension) {
  return extension == '.apkm' ? 'APKM' : 'XAPK';
}

String? _findBaseApkEntry(List<String> apkEntries) {
  if (apkEntries.isEmpty) return null;
  for (final entry in apkEntries) {
    final name = path.basename(entry).toLowerCase();
    if (name == 'base.apk' || name.endsWith('/base.apk')) {
      return entry;
    }
  }
  for (final entry in apkEntries) {
    final name = path.basename(entry).toLowerCase();
    if (!name.contains('config.')) {
      return entry;
    }
  }
  return apkEntries.first;
}

Future<ApkInfo?> getApkInfo(String apk) async {
  log.info("getApkInfo: apk=[$apk] start");
  final apkInfo = ApkInfo();
  apkInfo.apkPath = apk;
  apkInfo.apkSize = File(apk).lengthSync();

  // 检查是否为XAPK格式
  if (_isArchiveApk(apk)) {
    final extension = path.extension(apk).toLowerCase();
    log.info("getApkInfo: parsing XAPK/APKM file");
    apkInfo.isXapk = true;
    apkInfo.archiveType = _archiveTypeFromExtension(extension);

    final manifest = await parseXapkManifest(apk);
    final zip = ZipHelper();
    Directory? tempDir;
    String? baseApkPath;
    try {
      if (zip.open(apk)) {
        apkInfo.archiveApks = zip.listFiles(extension: '.apk');
        apkInfo.obbFiles = zip.listFiles(extension: '.obb');

        final baseEntry = _findBaseApkEntry(apkInfo.archiveApks);
        if (baseEntry != null) {
          tempDir = await Directory.systemTemp.createTemp('apk_info_base');
          baseApkPath = path.join(tempDir.path, path.basename(baseEntry));
          final extracted = await zip.extractFile(baseEntry, baseApkPath);
          if (extracted) {
            try {
              final aaptPath = CommandTools.getAapt2Path();
              final result = await Process.run(
                aaptPath,
                ['dump', 'badging', baseApkPath],
                stdoutEncoding: utf8,
                stderrEncoding: utf8,
              ).timeout(
                const Duration(seconds: 120),
                onTimeout: () {
                  throw TimeoutException('Parse timeout');
                },
              );
              if (result.exitCode == 0) {
                final originalPath = apkInfo.apkPath;
                apkInfo.apkPath = baseApkPath;
                parseApkInfoFromOutput(result.stdout.toString(), apkInfo);
                final iconImage = await apkInfo.loadIcon();
                if (iconImage != null) {
                  apkInfo.mainIconImage ??= iconImage;
                }
                apkInfo.apkPath = originalPath;
              }
            } catch (e) {
              log.info("getApkInfo: base APK parse failed: $e");
            }
          }
        }
      }
    } finally {
      zip.close();
      if (tempDir != null && await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }

    if (manifest != null) {
      if (manifest.packageName?.isNotEmpty == true) {
        apkInfo.packageName = manifest.packageName;
      }
      if (manifest.versionCode != null && manifest.versionCode! > 0) {
        apkInfo.versionCode = manifest.versionCode;
      }
      if (manifest.versionName?.isNotEmpty == true) {
        apkInfo.versionName = manifest.versionName;
      }
      if (manifest.minSdkVersion != null && manifest.minSdkVersion! > 0) {
        apkInfo.sdkVersion = manifest.minSdkVersion;
      }
      if (manifest.targetSdkVersion != null && manifest.targetSdkVersion! > 0) {
        apkInfo.targetSdkVersion = manifest.targetSdkVersion;
      }
      if (manifest.name?.isNotEmpty == true) {
        apkInfo.label = manifest.name;
        apkInfo.xapkName = manifest.name;
      }
      if (apkInfo.usesPermissions.isEmpty && manifest.permissions.isNotEmpty) {
        apkInfo.usesPermissions = manifest.permissions;
      }
      if (manifest.splitConfigs.isNotEmpty) {
        apkInfo.splitConfigs = manifest.splitConfigs;
      }
      if (manifest.splitApks.isNotEmpty) {
        apkInfo.splitApks = manifest.splitApks.map((e) => e.file).toList();
      }
      if (manifest.totalSize != null && manifest.totalSize! > 0) {
        apkInfo.totalSize = manifest.totalSize;
      }
      final iconImage = await loadXapkIcon(apk, iconPath: manifest.icon);
      if (iconImage != null && apkInfo.mainIconImage == null) {
        apkInfo.mainIconImage = iconImage;
      }
    } else {
      final iconImage = await loadXapkIcon(apk);
      if (iconImage != null && apkInfo.mainIconImage == null) {
        apkInfo.mainIconImage = iconImage;
      }
    }

    if (apkInfo.splitApks.isEmpty) {
      apkInfo.splitApks = apkInfo.archiveApks;
    }
    apkInfo.totalSize ??= apkInfo.apkSize;

    if (apkInfo.packageName == null &&
        apkInfo.versionName == null &&
        apkInfo.label == null &&
        apkInfo.archiveApks.isEmpty &&
        manifest == null) {
      log.info("getApkInfo: failed to parse XAPK/APKM");
      return null;
    }

    return apkInfo;
  }

  // 原有的APK解析逻辑
  final aaptPath = CommandTools.getAapt2Path();
  final start = DateTime.now();

  try {
    var result = await Process.run(
      aaptPath,
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
    log.info("getApkInfo: end exitCode=$exitCode, cost=${cost}ms");

    if (exitCode == 0) {
      parseApkInfoFromOutput(result.stdout.toString(), apkInfo);

      // 如果启用了签名检查，获取签名信息
      if (Config.enableSignature.value) {
        try {
          final signInfo = await getSignatureInfo(apk);
          apkInfo.signatureInfo = signInfo;
        } catch (e) {
          log.info("getApkInfo: 获取签名信息失败: $e");
          apkInfo.signatureInfo = "获取签名信息失败: $e";
        }
      }

      return apkInfo;
    }
  } catch (e) {
    log.info("getApkInfo: error=$e");
  }

  return null;
}

Future<String> getSignatureInfo(String apkPath) async {
  final apksigner = CommandTools.findApkSignerPath();
  if (apksigner == null || apksigner.isEmpty) {
    throw Exception(t.parse.please_set_path(name: "apksigner"));
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
    log.warning('getSignatureInfo: 获取签名信息失败: $e');
    rethrow;
  }
}

void parseApkInfoFromOutput(String output, ApkInfo apkInfo) {
  apkInfo.originalText = output;
  final lines = output.split("\n");
  for (final (index, item) in lines.indexed) {
    log.finer("parseApkInfoFromOutput: [$index] $item");
    apkInfo.parseLine(item);
  }
  log.fine("parseApkInfoFromOutput: apkInfo=$apkInfo");
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
  bool isXapk = false; // 是否为XAPK格式
  String? archiveType; // XAPK/APKM

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

  // XAPK 相关信息
  String? xapkName;
  List<String> splitConfigs = [];
  List<String> splitApks = [];
  List<String> archiveApks = [];
  List<String> obbFiles = [];
  int? totalSize;

  // 原始文本
  String originalText = "";

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

  // 找到最佳图标
  String _findBestIconPath(ZipHelper zip, String path) {
    String best = path;
    var number = 0;
    icons.forEach((key, value) {
      final tmp = int.parse(key);
      if (tmp > number) {
        number = tmp;
        best = value;
      }
      log.finer("_findBestIconPath: key=$key, value=$value");
    });
    log.info("_findBestIconPath: orig=$path, best=$best");
    return best;
  }

  /// 加载APK图标
  /// 返回图标的字节数据，如果加载失败返回null
  Future<Image?> loadIcon() async {
    if (mainIconPath == null || mainIconPath!.isEmpty) {
      return null;
    }

    try {
      var iconPath = mainIconPath!;
      final zip = ZipHelper();
      zip.open(apkPath);
      iconPath = _findBestIconPath(zip, iconPath);
      if (iconPath.endsWith('.webp') || iconPath.endsWith('.png')) {
        final data = await zip.readFileContent(iconPath);
        if (data != null) {
          final codec = await instantiateImageCodec(data);
          final frame = await codec.getNextFrame();
          return frame.image;
        } else {
          log.info('loadIcon: 找不到图标文件: $iconPath');
        }
      } else if (iconPath.endsWith('.xml')) {
        log.info('loadIcon: 暂不支持XML格式的图标: $iconPath');
      }
    } catch (e) {
      log.warning('loadIcon: 加载图标失败: $e');
    }
    return null;
  }

  @override
  String toString() {
    return 'ApkInfo{apkPath: $apkPath, apkSize: $apkSize, isXapk: $isXapk, archiveType: $archiveType, packageName: $packageName, versionCode: $versionCode, versionName: $versionName, platformBuildVersionName: $platformBuildVersionName, platformBuildVersionCode: $platformBuildVersionCode, compileSdkVersion: $compileSdkVersion, compileSdkVersionCodename: $compileSdkVersionCodename, sdkVersion: $sdkVersion, targetSdkVersion: $targetSdkVersion, label: $label, mainIcon: $mainIconPath, labels: $labels, usesPermissions: $usesPermissions, icons: $icons, application: $application, launchableActivity: $launchableActivity, userFeatures: $userFeatures, userFeaturesNotRequired: $userFeaturesNotRequired, userImpliedFeatures: $userImpliedFeatures, supportsScreens: $supportsScreens, locales: $locales, densities: $densities, supportsAnyDensity: $supportsAnyDensity, nativeCodes: $nativeCodes, others: $others, signatureInfo: $signatureInfo, xapkName: $xapkName, splitConfigs: $splitConfigs, splitApks: $splitApks, archiveApks: $archiveApks, obbFiles: $obbFiles, totalSize: $totalSize}';
  }

  void reset() {
    apkPath = "";
    apkSize = 0;
    isXapk = false;
    archiveType = null;
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
    xapkName = null;
    splitConfigs.clear();
    splitApks.clear();
    archiveApks.clear();
    obbFiles.clear();
    totalSize = null;
    originalText = "";
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
