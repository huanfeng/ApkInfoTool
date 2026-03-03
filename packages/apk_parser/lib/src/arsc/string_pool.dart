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

    // Read string offsets
    final stringOffsets =
        List<int>.generate(stringCount, (_) => reader.readUint32());

    // Skip style offsets
    for (var i = 0; i < styleCount; i++) {
      reader.readUint32();
    }

    // Parse strings
    final dataStart = headerStart + stringsStart;
    final strings = <String>[];

    for (var i = 0; i < stringCount; i++) {
      reader.position = dataStart + stringOffsets[i];
      if (isUtf8) {
        _readUtf16Length(reader); // skip utf16 length
        final utf8Len = _readUtf8Length(reader);
        final bytes = reader.readUint8List(utf8Len);
        strings.add(utf8.decode(bytes, allowMalformed: true));
      } else {
        final utf16Len = _readUtf16Length(reader);
        final bytes = reader.readUint8List(utf16Len * 2);
        final codeUnits =
            Uint16List.view(bytes.buffer, bytes.offsetInBytes, utf16Len);
        strings.add(String.fromCharCodes(codeUnits));
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
