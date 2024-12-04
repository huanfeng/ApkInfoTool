import 'dart:io';
import 'package:path/path.dart' as path;
import '../config.dart';

// 辅助获取命令行路径
class CommandTools {
  static const String adb = "adb";
  static const String aapt2 = "aapt2";
  static const String apksigner = "apksigner";

  static String _getMacOsCmdPath(String cmd) {
    final executable = Platform.resolvedExecutable;
    final parent = File(executable).parent.path;
    return path.join(parent, cmd);
  }

  static String getAdbPath() {
    if (Platform.isMacOS) {
      return _getMacOsCmdPath(adb);
    }
    return Config.adbPath.isEmpty ? adb : Config.adbPath;
  }

  static String getAapt2Path() {
    if (Platform.isMacOS) {
      return _getMacOsCmdPath(aapt2);
    }
    return Config.aapt2Path.isEmpty ? aapt2 : Config.aapt2Path;
  }

  static String getApkSignerPath() {
    if (Platform.isMacOS) {
      // macOS 暂不支持
      return "";
    }
    return Config.apksignerPath.isEmpty ? apksigner : Config.apksignerPath;
  }
}
