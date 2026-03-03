import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:apk_info_tool/apkparser/adaptive_icon_renderer.dart';
import 'package:apk_info_tool/config.dart';
import 'package:apk_info_tool/gen/strings.g.dart';
import 'package:apk_info_tool/utils/command_tools.dart';
import 'package:apk_info_tool/utils/logger.dart';
import 'package:apk_info_tool/utils/vector_to_svg.dart';
import 'package:apk_info_tool/utils/zip_helper.dart';
import 'package:path/path.dart' as path;
import 'xapk_info.dart';

enum IconCandidateType { bitmap, xmlVector }

class IconCandidate {
  final String path;
  final IconCandidateType type;
  final String? dpiLabel;
  final int? dpiValue;

  Image? renderedImage;
  Uint8List? rawBytes;

  IconCandidate({
    required this.path,
    required this.type,
    this.dpiLabel,
    this.dpiValue,
  });

  /// 从路径推断类型和 DPI，可选传入已知 DPI 值
  factory IconCandidate.fromPath(String entryPath, {int? knownDpi}) {
    final lower = entryPath.toLowerCase();
    final type = (lower.endsWith('.xml'))
        ? IconCandidateType.xmlVector
        : IconCandidateType.bitmap;

    String? dpiLabel;
    int? dpiValue;

    // 从路径目录名中提取 DPI（如 mipmap-xxxhdpi-v4/）
    final dpiMatch = RegExp(r'[/-](nodpi|anydpi(?:-v\d+)?|[a-z]*dpi)(?:[/-])').firstMatch(lower);
    if (dpiMatch != null) {
      dpiLabel = dpiMatch.group(1);
      dpiValue = _dpiLabelToValue(dpiLabel);
    }

    // 如果路径中没找到 DPI，使用已知的 DPI 值
    if (dpiLabel == null && knownDpi != null) {
      dpiValue = knownDpi;
      dpiLabel = _dpiValueToLabel(knownDpi);
    }

    return IconCandidate(
      path: entryPath,
      type: type,
      dpiLabel: dpiLabel,
      dpiValue: dpiValue,
    );
  }

  /// 显示标签，包含文件名以便区分
  String get displayLabel {
    final fileName = path.split('/').last;
    final baseName = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    final dpiText = dpiLabel ?? '?';
    if (type == IconCandidateType.xmlVector) {
      return 'XML $baseName ($dpiText)';
    }
    final ext = fileName.contains('.')
        ? fileName.substring(fileName.lastIndexOf('.') + 1).toUpperCase()
        : '?';
    return '$ext $baseName ($dpiText)';
  }

  void dispose() {
    renderedImage?.dispose();
    renderedImage = null;
  }

  static int? _dpiLabelToValue(String? label) {
    if (label == null) return null;
    return switch (label) {
      'ldpi' => 120,
      'mdpi' => 160,
      'hdpi' => 240,
      'xhdpi' => 320,
      'xxhdpi' => 480,
      'xxxhdpi' => 640,
      'tvdpi' => 213,
      _ => null,
    };
  }

  static String? _dpiValueToLabel(int? value) {
    if (value == null) return null;
    return switch (value) {
      120 => 'ldpi',
      160 => 'mdpi',
      240 => 'hdpi',
      320 => 'xhdpi',
      480 => 'xxhdpi',
      640 => 'xxxhdpi',
      213 => 'tvdpi',
      _ => '${value}dpi',
    };
  }
}

bool _isArchiveApk(String apkPath) {
  final extension = path.extension(apkPath).toLowerCase();
  return extension == '.xapk' || extension == '.apkm' || extension == '.apks';
}

String _archiveTypeFromExtension(String extension) {
  if (extension == '.apkm') return 'APKM';
  if (extension == '.apks') return 'APKS';
  return 'XAPK';
}

enum _ZipContentType { renamedApk, containsApks, notApk }

Future<_ZipContentType> _detectZipContentType(String zipPath) async {
  final zip = ZipHelper();
  try {
    if (!await zip.open(zipPath)) return _ZipContentType.notApk;
    final files = zip.listFiles();

    // 检查 ZIP 根目录是否有 AndroidManifest.xml → 说明这是重命名的 APK（优先级最高）
    final hasRootManifest =
        files.any((f) => f.toLowerCase() == 'androidmanifest.xml');

    // 检查是否包含 .apk 文件
    final hasApkFiles = files.any((f) => f.toLowerCase().endsWith('.apk'));

    if (hasRootManifest) return _ZipContentType.renamedApk;
    if (hasApkFiles) return _ZipContentType.containsApks;
    return _ZipContentType.notApk;
  } finally {
    zip.close();
  }
}

