import 'dart:typed_data';

import 'package:apk_info_tool/utils/logger.dart';
import 'package:archive/archive.dart';

class ZipHelper {
  InputFileStream? _inputStream;
  Archive? _archive;

  bool open(String path) {
    if (isOpen()) return false;
    _inputStream = InputFileStream(path);
    _archive = ZipDecoder().decodeStream(_inputStream!);
    return true;
  }

  bool isOpen() => _inputStream != null && _archive != null;

  void close() async {
    if (_archive != null) {
      await _archive!.clear();
      _archive = null;
    }
    if (_inputStream != null) {
      _inputStream!.close();
      _inputStream = null;
    }
  }

  Future<Uint8List?> readFileContent(String path) async {
    if (!isOpen()) return null;
    final archive = _archive!;
    try {
      final file = archive.findFile(path);
      return file?.content;
    } catch (e) {
      log.info('readFileContent: 找不到文件: $path');
    }
    return null;
  }

  
}
