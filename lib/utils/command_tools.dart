import 'dart:io';
import 'package:path/path.dart' as path;
import '../config.dart';

// 辅助获取命令行路径
class CommandTools {
  static String _getMacOsCmdPath(String cmd) {
    final executable = Platform.resolvedExecutable;
    final parent = File(executable).parent.path;
    return path.join(parent, cmd);
  }

  static String getAdbPath() {
    if (Platform.isMacOS) {
      return _getMacOsCmdPath("adb");
    }
    return Config.adbPath.isEmpty ? "adb" : Config.adbPath;
  }

  static String getAapt2Path() {
    if (Platform.isMacOS) {
      return _getMacOsCmdPath("aapt2");
    }
    return Config.adbPath.isEmpty ? "aapt2" : Config.adbPath;
  }

  static String getApkSignerPath() {
    if (Platform.isMacOS) {
      // macOS 暂不支持
      return "";
    }
    return Config.adbPath.isEmpty ? "apksigner" : Config.adbPath;
  }
}
