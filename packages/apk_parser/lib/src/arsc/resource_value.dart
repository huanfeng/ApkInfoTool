import 'dart:typed_data';
import '../byte_data_reader.dart';

/// Res_value structure
class ResourceValue {
  final int size;
  final int type;
  final int data;

  ResourceValue({required this.size, required this.type, required this.data});

  static const int TYPE_NULL = 0x00;
  static const int TYPE_REFERENCE = 0x01;
  static const int TYPE_ATTRIBUTE = 0x02;
  static const int TYPE_STRING = 0x03;
  static const int TYPE_FLOAT = 0x04;
  static const int TYPE_DIMENSION = 0x05;
  static const int TYPE_FRACTION = 0x06;
  static const int TYPE_INT_DEC = 0x10;
  static const int TYPE_INT_HEX = 0x11;
  static const int TYPE_INT_BOOLEAN = 0x12;
  static const int TYPE_INT_COLOR_ARGB8 = 0x1c;
  static const int TYPE_INT_COLOR_RGB8 = 0x1d;
  static const int TYPE_INT_COLOR_ARGB4 = 0x1e;
  static const int TYPE_INT_COLOR_RGB4 = 0x1f;

  bool get isString => type == TYPE_STRING;
  bool get isReference => type == TYPE_REFERENCE;
  bool get isColor =>
      type == TYPE_INT_COLOR_ARGB8 ||
      type == TYPE_INT_COLOR_RGB8 ||
      type == TYPE_INT_COLOR_ARGB4 ||
      type == TYPE_INT_COLOR_RGB4;

  /// 将颜色值转换为 #AARRGGBB 格式的十六进制字符串
  String? get colorHex {
    if (!isColor) return null;
    switch (type) {
      case TYPE_INT_COLOR_ARGB8:
        return '#${data.toUnsigned(32).toRadixString(16).padLeft(8, '0')}';
      case TYPE_INT_COLOR_RGB8:
        return '#ff${(data & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
      case TYPE_INT_COLOR_ARGB4:
        final a = (data >> 12) & 0xF;
        final r = (data >> 8) & 0xF;
        final g = (data >> 4) & 0xF;
        final b = data & 0xF;
        return '#${(a * 17).toRadixString(16).padLeft(2, '0')}'
            '${(r * 17).toRadixString(16).padLeft(2, '0')}'
            '${(g * 17).toRadixString(16).padLeft(2, '0')}'
            '${(b * 17).toRadixString(16).padLeft(2, '0')}';
      case TYPE_INT_COLOR_RGB4:
        final r = (data >> 8) & 0xF;
        final g = (data >> 4) & 0xF;
        final b = data & 0xF;
        return '#ff'
            '${(r * 17).toRadixString(16).padLeft(2, '0')}'
            '${(g * 17).toRadixString(16).padLeft(2, '0')}'
            '${(b * 17).toRadixString(16).padLeft(2, '0')}';
      default:
        return null;
    }
  }

  static ResourceValue read(ByteDataReader reader) {
    final size = reader.readUint16();
    reader.readUint8(); // res0
    final type = reader.readUint8();
    final data = reader.readUint32();
    return ResourceValue(size: size, type: type, data: data);
  }
}

/// ResTable_entry
class ResourceEntry {
  final int flags;
  final int keyIndex;
  final ResourceValue? value;
  final Map<int, ResourceValue>? mapValues;

  ResourceEntry({
    required this.flags,
    required this.keyIndex,
    this.value,
    this.mapValues,
  });

  bool get isComplex => (flags & 0x0001) != 0;
}

/// ResTable_config
class ResourceConfig {
  final int size;
  final int mcc;
  final int mnc;
  final String language;
  final String country;
  final int density;

  ResourceConfig({
    this.size = 0,
    this.mcc = 0,
    this.mnc = 0,
    this.language = '',
    this.country = '',
    this.density = 0,
  });

  String get locale {
    if (language.isEmpty) return '';
    if (country.isEmpty) return language;
    return '$language-$country';
  }

  static ResourceConfig read(ByteDataReader reader) {
    final startPos = reader.position;
    final size = reader.readUint32();

    if (size < 28) {
      if (size > 4) reader.position = startPos + size;
      return ResourceConfig(size: size);
    }

    final mcc = reader.readUint16();
    final mnc = reader.readUint16();

    final langBytes = reader.readUint8List(2);
    final countryBytes = reader.readUint8List(2);
    final language = _decodeChars(langBytes);
    final country = _decodeChars(countryBytes);

    reader.readUint8(); // orientation
    reader.readUint8(); // touchscreen
    final density = reader.readUint16();

    // Skip remaining config fields
    final remaining = size - (reader.position - startPos);
    if (remaining > 0) {
      reader.skipBytes(remaining);
    }

    return ResourceConfig(
      size: size,
      mcc: mcc,
      mnc: mnc,
      language: language,
      country: country,
      density: density,
    );
  }

  static String _decodeChars(Uint8List bytes) {
    if (bytes[0] == 0 && bytes[1] == 0) return '';
    return String.fromCharCodes(bytes.where((b) => b != 0));
  }
}
