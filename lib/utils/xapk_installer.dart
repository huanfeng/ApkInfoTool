import 'dart:io';

import 'package:apk_info_tool/apkparser/xapk_info.dart';
import 'package:apk_info_tool/utils/logger.dart';
import 'package:apk_info_tool/utils/zip_helper.dart';
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';

class XapkInstaller {
  static Future<(bool, String?)> installXapk(
    String deviceId,
    String xapkPath,
    bool allowDowngrade,
    bool forceInstall,
    bool allowTest,
  ) async {
    log.info('Installing XAPK: $xapkPath');
    
    // 创建临时目录
    final tempDir = await Directory.systemTemp.createTemp('xapk_install_');
    try {
      // 解析 XAPK 文件
      final manifest = await parseXapkManifest(xapkPath);
      if (manifest == null) {
        return (false, '无法解析 XAPK 文件');
      }

      // 解压 XAPK 文件
      final inputStream = InputFileStream(xapkPath);
      final archive = ZipDecoder().decodeStream(inputStream);
      for (final file in archive.files) {
        if (file.isFile) {
          final outputStream = OutputFileStream(path.join(tempDir.path, file.name));
          outputStream.writeBytes(file.content as List<int>);
          await outputStream.close();
        }
      }
      inputStream.close();

      // 准备安装参数
      final installArgs = ['-s', deviceId, 'install-multiple'];
      if (allowDowngrade) installArgs.add('-d');
      if (forceInstall) installArgs.add('-r');
      if (allowTest) installArgs.add('-t');

      // 添加主 APK 和所有分包
      final mainApk = path.join(tempDir.path, manifest.splitApks
          .firstWhere((apk) => apk.id == 'base')
          .file);
      installArgs.add(mainApk);

      // 添加所有分包
      for (final splitApk in manifest.splitApks.where((apk) => apk.id != 'base')) {
        installArgs.add(path.join(tempDir.path, splitApk.file));
      }

      // 执行安装命令
      final result = await Process.run('adb', installArgs);
      
      if (result.exitCode == 0) {
        return (true, null);
      } else {
        return (false, result.stderr.toString());
      }
    } catch (e) {
      log.severe('Error installing XAPK: $e');
      return (false, e.toString());
    } finally {
      // 清理临时目录
      try {
        await tempDir.delete(recursive: true);
      } catch (e) {
        log.warning('Error cleaning up temp directory: $e');
      }
    }
  }
}
