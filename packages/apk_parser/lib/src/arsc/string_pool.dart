import 'dart:convert';
import 'dart:typed_data';
import '../byte_data_reader.dart';

/// resources.arsc 字符串池解析
class StringPool {
  final List<String> strings;

  StringPool._(this.strings);

  String? get(int index) {
    if (index < 0 || index >= strings.length) return null;
    return strings[index];
  }

  int get length => strings.length;

  /// 从字节流解析字符串池
  /// reader 应指向 chunk 起始位置（type 字段）
  static StringPool parse(ByteDataReader reader) {
    final headerStart = reader.position;

    final type = reader.readUint16(); // RES_STRING_POOL_TYPE = 0x0001
    final headerSize = reader.readUint16();
    final totalSize = reader.readUint32();
    final stringCount = reader.readUint32();
    final styleCount = reader.readUint32();
    final flags = reader.readUint32(); // UTF8_FLAG = 0x100
    final stringsStart = reader.readUint32();
    final stylesStart = reader.readUint32();

    // Suppress unused variable warnings
    assert(type == type);
    assert(headerSize == headerSize);
    assert(stylesStart == stylesStart);

    final isUtf8 = (flags & 0x100) != 0;

    // Read string offsets (带边界检查，防止损坏的 stringCount 导致越界)
    final offsetsNeeded = (stringCount + styleCount) * 4;
    if (offsetsNeeded > reader.remain) {
      // 数据不足，跳到 chunk 末尾并返回空字符串池
      reader.position = headerStart + totalSize;
      return StringPool._([]);
    }
    final stringOffsets =
        List<int>.generate(stringCount, (_) => reader.readUint32());

    // Skip style offsets
    for (var i = 0; i < styleCount; i++) {
      reader.readUint32();
    }

    // Parse strings
    final dataStart = headerStart + stringsStart;
    final chunkEnd = headerStart + totalSize;
    final strings = <String>[];

    for (var i = 0; i < stringCount; i++) {
      final stringPos = dataStart + stringOffsets[i];
      if (stringPos < 0 || stringPos >= chunkEnd) {
        strings.add('');
        continue;
      }
      reader.position = stringPos;
      try {
        if (isUtf8) {
          _readUtf8Length(reader); // skip utf16 char count
          final utf8Len = _readUtf8Length(reader);
          if (utf8Len < 0 || utf8Len > reader.remain) {
            strings.add('');
            continue;
          }
          final bytes = reader.readUint8List(utf8Len);
          strings.add(utf8.decode(bytes, allowMalformed: true));
        } else {
          final utf16Len = _readUtf16Length(reader);
          final byteLen = utf16Len * 2;
          if (utf16Len < 0 || byteLen > reader.remain) {
            strings.add('');
            continue;
          }
          final bytes = reader.readUint8List(byteLen);
          final codeUnits =
              Uint16List.view(bytes.buffer, bytes.offsetInBytes, utf16Len);
          strings.add(String.fromCharCodes(codeUnits));
        }
      } catch (_) {
        strings.add('');
      }
    }

    // Jump to chunk end
    reader.position = headerStart + totalSize;
    return StringPool._(strings);
  }

  static int _readUtf8Length(ByteDataReader reader) {
    final first = reader.readUint8();
    if ((first & 0x80) == 0) return first;
    final second = reader.readUint8();
    return ((first & 0x7f) << 8) | second;
  }

  static int _readUtf16Length(ByteDataReader reader) {
    final first = reader.readUint16();
    if ((first & 0x8000) == 0) return first;
    final second = reader.readUint16();
    return ((first & 0x7fff) << 16) | second;
  }
}
