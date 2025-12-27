import 'dart:io';

import 'package:apk_info_tool/config.dart';
import 'package:apk_info_tool/utils/tool_paths.dart';

// 辅助获取命令行路径
class CommandTools {
  static const String adb = "adb";
  static const String aapt2 = "aapt2";
  static const String apksigner = "apksigner";

  static String getAdbPath() {
    return _resolveToolPath(
          adb,
          Config.adbSource.value,
          Config.adbPath.value,
          ToolPaths.getDownloadedAdbPath(
              baseDir: _downloadDirOrDefault()),
          ToolPaths.getBundledToolPath(Platform.isWindows ? 'adb.exe' : 'adb'),
        ) ??
        adb;
  }

  static String? findAdbPath() {
    return _resolveToolPath(
      adb,
      Config.adbSource.value,
      Config.adbPath.value,
      ToolPaths.getDownloadedAdbPath(baseDir: _downloadDirOrDefault()),
      ToolPaths.getBundledToolPath(Platform.isWindows ? 'adb.exe' : 'adb'),
    );
  }

  static String getAapt2Path() {
    return _resolveToolPath(
          aapt2,
          Config.aapt2Source.value,
          Config.aapt2Path.value,
          ToolPaths.getDownloadedAapt2Path(
              baseDir: _downloadDirOrDefault()),
          ToolPaths.getBundledToolPath(
              Platform.isWindows ? 'aapt2.exe' : 'aapt2'),
        ) ??
        aapt2;
  }

  static String? findAapt2Path() {
    return _resolveToolPath(
      aapt2,
      Config.aapt2Source.value,
      Config.aapt2Path.value,
      ToolPaths.getDownloadedAapt2Path(baseDir: _downloadDirOrDefault()),
      ToolPaths.getBundledToolPath(
          Platform.isWindows ? 'aapt2.exe' : 'aapt2'),
    );
  }

  static String getApkSignerPath() {
    return _resolveToolPath(
          apksigner,
          Config.apksignerSource.value,
          Config.apksignerPath.value,
          ToolPaths.getDownloadedApksignerPath(
              baseDir: _downloadDirOrDefault()),
          ToolPaths.getBundledToolPath(
              Platform.isWindows ? 'apksigner.bat' : 'apksigner'),
        ) ??
        apksigner;
  }

  static String? findApkSignerPath() {
    return _resolveToolPath(
      apksigner,
      Config.apksignerSource.value,
      Config.apksignerPath.value,
      ToolPaths.getDownloadedApksignerPath(
          baseDir: _downloadDirOrDefault()),
      ToolPaths.getBundledToolPath(
          Platform.isWindows ? 'apksigner.bat' : 'apksigner'),
    );
  }

  static String _downloadDirOrDefault() {
    return Config.downloadDir.value.isEmpty
        ? ToolPaths.installBinDir
        : Config.downloadDir.value;
  }

  static String? _resolveToolPath(
    String toolName,
    String source,
    String manualPath,
    String? downloadedPath,
    String? bundledPath,
  ) {
    final envPath = ToolPaths.findInPath(toolName);
    final builtinPath = downloadedPath ?? bundledPath;
    switch (source) {
      case Config.kToolSourceBuiltin:
        return builtinPath ?? envPath ?? (manualPath.isNotEmpty ? manualPath : null);
      case Config.kToolSourceCustom:
        return manualPath.isNotEmpty ? manualPath : envPath ?? builtinPath;
      case Config.kToolSourceSystem:
      default:
        return envPath ?? builtinPath ?? (manualPath.isNotEmpty ? manualPath : null);
    }
  }
}
