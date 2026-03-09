import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

final _log = Logger('ToolPaths');

class ToolPaths {
  static String get appDir => File(Platform.resolvedExecutable).parent.path;
  static String? _appSupportDir;

  static const _appDirName = 'to.feng.app.apkinfotool';

  static Future<void> init() async {
    if (_appSupportDir != null) return;
    await _migrateDataDir();
    final dir = await getApplicationSupportDirectory();
    _appSupportDir = dir.path;
  }

  /// Windows 数据目录迁移：将旧目录结构迁移到新的扁平结构
  /// 旧结构: AppData/Roaming/{companyName}/apk_info_tool/
  /// 新结构: AppData/Roaming/to.feng.app.apkinfotool/
  static Future<void> _migrateDataDir() async {
    if (!Platform.isWindows) return;

    final roamingDir = Platform.environment['APPDATA'];
    if (roamingDir == null) return;

    final newDir = Directory(path.join(roamingDir, _appDirName));

    // 旧包名结构: com.fengware.app.apkinfotool/apk_info_tool -> to.feng.app.apkinfotool
    final oldDir = Directory(
        path.join(roamingDir, 'com.fengware.app.apkinfotool', 'apk_info_tool'));
    if (!oldDir.existsSync()) return;

    try {
      if (!newDir.existsSync()) {
        // 新目录不存在，直接重命名
        await newDir.parent.create(recursive: true);
        await oldDir.rename(newDir.path);
      } else {
        // 新目录已存在，将旧目录内容逐个移入
        for (final entity in oldDir.listSync()) {
          final targetPath = path.join(newDir.path, path.basename(entity.path));
          if (!File(targetPath).existsSync() &&
              !Directory(targetPath).existsSync()) {
            await entity.rename(targetPath);
          }
        }
        // 删除已空的旧子目录
        if (oldDir.listSync().isEmpty) {
          await oldDir.delete();
        }
      }
      _log.info('已迁移数据目录: ${oldDir.path} -> ${newDir.path}');

      // 清理空的旧父目录
      final oldParent = oldDir.parent;
      if (oldParent.existsSync() && oldParent.listSync().isEmpty) {
        await oldParent.delete();
        _log.info('已删除空的旧目录: ${oldParent.path}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('数据目录迁移失败: $e');
      }
    }
  }

  static String get appSupportDir => _appSupportDir ?? appDir;

  static String get installBinDir {
    return path.join(appSupportDir, 'bin');
  }

  static String get repositoryMirrorFilePath =>
      path.join(installBinDir, 'repository_mirrors.txt');

  static String resolveDownloadDir(String? value) {
    if (value == null || value.isEmpty) {
      return installBinDir;
    }
    if (path.isAbsolute(value)) {
      return value;
    }
    return path.normalize(path.join(appSupportDir, value));
  }

  static String toRelativeDownloadDir(String absolutePath) {
    final relative = path.relative(absolutePath, from: appSupportDir);
    return relative.isEmpty ? '.' : relative;
  }

  static List<String> loadExtraRepositoryUrls() {
    final file = File(repositoryMirrorFilePath);
    if (!file.existsSync()) {
      return [];
    }
    return file
        .readAsLinesSync()
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toList();
  }

  static String? findInPath(String command) {
    final rawPath = Platform.environment['PATH'] ?? '';
    if (rawPath.isEmpty) {
      return null;
    }
    final separator = Platform.isWindows ? ';' : ':';
    final dirs = rawPath
        .split(separator)
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    final hasExtension = path.extension(command).isNotEmpty;
    final extensions = Platform.isWindows
        ? (Platform.environment['PATHEXT'] ?? '.EXE;.BAT;.CMD')
            .split(';')
            .where((value) => value.trim().isNotEmpty)
        : const [''];
    for (final dir in dirs) {
      if (Platform.isWindows && hasExtension) {
        final candidate = path.join(dir, command);
        if (File(candidate).existsSync()) {
          return candidate;
        }
        continue;
      }
      for (final ext in extensions) {
        final suffix = Platform.isWindows ? ext.toLowerCase() : '';
        final candidate = path.join(dir, '$command$suffix');
        if (File(candidate).existsSync()) {
          return candidate;
        }
      }
    }
    return null;
  }

  static String? getDownloadedAdbPath({String? baseDir}) {
    final name = Platform.isWindows ? 'adb.exe' : 'adb';
    final root = baseDir ?? installBinDir;
    final candidate = path.join(root, 'platform-tools', name);
    if (File(candidate).existsSync()) {
      return candidate;
    }
    return getBundledToolPath(name);
  }

  static String? getDownloadedAapt2Path({String? baseDir}) {
    final buildToolsDir = _getLatestBuildToolsDir(baseDir: baseDir);
    if (buildToolsDir == null) {
      return getBundledToolPath(Platform.isWindows ? 'aapt2.exe' : 'aapt2');
    }
    final name = Platform.isWindows ? 'aapt2.exe' : 'aapt2';
    final candidate = path.join(buildToolsDir, name);
    return File(candidate).existsSync() ? candidate : null;
  }

  static String? getDownloadedApksignerPath({String? baseDir}) {
    final buildToolsDir = _getLatestBuildToolsDir(baseDir: baseDir);
    if (buildToolsDir == null) {
      return getBundledToolPath(
          Platform.isWindows ? 'apksigner.bat' : 'apksigner');
    }
    final name = Platform.isWindows ? 'apksigner.bat' : 'apksigner';
    final candidate = path.join(buildToolsDir, name);
    return File(candidate).existsSync() ? candidate : null;
  }

  static String? getBundledToolPath(String name) {
    final candidates = [
      path.join(appDir, 'bin', name),
      path.join(appDir, name),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  static String? _getLatestBuildToolsDir({String? baseDir}) {
    final root = baseDir ?? installBinDir;
    final buildToolsRoot = path.join(root, 'build-tools');
    final dir = Directory(buildToolsRoot);
    if (!dir.existsSync()) {
      return null;
    }
    final versions = dir
        .listSync()
        .whereType<Directory>()
        .map((entry) => path.basename(entry.path))
        .toList();
    if (versions.isEmpty) {
      return null;
    }
    versions.sort(compareVersionDescending);
    return path.join(buildToolsRoot, versions.first);
  }

  static int compareVersionDescending(String a, String b) {
    return -_compareVersion(a, b);
  }

  static int _compareVersion(String a, String b) {
    final aParts = _parseVersion(a);
    final bParts = _parseVersion(b);
    final maxLength = aParts.length > bParts.length ? aParts.length : bParts.length;
    for (var i = 0; i < maxLength; i++) {
      final aValue = i < aParts.length ? aParts[i] : 0;
      final bValue = i < bParts.length ? bParts[i] : 0;
      if (aValue != bValue) {
        return aValue.compareTo(bValue);
      }
    }
    return 0;
  }

  static List<int> _parseVersion(String value) {
    return value
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
  }

}
