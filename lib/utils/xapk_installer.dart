import 'dart:convert';
import 'dart:io';

import 'package:apk_info_tool/utils/command_tools.dart';
import 'package:apk_info_tool/utils/logger.dart';
import 'package:apk_info_tool/utils/zip_helper.dart';
import 'package:path/path.dart' as path;

class XapkInstaller {
  bool _isCancelled = false;
  Process? _currentProcess;

  /// 取消当前安装
  void cancel() {
    _isCancelled = true;
    _currentProcess?.kill();
  }

  Future<Map<String, dynamic>?> _loadManifestData(ZipHelper zip) async {
    final manifestData = await zip.readFileContent('manifest.json') ??
        await zip.readFileContent('info.json') ??
        await zip.readFileContent('meta.json');
    if (manifestData == null) return null;
    final manifestJson = String.fromCharCodes(manifestData);
    return Map<String, dynamic>.from(jsonDecode(manifestJson));
  }

  List<String> _splitApksFromManifest(Map<String, dynamic> manifest) {
    final rawSplits = manifest['split_apks'] ??
        manifest['apks'] ??
        manifest['splits'];
    if (rawSplits is List) {
      return rawSplits
          .map((e) {
            if (e is String) return e;
            if (e is Map) {
              final map = Map<String, dynamic>.from(e);
              return (map['file'] ??
                      map['path'] ??
                      map['apk'] ??
                      map['name'])
                  ?.toString();
            }
            return null;
          })
          .whereType<String>()
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return [];
  }

  String? _packageNameFromManifest(Map<String, dynamic> manifest) {
    return (manifest['package_name'] ?? manifest['packageName'])?.toString();
  }

  Map<String, String> _expansionPathsFromManifest(Map<String, dynamic> manifest) {
    final expansions = manifest['expansions'] ?? manifest['obb_files'];
    if (expansions is! List) return {};
    final map = <String, String>{};
    for (final entry in expansions) {
      if (entry is! Map) continue;
      final item = Map<String, dynamic>.from(entry);
      final installPath =
          (item['install_path'] ?? item['path'] ?? item['installPath'])
              ?.toString();
      if (installPath == null || installPath.isEmpty) continue;
      map[path.basename(installPath)] = installPath.replaceAll('\\', '/');
    }
    return map;
  }

  bool _isBaseApk(String apkPath) {
    final name = path.basenameWithoutExtension(apkPath).toLowerCase();
    return name == 'base' ||
        name.startsWith('base-') ||
        name.startsWith('base_') ||
        name.startsWith('base.');
  }

  Future<String?> _extractPackageNameFromApk(String apkPath) async {
    try {
      final aaptPath = CommandTools.findAapt2Path();
      if (aaptPath == null || aaptPath.isEmpty) {
        log.warning('aapt2 not found');
        return null;
      }
      final result = await Process.run(
        aaptPath,
        ['dump', 'badging', apkPath],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0) return null;
      final match =
          RegExp(r"package: name='([^']+)'").firstMatch(result.stdout);
      return match?.group(1);
    } catch (e) {
      log.warning('Failed to parse package name from APK: $e');
      return null;
    }
  }

  /// 获取XAPK中的所有分包
  Future<List<String>?> getSplitApks(String xapkPath) async {
    final zip = ZipHelper();
    try {
      if (!zip.open(xapkPath)) return null;
      final manifest = await _loadManifestData(zip);
      var splitApks =
          manifest == null ? <String>[] : _splitApksFromManifest(manifest);

      if (splitApks.isEmpty) {
        splitApks = zip.listFiles(extension: '.apk');
      }

      if (splitApks.isEmpty) return null;
      splitApks.sort((a, b) {
        final aName = path.basenameWithoutExtension(a).toLowerCase();
        final bName = path.basenameWithoutExtension(b).toLowerCase();
        final aBase = aName == 'base' ||
            aName.startsWith('base-') ||
            aName.startsWith('base_') ||
            aName.startsWith('base.');
        final bBase = bName == 'base' ||
            bName.startsWith('base-') ||
            bName.startsWith('base_') ||
            bName.startsWith('base.');
        if (aBase != bBase) return aBase ? -1 : 1;
        return a.compareTo(b);
      });
      return splitApks;
    } catch (e) {
      log.severe('Failed to get split APKs: $e');
      return null;
    } finally {
      zip.close();
    }
  }

  /// 执行进程并支持取消
  Future<int> _runProcess(String executable, List<String> args) async {
    if (_isCancelled) return -1;

    final process = await Process.start(executable, args);
    _currentProcess = process;

    final exitCode = await process.exitCode;
    _currentProcess = null;

    return exitCode;
  }

  /// 安装XAPK文件
  /// [xapkPath] XAPK文件路径
  /// [deviceId] 设备ID
  /// [installOptions] 安装选项
  /// [selectedSplits] 选中的分包，如果为null则安装所有分包
  /// [isCancelled] 检查是否已取消的回调
  Future<bool> install(
    String xapkPath,
    String deviceId,
    List<String> installOptions, {
    Map<String, bool>? selectedSplits,
    bool Function()? isCancelled,
  }) async {
    _isCancelled = false;
    final tempDir = await Directory.systemTemp.createTemp('xapk_installer');
    final zip = ZipHelper();
    try {
      // 检查是否已取消
      if (isCancelled?.call() ?? false) {
        _isCancelled = true;
        return false;
      }

      // 解压XAPK
      if (!zip.open(xapkPath)) {
        log.severe('Failed to open XAPK file');
        return false;
      }

      final manifest = await _loadManifestData(zip);
      final manifestSplitApks =
          manifest == null ? <String>[] : _splitApksFromManifest(manifest);

      // 获取所有APK文件
      final splitApks = manifestSplitApks.isNotEmpty
          ? manifestSplitApks
          : zip.listFiles(extension: '.apk');
      if (splitApks.isEmpty) {
        log.severe('Failed to get split APKs from manifest');
        return false;
      }

      // 如果没有指定选中的分包，则安装所有分包
      var apksToInstall = selectedSplits == null
          ? splitApks
          : splitApks.where((apk) => selectedSplits[apk] ?? false).toList();

      if (apksToInstall.isEmpty) {
        log.severe('No APKs selected for installation');
        return false;
      }

      // 检查是否已取消
      if (_isCancelled || (isCancelled?.call() ?? false)) {
        return false;
      }

      // 解压需要安装的APK
      String? baseApkPath;
      for (final apk in apksToInstall) {
        if (_isCancelled || (isCancelled?.call() ?? false)) {
          return false;
        }

        final apkPath = path.join(tempDir.path, apk);
        final apkDir = Directory(path.dirname(apkPath));
        if (!await apkDir.exists()) {
          await apkDir.create(recursive: true);
        }
        if (!await zip.extractFile(apk, apkPath)) {
          log.severe('Failed to extract APK: $apk');
          return false;
        }
        if (baseApkPath == null && _isBaseApk(apk)) {
          baseApkPath = apkPath;
        }
      }

      // 检查是否已取消
      if (_isCancelled || (isCancelled?.call() ?? false)) {
        return false;
      }

      // 构建安装命令
      final adbPath = CommandTools.getAdbPath();
      final apkPaths = apksToInstall.map((apk) => path.join(tempDir.path, apk));
      final args = [
        '-s',
        deviceId,
        'install-multiple',
        ...installOptions,
        ...apkPaths,
      ];

      // 执行安装命令
      final exitCode = await _runProcess(adbPath, args);
      if (_isCancelled || (isCancelled?.call() ?? false)) {
        return false;
      }
      if (exitCode != 0) {
        log.severe('Failed to install APKs, exit code: $exitCode');
        return false;
      }

      // 安装OBB文件
      final obbEntries = zip.listFiles(extension: '.obb');
      if (obbEntries.isNotEmpty) {
        String? packageName =
            manifest == null ? null : _packageNameFromManifest(manifest);
        packageName ??= baseApkPath == null
            ? null
            : await _extractPackageNameFromApk(baseApkPath);
        final expansionPaths =
            manifest == null ? <String, String>{} : _expansionPathsFromManifest(
                manifest,
              );

        for (final obb in obbEntries) {
          // 检查是否已取消
          if (_isCancelled || (isCancelled?.call() ?? false)) {
            return false;
          }

          final obbLocalPath = path.join(tempDir.path, obb);
          final obbDir = Directory(path.dirname(obbLocalPath));
          if (!await obbDir.exists()) {
            await obbDir.create(recursive: true);
          }
          if (!await zip.extractFile(obb, obbLocalPath)) {
            log.severe('Failed to extract OBB: $obb');
            return false;
          }

          final normalized = obb.replaceAll('\\', '/');
          final obbName = path.basename(obb);
          String? devicePath = expansionPaths[obbName];
          if (devicePath == null) {
            final marker = 'Android/obb/';
            final markerIndex = normalized.indexOf(marker);
            if (markerIndex != -1) {
              devicePath =
                  '/sdcard/${normalized.substring(markerIndex)}';
            } else if (packageName != null && packageName.isNotEmpty) {
              devicePath = '/sdcard/Android/obb/$packageName/$obbName';
            }
          }

          if (devicePath == null || devicePath.isEmpty) {
            log.warning('Skip OBB without install path: $obb');
            continue;
          }

          final deviceDir = path.posix.dirname(devicePath);
          final mkdirExitCode = await _runProcess(
            adbPath,
            ['-s', deviceId, 'shell', 'mkdir', '-p', deviceDir],
          );
          if (_isCancelled || (isCancelled?.call() ?? false)) {
            return false;
          }
          if (mkdirExitCode != 0) {
            log.severe('Failed to create OBB dir');
            return false;
          }

          final pushExitCode = await _runProcess(
            adbPath,
            ['-s', deviceId, 'push', obbLocalPath, devicePath],
          );
          if (_isCancelled || (isCancelled?.call() ?? false)) {
            return false;
          }
          if (pushExitCode != 0) {
            log.severe('Failed to push OBB');
            return false;
          }
        }
      }

      return true;
    } catch (e) {
      log.severe('Failed to install XAPK: $e');
      return false;
    } finally {
      _currentProcess = null;
      zip.close();
      // 清理临时文件
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }
}
