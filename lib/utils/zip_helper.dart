import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:apk_info_tool/utils/logger.dart';
import 'package:path/path.dart' as path;

class ZipHelper {
  Archive? _archive;
  String? _filePath;

  bool open(String filePath) {
    try {
      _filePath = filePath;
      final bytes = File(filePath).readAsBytesSync();
      _archive = ZipDecoder().decodeBytes(bytes);
      return true;
    } catch (e) {
      log.severe('Failed to open zip file: $e');
      return false;
    }
  }

  Future<Uint8List?> readFileContent(String fileName) async {
    try {
      final file = _archive?.findFile(fileName);
      return file?.content as Uint8List?;
    } catch (e) {
      log.severe('Failed to read file content: $e');
      return null;
    }
  }

  List<String> listFiles({String? extension}) {
    final files = _archive?.files ?? [];
    final lowerExtension = extension?.toLowerCase();
    return files
        .where((file) => file.isFile)
        .map((file) => file.name)
        .where((name) =>
            lowerExtension == null ||
            name.toLowerCase().endsWith(lowerExtension))
        .toList();
  }

  Future<bool> extractFile(String fileName, String outputPath) async {
    try {
      final file = _archive?.findFile(fileName);
      if (file == null) {
        log.severe('File not found in zip: $fileName');
        return false;
      }

      final outputDir = path.dirname(outputPath);
      await Directory(outputDir).create(recursive: true);
      await File(outputPath).writeAsBytes(file.content as List<int>);
      return true;
    } catch (e) {
      log.severe('Failed to extract file: $e');
      return false;
    }
  }

  void close() {
    _archive = null;
    _filePath = null;
  }
}
