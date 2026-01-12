import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:apk_info_tool/utils/logger.dart';
import 'package:crypto/crypto.dart';

/// 在独立 isolate 中计算文件的 MD5 和 SHA1 哈希值
/// 使用分块读取，减少内存分配次数
(String, String) _computeHashesInIsolate(String filePath) {
  final file = File(filePath);
  final length = file.lengthSync();
  final input = file.openSync();

  // 对于小文件（<50MB），直接读取全部
  if (length < 50 * 1024 * 1024) {
    try {
      final bytes = input.readSync(length);
      return (md5.convert(bytes).toString(), sha1.convert(bytes).toString());
    } finally {
      input.closeSync();
    }
  }

  // 对于大文件，使用分块读取
  // 使用 BytesBuilder 减少内存分配次数
  const chunkSize = 4 * 1024 * 1024; // 4MB
  final allBytes = BytesBuilder(copy: false);

  try {
    final buffer = Uint8List(chunkSize);
    int bytesRead;
    while ((bytesRead = input.readIntoSync(buffer)) > 0) {
      allBytes.add(buffer.sublist(0, bytesRead));
    }
  } finally {
    input.closeSync();
  }

  final bytes = allBytes.takeBytes();
  return (md5.convert(bytes).toString(), sha1.convert(bytes).toString());
}

/// 计算文件的 MD5 哈希值（在独立 isolate 中执行）
Future<String> computeMd5(String filePath) async {
  try {
    final result = await Isolate.run(() {
      final file = File(filePath);
      final bytes = file.readAsBytesSync();
      return md5.convert(bytes).toString();
    });
    return result;
  } catch (e) {
    log.warning('computeMd5: failed to compute MD5: $e');
    rethrow;
  }
}

/// 计算文件的 SHA1 哈希值（在独立 isolate 中执行）
Future<String> computeSha1(String filePath) async {
  try {
    final result = await Isolate.run(() {
      final file = File(filePath);
      final bytes = file.readAsBytesSync();
      return sha1.convert(bytes).toString();
    });
    return result;
  } catch (e) {
    log.warning('computeSha1: failed to compute SHA1: $e');
    rethrow;
  }
}

/// 同时计算文件的 MD5 和 SHA1 哈希值（在独立 isolate 中执行）
/// 返回 (md5, sha1) 元组
/// 只读取一次文件，同时计算两个哈希值，效率更高
Future<(String, String)> computeFileHashes(String filePath) async {
  try {
    final result = await Isolate.run(() => _computeHashesInIsolate(filePath));
    return result;
  } catch (e) {
    log.warning('computeFileHashes: failed to compute hashes: $e');
    rethrow;
  }
}
