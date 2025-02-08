import 'dart:convert';
import 'dart:io';

import 'package:apk_info_tool/utils/command_tools.dart';
import 'package:apk_info_tool/utils/logger.dart';
import 'package:apk_info_tool/utils/zip_helper.dart';
import 'package:path/path.dart' as path;

class XapkInstaller {
  /// 获取XAPK中的所有分包
  Future<List<String>?> getSplitApks(String xapkPath) async {
    final zip = ZipHelper();
    try {
      if (!zip.open(xapkPath)) return null;
      final manifestData = await zip.readFileContent('manifest.json');
      if (manifestData == null) return null;

      final manifestJson = String.fromCharCodes(manifestData);
      final manifest = Map<String, dynamic>.from(jsonDecode(manifestJson));
      final splitApks = List<Map<String, dynamic>>.from(manifest['split_apks']);
      return splitApks.map((e) => e['file'] as String).toList();
    } catch (e) {
      log.severe('Failed to get split APKs: $e');
      return null;
    } finally {
      zip.close();
    }
  }

  /// 安装XAPK文件
  /// [xapkPath] XAPK文件路径
  /// [deviceId] 设备ID
  /// [installOptions] 安装选项
  /// [selectedSplits] 选中的分包，如果为null则安装所有分包
  Future<bool> install(
    String xapkPath,
    String deviceId,
    List<String> installOptions, {
    Map<String, bool>? selectedSplits,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('xapk_installer');
    try {
      // 解压XAPK
      final zip = ZipHelper();
      if (!zip.open(xapkPath)) {
        log.severe('Failed to open XAPK file');
        return false;
      }

      // 获取所有APK文件
      final splitApks = await getSplitApks(xapkPath);
      if (splitApks == null) {
        log.severe('Failed to get split APKs from manifest');
        return false;
      }

      // 如果没有指定选中的分包，则安装所有分包
      final apksToInstall = selectedSplits == null
          ? splitApks
          : splitApks.where((apk) => selectedSplits[apk] ?? false).toList();

      // 确保至少安装base包
      if (!apksToInstall.any((apk) => path.basenameWithoutExtension(apk) == 'base')) {
        log.severe('Base APK must be installed');
        return false;
      }

      // 解压需要安装的APK
      for (final apk in apksToInstall) {
        final apkPath = path.join(tempDir.path, apk);
        final apkDir = Directory(path.dirname(apkPath));
        if (!await apkDir.exists()) {
          await apkDir.create(recursive: true);
        }
        if (!await zip.extractFile(apk, apkPath)) {
          log.severe('Failed to extract APK: $apk');
          return false;
        }
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
      final result = await Process.run(adbPath, args);
      if (result.exitCode != 0) {
        log.severe('Failed to install APKs: ${result.stderr}');
        return false;
      }

      return true;
    } catch (e) {
      log.severe('Failed to install XAPK: $e');
      return false;
    } finally {
      // 清理临时文件
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }
}