final _kSplitAbiTokens = <String>{
  'armeabi',
  'armeabi_v7a',
  'arm64_v8a',
  'x86',
  'x86_64',
  'mips',
  'mips64',
};

final _kSplitDensityTokens = <String>{
  'ldpi',
  'mdpi',
  'hdpi',
  'xhdpi',
  'xxhdpi',
  'xxxhdpi',
  'tvdpi',
};

bool _looksLikeSplitAbi(String value) {
  if (_kSplitAbiTokens.contains(value)) return true;
  return value.contains('v7a') ||
      value.contains('v8a') ||
      value.contains('x86');
}

bool _looksLikeSplitDensity(String value) {
  if (_kSplitDensityTokens.contains(value)) return true;
  return value.endsWith('dpi');
}

final _kSplitLanguagePattern = RegExp(r'^[a-z]{2,3}(-r[a-z]{2})?$');

bool _looksLikeSplitLanguage(String value) {
  return _kSplitLanguagePattern.hasMatch(value);
}

bool _hasOnlyPlaceholderLocales(List<String> locales) {
  if (locales.isEmpty) return false;
  final normalized = locales.map((e) => e.trim().toLowerCase()).toList();
  return normalized.every((e) => e == '--_--' || e == '--');
}

void _inferLocalesAndAbisFromSplits(
  ApkInfo apkInfo,
  List<String> splitApks,
) {
  final needLocales =
      apkInfo.locales.isEmpty || _hasOnlyPlaceholderLocales(apkInfo.locales);
  final needAbis = apkInfo.nativeCodes.isEmpty;
  if (!needLocales && !needAbis) return;

  final locales = <String>[];
  final localesSeen = <String>{};
  final abis = <String>[];
  final abisSeen = <String>{};

  for (final entry in splitApks) {
    final baseName = path.basenameWithoutExtension(entry).toLowerCase();
    String? suffix;
    if (baseName.startsWith('split_config.')) {
      suffix = baseName.substring('split_config.'.length);
    } else if (baseName.startsWith('config.')) {
      suffix = baseName.substring('config.'.length);
    } else {
      continue;
    }

    if (suffix.isEmpty) continue;
    if (needAbis && _looksLikeSplitAbi(suffix)) {
      if (abisSeen.add(suffix)) abis.add(suffix);
      continue;
    }
    if (_looksLikeSplitDensity(suffix)) continue;
    if (needLocales && _looksLikeSplitLanguage(suffix)) {
      if (localesSeen.add(suffix)) locales.add(suffix);
    }
  }

  if (needLocales && locales.isNotEmpty) {
    apkInfo.locales = locales;
  }
  if (needAbis && abis.isNotEmpty) {
    apkInfo.nativeCodes = abis;
  }
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

  // ZIP 文件智能检测：区分重命名的 APK 和包含多个 APK 的压缩包
  final extension = path.extension(apk).toLowerCase();
  bool zipAsArchive = false;

  if (extension == '.zip') {
    final zipType = await _detectZipContentType(apk);
    log.fine("getApkInfo: ZIP content type=$zipType");
    if (zipType == _ZipContentType.containsApks) {
      zipAsArchive = true;
    } else if (zipType == _ZipContentType.notApk) {
      log.warning("getApkInfo: ZIP file contains no APK content");
      return null;
    }
    // renamedApk: fall through to aapt2 direct parsing
  }

  // 检查是否为XAPK/APKM/APKS格式，或 ZIP 内含多个 APK
  if (_isArchiveApk(apk) || zipAsArchive) {
    log.fine("getApkInfo: parsing archive file (zipAsArchive=$zipAsArchive)");
    apkInfo.isXapk = true;
    apkInfo.archiveType =
        zipAsArchive ? 'ZIP' : _archiveTypeFromExtension(extension);

    final totalSw = Stopwatch()..start();
    var zipOpenMs = 0;
    var manifestMs = 0;
    var extractMs = 0;
    var aapt2Ms = 0;
    var parseMs = 0;
    var iconMs = 0;

    // 共享同一个 ZipHelper 实例，避免重复打开同一个大文件
    final zip = ZipHelper();
    Directory? tempDir;
    String? baseApkPath;
    XapkManifest? manifest;
    try {
      final zipOpenSw = Stopwatch()..start();
      if (!await zip.open(apk)) {
        log.warning("getApkInfo: failed to open XAPK file");
        return null;
      }
      zipOpenMs = zipOpenSw.elapsedMilliseconds;

      // 使用共享的 zip 实例解析清单（不再重新打开文件）
      final manifestSw = Stopwatch()..start();
      manifest = await parseXapkManifest(apk, sharedZip: zip);
      manifestMs = manifestSw.elapsedMilliseconds;

      apkInfo.archiveApks = zip.listFiles(extension: '.apk');
      apkInfo.obbFiles = zip.listFiles(extension: '.obb');

      // 优先加载打包文件自带的图标（xapk/apkm 自身携带的 icon）
      final iconSw = Stopwatch()..start();
      final xapkIcon = await loadXapkIcon(apk,
          iconPath: manifest?.icon, sharedZip: zip);
      if (xapkIcon != null) {
        apkInfo.mainIconImage = xapkIcon;
      }
      iconMs = iconSw.elapsedMilliseconds;

      final baseEntry = _findBaseApkEntry(apkInfo.archiveApks);
      if (baseEntry != null) {
        tempDir = await Directory.systemTemp.createTemp('apk_info_base');
        baseApkPath = path.join(tempDir.path, path.basename(baseEntry));
        final extractSw = Stopwatch()..start();
        final extracted = await zip.extractFile(baseEntry, baseApkPath);
        extractMs = extractSw.elapsedMilliseconds;
        if (extracted) {
          try {
            final aaptPath = CommandTools.findAapt2Path();
            if (aaptPath == null || aaptPath.isEmpty) {
              throw Exception(t.parse.please_set_path(name: 'aapt2'));
            }
            final aapt2Sw = Stopwatch()..start();
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
            aapt2Ms = aapt2Sw.elapsedMilliseconds;
            if (result.exitCode == 0) {
              final originalPath = apkInfo.apkPath;
              apkInfo.apkPath = baseApkPath;
              final parseSw = Stopwatch()..start();
              parseApkInfoFromOutput(result.stdout.toString(), apkInfo);
              parseMs = parseSw.elapsedMilliseconds;
              // 仅在打包文件不包含图标时，才从 base APK 加载图标
              if (apkInfo.mainIconImage == null) {
                iconSw..reset()..start();
                final iconImage = await apkInfo.loadIcon();
                if (iconImage != null) {
                  apkInfo.mainIconImage = iconImage;
                }
                iconMs += iconSw.elapsedMilliseconds;
              }
              apkInfo.apkPath = originalPath;
            }
          } catch (e) {
            log.warning("getApkInfo: base APK parse failed: $e");
          }
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
        if (manifest.targetSdkVersion != null &&
            manifest.targetSdkVersion! > 0) {
          apkInfo.targetSdkVersion = manifest.targetSdkVersion;
        }
        if (manifest.name?.isNotEmpty == true) {
          apkInfo.label = manifest.name;
          apkInfo.xapkName = manifest.name;
        }
        if (apkInfo.usesPermissions.isEmpty &&
            manifest.permissions.isNotEmpty) {
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
      }
    } finally {
      zip.close();
      if (tempDir != null && await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }

    if (apkInfo.splitApks.isEmpty) {
      apkInfo.splitApks = apkInfo.archiveApks;
    }
    _inferLocalesAndAbisFromSplits(apkInfo, apkInfo.splitApks);
    apkInfo.totalSize ??= apkInfo.apkSize;

    if (apkInfo.packageName == null &&
        apkInfo.versionName == null &&
        apkInfo.label == null &&
        apkInfo.archiveApks.isEmpty &&
        manifest == null) {
      log.warning("getApkInfo: failed to parse XAPK/APKM/APKS");
      return null;
    }

    totalSw.stop();
    log.info("[PERF] getApkInfo(archive): total=${totalSw.elapsedMilliseconds}ms"
        " | zip_open=${zipOpenMs}ms"
        " | xapk_manifest=${manifestMs}ms"
        " | zip_extract=${extractMs}ms"
        " | aapt2_badging=${aapt2Ms}ms"
        " | output_parse=${parseMs}ms"
        " | icon=${iconMs}ms");

    return apkInfo;
  }

  // 原有的APK解析逻辑
  final aaptPath = CommandTools.findAapt2Path();
  if (aaptPath == null || aaptPath.isEmpty) {
    throw Exception(t.parse.please_set_path(name: 'aapt2'));
  }
  final totalSw = Stopwatch()..start();
  var aapt2BadgingMs = 0;
  var outputParseMs = 0;
  var iconMs = 0;
  var signatureMs = 0;

  try {
    final aapt2Sw = Stopwatch()..start();
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
    aapt2BadgingMs = aapt2Sw.elapsedMilliseconds;

    var exitCode = result.exitCode;
    log.fine("getApkInfo: aapt2 exitCode=$exitCode");

    if (exitCode == 0) {
      final parseSw = Stopwatch()..start();
      parseApkInfoFromOutput(result.stdout.toString(), apkInfo);
      outputParseMs = parseSw.elapsedMilliseconds;

      final iconSw = Stopwatch()..start();
      final iconImage = await apkInfo.loadIcon();
      if (iconImage != null) {
        apkInfo.mainIconImage ??= iconImage;
      }
      iconMs = iconSw.elapsedMilliseconds;

      // 如果启用了签名检查，获取签名信息
      if (Config.enableSignature.value) {
        final sigSw = Stopwatch()..start();
        try {
          final signInfo = await getSignatureInfo(apk);
          apkInfo.signatureInfo = signInfo;
        } catch (e) {
          log.warning("getApkInfo: 获取签名信息失败: $e");
          apkInfo.signatureInfo = "获取签名信息失败: $e";
        }
        signatureMs = sigSw.elapsedMilliseconds;
      }

      totalSw.stop();
      log.info("[PERF] getApkInfo: total=${totalSw.elapsedMilliseconds}ms"
          " | aapt2_badging=${aapt2BadgingMs}ms"
          " | output_parse=${outputParseMs}ms"
          " | icon=${iconMs}ms"
          " | signature=${signatureMs}ms");

      return apkInfo;
    }
  } catch (e) {
    log.warning("getApkInfo: error=$e");
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
    ).timeout(
      const Duration(seconds: 120),
      onTimeout: () {
        throw TimeoutException('apksigner verify timeout');
      },
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
  String? archiveType; // XAPK/APKM/APKS

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
  List<IconCandidate> iconCandidates = [];
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

  // 文件哈希值
  String? md5Hash;
  String? sha1Hash;

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
            icons[key.substring("application-icon-".length)] = value.trimSQ();
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

  // 从 application-icon-* 中按密度从大到小排列，返回 (dpi, path) 对
  List<MapEntry<int, String>> _buildIconCandidatesWithDpi() {
    final entries = <MapEntry<int, String>>[];
    icons.forEach((key, value) {
      final tmp = int.tryParse(key);
      if (tmp != null) {
        entries.add(MapEntry(tmp, value));
      }
      log.finer("_buildIconCandidates: key=$key, value=$value");
    });

    entries.sort((a, b) => b.key.compareTo(a.key));
    return entries;
  }

  bool _isBitmapIcon(String path) {
    return path.endsWith('.webp') || path.endsWith('.png');
  }

  bool _isBitmapPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.webp') ||
        lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg');
  }

  bool _isXmlPath(String path) {
    return path.toLowerCase().endsWith('.xml');
  }

  Future<Image?> _decodeImageData(Uint8List data) async {
    try {
      final codec = await instantiateImageCodec(data);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  int _unknownPathScore(String candidate) {
    final lower = candidate.toLowerCase();
    var score = 0;
    if (lower.contains('mipmap')) score += 300;
    if (lower.contains('drawable')) score += 220;
    if (lower.contains('launcher')) score += 180;
    if (_isBitmapPath(lower)) score += 200;
    if (_isXmlPath(lower)) score += 120;
    if (lower.contains('-xxxhdpi')) score += 90;
    if (lower.contains('-xxhdpi')) score += 80;
    if (lower.contains('-xhdpi')) score += 70;
    if (lower.contains('-hdpi')) score += 60;
    if (lower.contains('-mdpi')) score += 50;
    return score;
  }

  List<String> _findUnknownCandidatePaths(List<String> allFiles, String candidate) {
    final raw = candidate.trim();
    if (raw.isEmpty) return const [];
    final normalized = raw.replaceAll('\\', '/');
    final files = allFiles;
    final result = <String>{};
    if (files.contains(normalized)) {
      result.add(normalized);
    }
    if (normalized.startsWith('/')) {
      final tmp = normalized.substring(1);
      if (files.contains(tmp)) {
        result.add(tmp);
      }
    }
    final base = path.basename(normalized).toLowerCase();
    for (final file in files) {
      final fileLower = file.toLowerCase();
      final fileBase = path.basename(fileLower);
      if (fileBase == base || fileLower.endsWith('/$base')) {
        result.add(file);
      }
    }
    final sorted = result.toList();
    sorted.sort((a, b) => _unknownPathScore(b).compareTo(_unknownPathScore(a)));
    return sorted;
  }

  /// 收集所有图标候选路径，构建 iconCandidates 列表（不渲染）
  Future<void> collectIconCandidates() async {
    iconCandidates.clear();

    if (mainIconPath == null || mainIconPath!.isEmpty) {
      if (icons.isEmpty) return;
    }

    final zip = ZipHelper();
    AdaptiveIconRenderer? adaptiveIconRenderer;
    try {
      await zip.open(apkPath);
      final aaptPath = CommandTools.findAapt2Path();
      final allFiles = zip.listFiles();

      // 构建 path -> knownDpi 的映射
      final dpiMap = <String, int>{};
      final candidatesWithDpi = _buildIconCandidatesWithDpi();
      for (final entry in candidatesWithDpi) {
        dpiMap[entry.value] = entry.key;
      }

      final candidates = <String>[];
      if (mainIconPath != null && mainIconPath!.isNotEmpty) {
        candidates.add(mainIconPath!);
      }
      candidates.addAll(candidatesWithDpi.map((e) => e.value));
      final uniqueCandidates = <String>[];
      final seenCandidates = <String>{};
      for (final item in candidates) {
        if (seenCandidates.add(item)) {
          uniqueCandidates.add(item);
        }
      }

      final prioritizedPaths = <String>[];
      final prioritizedSeen = <String>{};
      for (final iconPath in uniqueCandidates) {
        var resourceLinkedBitmaps = <String>[];
        if (_isXmlPath(iconPath) && aaptPath != null && aaptPath.isNotEmpty) {
          adaptiveIconRenderer ??= AdaptiveIconRenderer(
            apkPath: apkPath,
            aaptPath: aaptPath,
            zip: zip,
          );
          resourceLinkedBitmaps = await adaptiveIconRenderer
              .findBitmapAlternativesForPath(iconPath);
        }
        if (prioritizedSeen.add(iconPath)) {
          prioritizedPaths.add(iconPath);
        }
        for (final bitmap in resourceLinkedBitmaps) {
          if (prioritizedSeen.add(bitmap)) {
            prioritizedPaths.add(bitmap);
          }
        }
      }

      // 收集有效候选
      final validPaths = <String>[];
      for (final iconPath in prioritizedPaths) {
        if (_isBitmapIcon(iconPath)) {
          if (allFiles.contains(iconPath)) {
            validPaths.add(iconPath);
          }
        } else if (_isXmlPath(iconPath)) {
          if (allFiles.contains(iconPath)) {
            validPaths.add(iconPath);
          }
        } else {
          // 资源引用或未知路径，尝试解析
          final resolvedPaths = _findUnknownCandidatePaths(allFiles, iconPath);
          if (resolvedPaths.isNotEmpty) {
            for (final resolved in resolvedPaths) {
              if (prioritizedSeen.add(resolved)) {
                validPaths.add(resolved);
              }
            }
          } else {
            // 保留原始路径（可能是资源引用，渲染时由 AdaptiveIconRenderer 处理）
            validPaths.add(iconPath);
          }
        }
      }

      // 兜底：启发式扫描
      if (validPaths.isEmpty) {
        final fallbackCandidates = allFiles
            .where((e) {
              final lower = e.toLowerCase();
              return lower.contains('mipmap') ||
                  (lower.contains('drawable') && lower.contains('launcher'));
            })
            .toSet()
            .toList()
          ..sort((a, b) => _unknownPathScore(b).compareTo(_unknownPathScore(a)));
        for (final candidate in fallbackCandidates) {
          if (prioritizedSeen.add(candidate)) {
            validPaths.add(candidate);
          }
        }
      }

      // 去除 _round 后缀的变体
      final filtered = validPaths.where((p) {
        final lower = p.toLowerCase();
        return !lower.contains('_round.');
      }).toList();

      // 构建 IconCandidate 对象，传入已知 DPI
      final seen = <String>{};
      for (final p in filtered) {
        if (seen.add(p)) {
          iconCandidates.add(IconCandidate.fromPath(p, knownDpi: dpiMap[p]));
        }
      }

      log.fine('collectIconCandidates: found ${iconCandidates.length} candidates: ${iconCandidates.map((c) => c.path).join(", ")}');
    } catch (e) {
      log.warning('collectIconCandidates: 收集图标候选失败: $e');
    } finally {
      adaptiveIconRenderer?.dispose();
      zip.close();
    }
  }

  /// 渲染指定索引的候选图标，结果缓存到 IconCandidate.renderedImage
  Future<Image?> renderIcon(int index) async {
    if (index < 0 || index >= iconCandidates.length) return null;
    final candidate = iconCandidates[index];

    // 已有缓存，直接返回
    if (candidate.renderedImage != null) return candidate.renderedImage;

    final zip = ZipHelper();
    AdaptiveIconRenderer? adaptiveIconRenderer;
    try {
      await zip.open(apkPath);
      final aaptPath = CommandTools.findAapt2Path();
      final iconPath = candidate.path;

      if (_isBitmapIcon(iconPath) || _isBitmapPath(iconPath)) {
        final data = await zip.readFileContent(iconPath);
        if (data != null) {
          final image = await _decodeImageData(data);
          if (image != null) {
            candidate.renderedImage = image;
            log.fine('renderIcon: 渲染位图图标: $iconPath');
            return image;
          }
        }
      }

      if (_isXmlPath(iconPath)) {
        if (aaptPath != null && aaptPath.isNotEmpty) {
          adaptiveIconRenderer = AdaptiveIconRenderer(
            apkPath: apkPath,
            aaptPath: aaptPath,
            zip: zip,
          );
          final image = await adaptiveIconRenderer.render(iconPath);
          if (image != null) {
            candidate.renderedImage = image;
            log.fine('renderIcon: 渲染XML图标: $iconPath');
            return image;
          }
        }
      }

      // 尝试作为资源引用渲染
      if (aaptPath != null && aaptPath.isNotEmpty) {
        adaptiveIconRenderer ??= AdaptiveIconRenderer(
          apkPath: apkPath,
          aaptPath: aaptPath,
          zip: zip,
        );
        final rendered = await adaptiveIconRenderer.render(iconPath);
        if (rendered != null) {
          candidate.renderedImage = rendered;
          log.fine('renderIcon: 渲染资源引用图标: $iconPath');
          return rendered;
        }
      }

      log.fine('renderIcon: 无法渲染图标: $iconPath');
    } catch (e) {
      log.warning('renderIcon: 渲染图标失败: $e');
    } finally {
      adaptiveIconRenderer?.dispose();
      zip.close();
    }
    return null;
  }

  /// 加载APK图标（兼容接口）
  /// 先收集候选，再渲染第一个可用的
  Future<Image?> loadIcon() async {
    await collectIconCandidates();
    if (iconCandidates.isEmpty) {
      log.fine('loadIcon: 未找到可用图标');
      return null;
    }

    // 按顺序尝试渲染，直到成功
    for (var i = 0; i < iconCandidates.length; i++) {
      final image = await renderIcon(i);
      if (image != null) {
        return image;
      }
    }

    log.fine('loadIcon: 所有候选图标渲染失败');
    return null;
  }

  /// 为导出渲染高清图标（XML 矢量图使用更大 canvas + 透明背景）
  /// 位图图标直接解码原始分辨率
  Future<Image?> renderIconForExport(int index, {int exportSize = 1024}) async {
    if (index < 0 || index >= iconCandidates.length) return null;
    final candidate = iconCandidates[index];
    final iconPath = candidate.path;

    final zip = ZipHelper();
    AdaptiveIconRenderer? adaptiveIconRenderer;
    try {
      await zip.open(apkPath);
      final aaptPath = CommandTools.findAapt2Path();

      // 位图：直接解码原始分辨率
      if (_isBitmapIcon(iconPath) || _isBitmapPath(iconPath)) {
        final data = await zip.readFileContent(iconPath);
        if (data != null) {
          return await _decodeImageData(data);
        }
      }

      // XML 矢量图：高分辨率 + 透明背景
      if (aaptPath != null && aaptPath.isNotEmpty) {
        adaptiveIconRenderer = AdaptiveIconRenderer(
          apkPath: apkPath,
          aaptPath: aaptPath,
          zip: zip,
        );
        return await adaptiveIconRenderer.render(
          iconPath,
          canvasSize: exportSize,
          transparentBackground: true,
        );
      }
    } catch (e) {
      log.warning('renderIconForExport: 导出渲染失败: $e');
    } finally {
      adaptiveIconRenderer?.dispose();
      zip.close();
    }
    return null;
  }

  /// 将指定索引的 XML 矢量图标候选导出为 SVG 字符串。
  /// 支持解析 adaptive-icon 中引用的 vector drawable。
  Future<String?> exportSvgString(int index) async {
    if (index < 0 || index >= iconCandidates.length) return null;
    final candidate = iconCandidates[index];
    if (candidate.type != IconCandidateType.xmlVector) return null;

    final zip = ZipHelper();
    AdaptiveIconRenderer? renderer;
    try {
      await zip.open(apkPath);
      final aaptPath = CommandTools.findAapt2Path();
      if (aaptPath == null || aaptPath.isEmpty) {
        // 无 aapt 时直接读取 XML 字节尝试转换
        final bytes = await zip.readFileContent(candidate.path);
        if (bytes != null) {
          return VectorToSvg.convert(bytes);
        }
        return null;
      }

      renderer = AdaptiveIconRenderer(
        apkPath: apkPath,
        aaptPath: aaptPath,
        zip: zip,
      );

      // 优先尝试 adaptive-icon 完整导出（包含 background + foreground）
      final adaptiveData =
          await renderer.resolveAdaptiveIconForSvg(candidate.path);
      if (adaptiveData != null) {
        if (adaptiveData.backgroundVector != null) {
          await renderer
              .resolveVectorColorRefs(adaptiveData.backgroundVector!);
          await renderer
              .resolveVectorGradientRefs(adaptiveData.backgroundVector!);
        }
        if (adaptiveData.foregroundVector != null) {
          await renderer
              .resolveVectorColorRefs(adaptiveData.foregroundVector!);
          await renderer
              .resolveVectorGradientRefs(adaptiveData.foregroundVector!);
        }
        return VectorToSvg.convertAdaptiveIconData(adaptiveData);
      }

      // 回退：单个 vector drawable 导出
      final vectorElement =
          await renderer.resolveToVectorElement(candidate.path);
      if (vectorElement != null) {
        await renderer.resolveVectorColorRefs(vectorElement);
        await renderer.resolveVectorGradientRefs(vectorElement);
        return VectorToSvg.convertElement(vectorElement);
      }
      return null;
    } catch (e) {
      log.warning('exportSvgString: SVG 导出失败: $e');
      return null;
    } finally {
      renderer?.dispose();
      zip.close();
    }
  }

  @override
  String toString() {
    return 'ApkInfo{apkPath: $apkPath, apkSize: $apkSize, isXapk: $isXapk, archiveType: $archiveType, packageName: $packageName, versionCode: $versionCode, versionName: $versionName, platformBuildVersionName: $platformBuildVersionName, platformBuildVersionCode: $platformBuildVersionCode, compileSdkVersion: $compileSdkVersion, compileSdkVersionCodename: $compileSdkVersionCodename, sdkVersion: $sdkVersion, targetSdkVersion: $targetSdkVersion, label: $label, mainIcon: $mainIconPath, labels: $labels, usesPermissions: $usesPermissions, icons: $icons, application: $application, launchableActivity: $launchableActivity, userFeatures: $userFeatures, userFeaturesNotRequired: $userFeaturesNotRequired, userImpliedFeatures: $userImpliedFeatures, supportsScreens: $supportsScreens, locales: $locales, densities: $densities, supportsAnyDensity: $supportsAnyDensity, nativeCodes: $nativeCodes, others: $others, signatureInfo: $signatureInfo, xapkName: $xapkName, splitConfigs: $splitConfigs, splitApks: $splitApks, archiveApks: $archiveApks, obbFiles: $obbFiles, totalSize: $totalSize}';
  }

  /// 释放持有的 GPU 资源（dart:ui.Image）
  void dispose() {
    for (final candidate in iconCandidates) {
      candidate.dispose();
    }
    iconCandidates.clear();
    // mainIconImage 指向某个候选的 renderedImage，已在上面释放
    mainIconImage = null;
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
    for (final candidate in iconCandidates) {
      candidate.dispose();
    }
    iconCandidates.clear();
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
    md5Hash = null;
    sha1Hash = null;
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
