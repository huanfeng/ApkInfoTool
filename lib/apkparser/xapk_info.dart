import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:apk_info_tool/utils/zip_helper.dart';

class XapkManifest {
  final int xapkVersion;
  final String packageName;
  final String name;
  final int versionCode;
  final String versionName;
  final int minSdkVersion;
  final int targetSdkVersion;
  final List<String> permissions;
  final List<String> splitConfigs;
  final int totalSize;
  final String icon;
  final List<SplitApk> splitApks;

  XapkManifest({
    required this.xapkVersion,
    required this.packageName,
    required this.name,
    required this.versionCode,
    required this.versionName,
    required this.minSdkVersion,
    required this.targetSdkVersion,
    required this.permissions,
    required this.splitConfigs,
    required this.totalSize,
    required this.icon,
    required this.splitApks,
  });

  factory XapkManifest.fromJson(Map<String, dynamic> json) {
    return XapkManifest(
      xapkVersion: json['xapk_version'] as int,
      packageName: json['package_name'] as String,
      name: json['name'] as String,
      versionCode: int.parse(json['version_code']),
      versionName: json['version_name'] as String,
      minSdkVersion: int.parse(json['min_sdk_version']),
      targetSdkVersion: int.parse(json['target_sdk_version']),
      permissions: List<String>.from(json['permissions']),
      splitConfigs: List<String>.from(json['split_configs']),
      totalSize: json['total_size'] as int,
      icon: json['icon'] as String,
      splitApks: (json['split_apks'] as List)
          .map((e) => SplitApk.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
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
    return SplitApk(
      file: json['file'] as String,
      id: json['id'] as String,
    );
  }
}

Future<XapkManifest?> parseXapkManifest(String xapkPath) async {
  final zip = ZipHelper();
  try {
    if (!zip.open(xapkPath)) return null;
    final manifestData = await zip.readFileContent('manifest.json');
    if (manifestData == null) return null;
    
    final manifestJson = String.fromCharCodes(manifestData);
    final Map<String, dynamic> json = jsonDecode(manifestJson);
    return XapkManifest.fromJson(json);
  } catch (e) {
    return null;
  } finally {
    zip.close();
  }
}

Future<Image?> loadXapkIcon(String xapkPath) async {
  final zip = ZipHelper();
  try {
    if (!zip.open(xapkPath)) return null;
    final iconData = await zip.readFileContent('icon.png');
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
