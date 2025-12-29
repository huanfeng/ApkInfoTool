import 'dart:developer' as developer;
import 'dart:io';

import 'package:apk_info_tool/config.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

final log = Logger('ExampleLogger');

class LoggerInit {
  static final LoggerInit _instance = LoggerInit._internal();
  static LoggerInit get instance => _instance;

  LoggerInit._internal();

  File? _logFile;
  IOSink? _logSink;

  static initLogger() async {
    Logger.root.level = Level.FINE;
    Logger.root.onRecord.listen((record) {
      if (!kReleaseMode) {
        developer
            .log('${record.level.name}: ${record.time}: ${record.message}');
      }
      LoggerInit.instance.log(record);
    });
  }

  Future<void> init() async {
    if (Config.enableDebug.value) {
      final appDir = await getApplicationSupportDirectory();
      final logPath = path.join(appDir.path, 'debug.log');
      _logFile = File(logPath);
      _logSink = _logFile?.openWrite(mode: FileMode.append);
    }
  }

  void log(LogRecord record) {
    if (Config.enableDebug.value && _logSink != null) {
      _logSink
          ?.writeln('${record.level.name}: ${record.time}: ${record.message}');
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
