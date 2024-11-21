import 'dart:io';
import 'dart:developer' as developer;

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../config.dart';

class Logger {
  static final Logger _instance = Logger._internal();
  static Logger get instance => _instance;

  Logger._internal();

  File? _logFile;
  IOSink? _logSink;

  Future<void> init() async {
    if (Config.enableDebug) {
      final appDir = await getApplicationSupportDirectory();
      final logPath = path.join(appDir.path, 'debug.log');
      _logFile = File(logPath);
      _logSink = _logFile?.openWrite(mode: FileMode.append);
    }
  }

  void log(String message, {int level = 0}) {
    final now = DateTime.now();

    developer.log(message, time: now, level: level);

    if (Config.enableDebug && _logSink != null) {
      final timeStr =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} "
          "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
      final logMessage = "[$timeStr] $message";
      _logSink?.writeln(logMessage);
    }
  }

  String? get logFilePath => _logFile?.path;

  Future<void> dispose() async {
    await _logSink?.flush();
    await _logSink?.close();
    _logSink = null;
    _logFile = null;
  }
}
