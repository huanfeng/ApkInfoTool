import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:apk_info_tool/utils/logger.dart';
import 'package:apk_info_tool/utils/zip_helper.dart';
import 'package:path/path.dart' as path;

class XapkManifest {
  final int? xapkVersion;
  final String? packageName;
  final String? name;
  final Map<String, String>? localesName;
  final int? versionCode;
  final String? versionName;
  final int? minSdkVersion;
  final int? targetSdkVersion;
  final List<String> permissions;
  final List<String> splitConfigs;
  final int? totalSize;
  final String? icon;
  final List<SplitApk> splitApks;

  XapkManifest({
    this.xapkVersion,
    this.packageName,
    this.name,
    this.localesName,
    this.versionCode,
    this.versionName,
    this.minSdkVersion,
    this.targetSdkVersion,
    this.permissions = const [],
    this.splitConfigs = const [],
    this.totalSize,
    this.icon,
    this.splitApks = const [],
  });

  factory XapkManifest.fromJson(Map<String, dynamic> json) {
    int? parseIntSafe(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      return null;
    }

    String? parseStringSafe(dynamic value) {
      if (value == null) return null;
      return value.toString();
    }

    List<String> parseStringList(dynamic value) {
      if (value == null) return const [];
      if (value is List) {
        return value.map((e) => e.toString()).toList();
      }
      if (value is String) {
        return value.split(',').map((e) => e.trim()).toList();
      }
      return const [];
    }

    List<SplitApk> parseSplitApks(dynamic value) {
      if (value is List) {
        return value
            .map((e) => SplitApk.fromJson(e as Map<String, dynamic>))
            .where((apk) => apk.file.isNotEmpty)
            .toList();
      }
      return const [];
    }

    try {
      return XapkManifest(
        xapkVersion: parseIntSafe(json['xapk_version']),
        packageName: parseStringSafe(json['package_name']),
        name: parseStringSafe(json['name']) ??
            parseStringSafe(json['app_name']) ??
            parseStringSafe(json['apk_name']),
        localesName: (json['locales_name'] as Map<String, dynamic>?)?.map(
          (key, value) => MapEntry(key, value.toString()),
        ),
        versionCode: parseIntSafe(json['version_code']),
        versionName: parseStringSafe(json['version_name']),
        minSdkVersion: parseIntSafe(json['min_sdk_version']),
        targetSdkVersion: parseIntSafe(json['target_sdk_version']),
        permissions: parseStringList(json['permissions']),
        splitConfigs: json['split_configs'] == null
            ? const []
            : parseStringList(json['split_configs']),
        totalSize: parseIntSafe(json['total_size']),
        icon: parseStringSafe(json['icon']),
        splitApks: parseSplitApks(json['split_apks']),
      );
    } catch (e) {
      log.severe('Error parsing XAPK manifest: $e');
      rethrow;
    }
  }
}

class SplitApk {
  final String file;
  final String id;

  SplitApk({
    required this.file,
    required this.id,
  });

  factory SplitApk.fromJson(Map<String, dynamic> json) {
    final file = (json['file'] ??
            json['path'] ??
            json['apk'] ??
            json['name'])
        ?.toString();
    final id = (json['id'] ?? json['type'] ?? json['name'])
        ?.toString()
        ?.trim();
    return SplitApk(
      file: file ?? '',
      id: id?.isNotEmpty == true
          ? id!
          : path.basenameWithoutExtension(file ?? ''),
    );
  }
}

Future<XapkManifest?> parseXapkManifest(String xapkPath) async {
  final zip = ZipHelper();
  try {
    if (!zip.open(xapkPath)) return null;
    final manifestData = await zip.readFileContent('manifest.json') ??
        await zip.readFileContent('info.json');
    if (manifestData == null) return null;

    final manifestJson = String.fromCharCodes(manifestData);
    final Map<String, dynamic> json = jsonDecode(manifestJson);
    return XapkManifest.fromJson(json);
  } catch (e) {
    log.severe('Failed to parse XAPK manifest: $e');
    return null;
  } finally {
    zip.close();
  }
}

Future<Image?> loadXapkIcon(String xapkPath, {String? iconPath}) async {
  final zip = ZipHelper();
  try {
    if (!zip.open(xapkPath)) return null;
    final candidates = <String>[
      if (iconPath != null && iconPath.isNotEmpty) iconPath,
      'icon.png',
    ];
    Uint8List? iconData;
    for (final candidate in candidates) {
      iconData = await zip.readFileContent(candidate);
      if (iconData != null) break;
    }
    if (iconData == null) return null;

    final codec = await instantiateImageCodec(iconData);
    final frame = await codec.getNextFrame();
    return frame.image;
  } catch (e) {
    return null;
  } finally {
    zip.close();
  }
}
