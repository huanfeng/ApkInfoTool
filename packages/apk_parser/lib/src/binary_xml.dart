// ignore_for_file: constant_identifier_names
// from: https://github.com/google/android-classyshark/blob/master/ClassySharkWS/src/com/google/classyshark/silverghost/translator/xml/XmlDecompressor.java

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'byte_data_reader.dart';

class XmlElement {
  String name = "";
  Map<String, String> attributes = {};
  List<XmlElement> children = [];

  /// 混淆属性中通过非标准字段（如 ns）恢复的额外字符串值，
  /// 供 ManifestParser 启发式查找使用
  List<String> extraStrings = [];
}

class XmlDocument extends XmlElement {}

/// Android 框架属性资源 ID → 属性名的映射
const Map<int, String> _kFrameworkAttrNames = {
  0x01010000: 'theme',
  0x01010001: 'label',
  0x01010002: 'icon',
  0x01010003: 'name',
  0x01010006: 'permission',
  0x0101000f: 'value',
  0x01010010: 'resource',
  0x01010011: 'mimeType',
  0x01010012: 'scheme',
  0x01010013: 'host',
  0x01010018: 'debuggable',
  0x0101001e: 'authorities',
  0x0101020c: 'minSdkVersion',
  0x01010270: 'targetSdkVersion',
  0x0101021b: 'versionCode',
  0x0101021c: 'versionName',
  0x0101028e: 'required',
  0x010102b7: 'screenOrientation',
  0x01010572: 'compileSdkVersion',
  0x01010573: 'compileSdkVersionCodename',
  0x01010281: 'smallScreens',
  0x01010282: 'normalScreens',
  0x01010283: 'largeScreens',
  0x01010284: 'resizeable',
  0x010102bf: 'xlargeScreens',
  0x0101026c: 'anyDensity',
  0x01010272: 'hardwareAccelerated',
  0x0101027f: 'configChanges',
  0x01010280: 'screenSize',
  0x01010324: 'exported',
  0x01010398: 'banner',
  0x010103f2: 'roundIcon',
  0x0101054b: 'appComponentFactory',
  0x0101000e: 'persistent',
  0x01010019: 'enabled',
  0x01010275: 'installLocation',
  0x0101042e: 'extractNativeLibs',
  0x0101054c: 'classLoader',
  0x010104d8: 'networkSecurityConfig',
  0x01010009: 'process',
  0x010102d3: 'targetSandboxVersion',
  0x01010285: 'requiresSmallestWidthDp',
  0x01010286: 'compatibleWidthLimitDp',
  0x0101028d: 'largestWidthLimitDp',
  0x010104f6: 'isGame',
  0x010103af: 'requestLegacyExternalStorage',
  0x010104ec: 'localeConfig',
  0x0101052c: 'enableOnBackInvokedCallback',
  0x01010004: 'launchMode',
  0x01010007: 'taskAffinity',
  0x01010008: 'multiprocess',
  0x0101000a: 'allowTaskReparenting',
  0x01010014: 'port',
  0x01010015: 'path',
  0x01010016: 'pathPrefix',
  0x01010017: 'pathPattern',
  0x01010020: 'hasCode',
  0x01010024: 'allowClearUserData',
  0x01010271: 'maxSdkVersion',
  0x01010273: 'supportsRtl',
  0x01010326: 'parentActivityName',
  0x01010473: 'usesCleartextTraffic',
  0x0101054a: 'appCategory',
};

class BinaryXmlDecompressor {
  // Identifiers for XML Chunk Types
  static const int PACKED_XML_IDENTIFIER = 0x00080003;
  static const int START_NAMESPACE_TAG = 0x0100;
  static const int END_NAMESPACE_TAG = 0x0101;
  static const int START_ELEMENT_TAG = 0x0102;
  static const int END_ELEMENT_TAG = 0x0103;
  static const int CDATA_TAG = 0x0104;
  static const int ATTRS_MARKER = 0x00140014;

  static const int RES_XML_RESOURCE_MAP_TYPE = 0x180;
  static const int RES_XML_FIRST_CHUNK_TYPE = 0x100;
  static const int RES_XML_STRING_TABLE = 0x0001;

  // Resource Types
  static const int RES_TYPE_NULL = 0x00;
  static const int RES_TYPE_REFERENCE = 0x01;
  static const int RES_TYPE_ATTRIBUTE = 0x02;
  static const int RES_TYPE_STRING = 0x03;
  static const int RES_TYPE_FLOAT = 0x04;
  static const int RES_TYPE_DIMENSION = 0x05;
  static const int RES_TYPE_FRACTION = 0x06;
  static const int RES_TYPE_DYNAMIC_REFERENCE = 0x07;
  static const int RES_TYPE_INT_DEC = 0x10;
  static const int RES_TYPE_INT_HEX = 0x11;
  static const int RES_TYPE_INT_BOOLEAN = 0x12;

  // Color Types
  static const int RES_TYPE_INT_COLOR_ARGB8 = 0x1c;
  static const int RES_TYPE_INT_COLOR_RGB8 = 0x1d;
  static const int RES_TYPE_INT_COLOR_ARGB4 = 0x1e;
  static const int RES_TYPE_INT_COLOR_RGB4 = 0x1f;

  // Complex Types
  static const int COMPLEX_UNIT_SHIFT = 0;
  static const int COMPLEX_UNIT_MASK = 0xf;
  static const int COMPLEX_MANTISSA_SHIFT = 8;
  static const int COMPLEX_MANTISSA_MASK = 0xffffff;
  static const int COMPLEX_RADIX_SHIFT = 4;
  static const int COMPLEX_RADIX_MASK = 0x3;
  static const int COMPLEX_UNIT_FRACTION = 0;
  static const int COMPLEX_UNIT_FRACTION_PARENT = 1;
  static const List<double> RADIX_MULTS = [
    1.0,
    1.0 / (1 << 7),
    1.0 / (1 << 15),
    1.0 / (1 << 23),
  ];

  static const int RES_VALUE_TRUE = 0xffffffff;
  static const int RES_VALUE_FALSE = 0x00000000;

  // Print Defeine
  static const int IDENT_SIZE = 2;
  static const int ATTR_IDENT_SIZE = 4;

  static const int UTF8_FLAG = 0x100;

  bool appendNamespaces = false;
  bool appendCData = true;

  String decompressXml(Uint8List bytes) {
    final reader = ByteDataReader.wrapUint8List(bytes, endian: Endian.little);
    StringBuffer result =
        StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n');

    // Getting and checking the marker for a valid XML file
    int fileMarker = reader.readInt32();
    if (fileMarker != PACKED_XML_IDENTIFIER) {
      throw FormatException(
          'Invalid packed XML identifier. Expecting 0x${PACKED_XML_IDENTIFIER.toRadixString(16)}, found 0x${fileMarker.toRadixString(16)}');
    }

    reader.skipBytes(4);

    List<String> packedStrings = parseStrings(reader);

    // Resource ID Map: 字符串池索引 → 框架资源 ID
    List<int> resourceIdMap = [];

    int ident = 0;
    while (reader.remain >= 8) {
      final chunkStart = reader.position;
      int tag = reader.readInt16();
      int headerSize = reader.readInt16();
      int chunkSize = reader.readInt32();
      if (chunkSize < 8) {
        throw FormatException('Invalid chunk size: $chunkSize');
      }
      final chunkEnd = chunkStart + chunkSize;
      if (chunkEnd > reader.length) {
        throw FormatException(
            'Chunk out of bounds: start=$chunkStart size=$chunkSize total=${reader.length}');
      }

      switch (tag) {
        case START_NAMESPACE_TAG:
        case END_NAMESPACE_TAG:
          break;
        case RES_XML_RESOURCE_MAP_TYPE:
          resourceIdMap = _parseResourceIdMap(
              reader, chunkStart, headerSize, chunkSize);
          break;
        case START_ELEMENT_TAG:
          parseStartTag(result, reader, packedStrings, resourceIdMap, ident);
          ident++;
          break;
        case END_ELEMENT_TAG:
          ident = math.max(ident - 1, 0);
          parseEndTag(result, reader, packedStrings, ident);
          break;
        case CDATA_TAG:
          parseCDataTag(result, reader, packedStrings, ident);
          break;
        default:
          break;
      }

      // Always align to chunk boundary, even if parse consumed fewer bytes.
      if (reader.position != chunkEnd) {
        reader.position = chunkEnd;
      }
    }

    return result.toString();
  }

  /// Decompress binary XML to a structured [XmlDocument] tree.
  XmlDocument decompressToDocument(Uint8List bytes) {
    final reader = ByteDataReader.wrapUint8List(bytes, endian: Endian.little);
    int fileMarker = reader.readInt32();
    if (fileMarker != PACKED_XML_IDENTIFIER) {
      throw FormatException('Invalid packed XML identifier');
    }
    reader.skipBytes(4);
    List<String> packedStrings = parseStrings(reader);

    // Resource ID Map: 字符串池索引 → 框架资源 ID
    List<int> resourceIdMap = [];

    final doc = XmlDocument();
    final stack = <XmlElement>[doc];

    while (reader.remain >= 8) {
      final chunkStart = reader.position;
      int tag = reader.readInt16();
      int headerSize = reader.readInt16();
      int chunkSize = reader.readInt32();
      if (chunkSize < 8) break;
      final chunkEnd = chunkStart + chunkSize;
      if (chunkEnd > reader.length) break;

      switch (tag) {
        case START_NAMESPACE_TAG:
        case END_NAMESPACE_TAG:
          break;
        case RES_XML_RESOURCE_MAP_TYPE:
          resourceIdMap = _parseResourceIdMap(
              reader, chunkStart, headerSize, chunkSize);
          break;
        case START_ELEMENT_TAG:
          final element =
              _parseStartElement(reader, packedStrings, resourceIdMap, chunkEnd);
          stack.last.children.add(element);
          stack.add(element);
          break;
        case END_ELEMENT_TAG:
          reader.skipBytes(8);
          reader.readInt32(); // namespace
          reader.readInt32(); // name
          if (stack.length > 1) stack.removeLast();
          break;
        case CDATA_TAG:
          // Skip CDATA in document mode
          reader.skipBytes(8);
          reader.readInt32();
          reader.skipBytes(8);
          break;
      }
      if (reader.position != chunkEnd) reader.position = chunkEnd;
    }
    return doc;
  }

  /// Parse a START_ELEMENT_TAG into an [XmlElement] with name and attributes.
  /// [chunkEnd] 是当前 chunk 的结束位置，用于读取移位属性的溢出数据。
  XmlElement _parseStartElement(
      ByteDataReader reader, List<String> packedStrings,
      List<int> resourceIdMap, int chunkEnd) {
    final element = XmlElement();

    // Skip line number and comment
    reader.skipBytes(8);
    reader.readInt32(); // namespace
    int nameStringIndex = reader.readInt32();
    element.name = _resolveStringOrResourceId(
        packedStrings, resourceIdMap, nameStringIndex);
    if (element.name.isEmpty) element.name = 'unknown';

    // Parse attributes
    int marker = reader.readInt32();
    // marker 包含 attrStart (低16位) 和 attrSize (高16位)
    // 标准值: attrStart=20, attrSize=20 → marker=0x00140014
    // 混淆 APK 可能修改 attrSize（如 24），需按实际大小跳过额外字节
    final attrSize = (marker >> 16) & 0xFFFF;
    final attrExtraBytes = (attrSize > 20) ? attrSize - 20 : 0;

    int numAttributes = reader.readUint16();
    reader.skipBytes(6);

    // 缓冲所有原始属性数据（标准 20 字节 + 可能的额外填充）
    final rawAttrs = <List<int>>[];
    for (int i = 0; i < numAttributes; i++) {
      rawAttrs.add([
        reader.readInt32(), // 0: ns
        reader.readInt32(), // 1: name
        reader.readInt32(), // 2: rawValue
        reader.readUint16(), // 3: tvSize
        reader.readUint8(), // 4: tvRes0
        reader.readUint8(), // 5: tvType
        reader.readInt32(), // 6: tvData
      ]);
      // 跳过混淆器注入的额外填充字节
      if (attrExtraBytes > 0) {
        reader.skipBytes(attrExtraBytes);
      }
    }

    // 读取溢出字节（移位属性在最后一个时，值在 chunk 末尾填充区）
    int overflowValue = 0;
    bool hasOverflow = false;
    if (reader.position + 4 <= chunkEnd) {
      overflowValue = reader.readInt32();
      hasOverflow = true;
    }

    // 处理属性：检测移位属性模式并恢复值
    for (int i = 0; i < rawAttrs.length; i++) {
      final attr = rawAttrs[i];
      int attrNs = attr[0];
      int attrName = attr[1];
      int attrRawValue = attr[2];
      int attrType = attr[5];
      int attrData = attr[6];

      // 检测移位属性：type=0xFF 且 data 看起来像 typedValue header
      if (_isShiftedAttribute(attrType, attrData)) {
        final shiftedType = (attrData >> 24) & 0xFF;
        // 真实属性名在 rawValue 位置
        final realNameIdx = attrRawValue;
        // 真实值在下一个属性的 ns 字段或溢出区
        int? realValue;
        if (i + 1 < rawAttrs.length) {
          realValue = rawAttrs[i + 1][0]; // 下一个属性的 ns 字段
        } else if (hasOverflow) {
          realValue = overflowValue;
        }

        if (realValue != null) {
          String attributeName = _resolveStringOrResourceId(
              packedStrings, resourceIdMap, realNameIdx);
          if (attributeName.isEmpty) attributeName = "attr_$realNameIdx";

          String attributeValue = _resolveAttributeValue(
              shiftedType, realValue, -1, packedStrings,
              resIdMapLength: resourceIdMap.length);

          if (attributeValue != '<empty>' && attributeValue != '<undefined>') {
            // 移位属性恢复的值优先级高
            element.attributes[attributeName] = attributeValue;
          }
        }
        continue;
      }

      // 普通属性处理
      String attributeName = _resolveStringOrResourceId(
          packedStrings, resourceIdMap, attrName);
      if (attributeName.isEmpty) attributeName = "attr_$attrName";

      String attributeValue =
          _resolveAttributeValue(attrType, attrData,
              attrRawValue, packedStrings,
              resIdMapLength: resourceIdMap.length);

      // 不用空值覆盖已有的有效值（混淆 APK 可能有重复属性名）
      final existing = element.attributes[attributeName];
      if (existing != null &&
          existing.isNotEmpty &&
          existing != '<empty>' &&
          existing != '<undefined>' &&
          (attributeValue == '<empty>' || attributeValue == '<undefined>')) {
        if (attrType == RES_TYPE_NULL || attrType == 0xFF) {
          _rescueNsValue(element, packedStrings, resourceIdMap, attrNs);
        }
        continue;
      }
      element.attributes[attributeName] = attributeValue;

      // 对于混淆属性，也检查 ns 字段中是否有被藏匿的值
      if (attrType == RES_TYPE_NULL || attrType == 0xFF) {
        _rescueNsValue(element, packedStrings, resourceIdMap, attrNs);
      }
    }

    return element;
  }

  /// 检测移位属性：type=0xFF 且 data 字段包含有效的 typedValue header
  bool _isShiftedAttribute(int type, int data) {
    if (type != 0xFF) return false;
    // 提取移位 header 中的字段
    final shiftedSize = data & 0xFFFF;
    final shiftedType = (data >> 24) & 0xFF;
    // 有效的 Res_value size 通常是 8 或 12
    if (shiftedSize != 0x0008 && shiftedSize != 0x000c) return false;
    // 有效的类型值
    return shiftedType == RES_TYPE_REFERENCE ||
        shiftedType == RES_TYPE_STRING ||
        shiftedType == RES_TYPE_INT_DEC ||
        shiftedType == RES_TYPE_INT_HEX ||
        shiftedType == RES_TYPE_INT_BOOLEAN ||
        shiftedType == RES_TYPE_INT_COLOR_ARGB8 ||
        shiftedType == RES_TYPE_INT_COLOR_RGB8;
  }

  /// Resolve an attribute's typed value to a string representation.
  /// Handles all the same type cases as [parseAttributes].
  /// [resIdMapLength] 用于过滤 rawValue 回退（Resource ID Map 范围内是属性名）
  String _resolveAttributeValue(int attrValueType, int attributeResourceId,
      int attributeValueIndex, List<String> packedStrings,
      {int resIdMapLength = 0}) {
    switch (attrValueType) {
      case RES_TYPE_NULL:
        // 混淆 APK 可能将 typed value 置空，但 rawValue 仍有效
        // 仅在 rawValue 索引超出 Resource ID Map 范围时使用
        // (Resource ID Map 范围内的字符串是属性名，不是属性值)
        if (attributeValueIndex >= resIdMapLength &&
            attributeValueIndex >= 0 &&
            attributeValueIndex < packedStrings.length) {
          final rawStr = packedStrings[attributeValueIndex];
          if (rawStr.isNotEmpty &&
              !rawStr.startsWith('http://') &&
              !rawStr.startsWith('https://')) {
            return rawStr;
          }
        }
        return (attributeResourceId == 0) ? "<undefined>" : "<empty>";
      case RES_TYPE_REFERENCE:
        return '@res/0x${attributeResourceId.toRadixString(16)}';
      case RES_TYPE_ATTRIBUTE:
        return '@attr/0x${attributeResourceId.toRadixString(16)}';
      case RES_TYPE_STRING:
        return _safeGet(packedStrings, attributeValueIndex);
      case RES_TYPE_FLOAT:
        final buf = Uint8List(4);
        buf[0] = attributeResourceId & 0xff;
        buf[1] = (attributeResourceId >> 8) & 0xff;
        buf[2] = (attributeResourceId >> 16) & 0xff;
        buf[3] = (attributeResourceId >> 24) & 0xff;
        final value = ByteData.sublistView(buf).buffer.asFloat32List().first;
        return value.toString();
      case RES_TYPE_DIMENSION:
        double value = resValue(attributeResourceId);
        String type = getDimensionType(attributeResourceId);
        return '$value$type';
      case RES_TYPE_FRACTION:
        final value = resValue(attributeResourceId);
        final type = getFractionType(attributeResourceId);
        return '$value$type';
      case RES_TYPE_DYNAMIC_REFERENCE:
        return '@dyn/0x${attributeResourceId.toRadixString(16)}';
      case RES_TYPE_INT_DEC:
        return attributeResourceId.toString();
      case RES_TYPE_INT_HEX:
        return '0x${(attributeResourceId & 0xffffffff).toRadixString(16)}';
      case RES_TYPE_INT_BOOLEAN:
        return (attributeResourceId == RES_VALUE_TRUE) ? 'true' : 'false';
      case RES_TYPE_INT_COLOR_ARGB8:
      case RES_TYPE_INT_COLOR_ARGB4:
        return '#${(attributeResourceId & 0xffffffff).toRadixString(16).padLeft(8, '0')}';
      case RES_TYPE_INT_COLOR_RGB8:
      case RES_TYPE_INT_COLOR_RGB4:
        return '#ff${(attributeResourceId & 0x00ffffff).toRadixString(16).padLeft(6, '0')}';
      default:
        return '0x${(attributeResourceId & 0xffffffff).toRadixString(16)}';
    }
  }

  void parseCDataTag(
      StringBuffer sb, ByteDataReader reader, List<String> strings, int ident) {
    //Skipping 3 unknowns integers:
    reader.skipBytes(8);
    int nameStringIndex = reader.readInt32();
    //Skipping 2 more unknown integers.
    reader.skipBytes(8);
    if (appendCData) {
      sb.write(' ' * (ident * IDENT_SIZE));
      sb.write('<![CDATA[\n');
      sb.write(' ' * (ident * IDENT_SIZE + 1));
      sb.write(_safeGet(strings, nameStringIndex));
      sb.write(' ' * (ident * IDENT_SIZE));
      sb.write(']]>\n');
    }
  }

  void parseEndTag(
      StringBuffer sb, ByteDataReader reader, List<String> strings, int ident) {
    sb.write(' ' * (ident * IDENT_SIZE));
    sb.write('</');
    //Skipping 3 integers:
    // 1 - a flag?, like 38000000
    // 2 - Line of where this tag appeared in the original source file
    // 3 - Unknown: always FFFFFFFF?
    reader.skipBytes(8);
    int namespaceStringIndex = reader.readInt32();
    if (appendNamespaces && namespaceStringIndex >= 0) {
      sb.write(_safeGet(strings, namespaceStringIndex));
      sb.write(':');
    }

    int nameStringIndex = reader.readInt32();
    sb.write(_safeGet(strings, nameStringIndex));
    sb.write('>\n');
  }

  void parseStartTag(
      StringBuffer sb, ByteDataReader reader, List<String> strings,
      List<int> resourceIdMap, int ident) {
    sb.write(' ' * (ident * IDENT_SIZE));
    sb.write('<');
    //Skipping 3 integers:
    // 1 - a flag?, like 38000000
    // 2 - Line of where this tag appeared in the original source file
    // 3 - Unknown: always FFFFFFFF?
    reader.skipBytes(8);
    int namespaceStringIndex = reader.readInt32();
    if (appendNamespaces && namespaceStringIndex >= 0) {
      sb.write(_safeGet(strings, namespaceStringIndex));
      sb.write(':');
    }

    int nameStringIndex = reader.readInt32();
    final tagName = _resolveStringOrResourceId(
        strings, resourceIdMap, nameStringIndex);
    sb.write(tagName.isNotEmpty ? tagName : 'unknown');
    parseAttributes(sb, reader, strings, resourceIdMap, ident);
    sb.write('>\n');
  }

  void parseAttributes(
      StringBuffer sb, ByteDataReader reader, List<String> strings,
      List<int> resourceIdMap, int ident) {
    int marker = reader.readInt32();
    if (marker != ATTRS_MARKER) {
      // Non-fatal marker mismatch
    }

    // ResXMLTree_attrExt:
    // uint16 attributeCount, uint16 idIndex, uint16 classIndex, uint16 styleIndex
    int numAttributes = reader.readUint16();
    reader.skipBytes(6);

    for (int i = 0; i < numAttributes; i++) {
      sb.write('\n');
      sb.write(' ' * (ident * IDENT_SIZE + ATTR_IDENT_SIZE));

      int attributeNamespaceIndex = reader.readInt32();
      int attributeNameIndex = reader.readInt32();
      int attributeValueIndex = reader.readInt32();

      // typedValue header: size(uint16), res0(uint8), dataType(uint8)
      reader.readUint16(); // size, usually 8
      reader.readUint8(); // res0
      int attrValueType = reader.readUint8();
      int attributeResourceId = reader.readInt32();

      if (appendNamespaces && attributeNamespaceIndex >= 0) {
        sb.write(_safeGet(strings, attributeNamespaceIndex));
        sb.write(":");
      }

      String attributeName = _resolveStringOrResourceId(
          strings, resourceIdMap, attributeNameIndex);
      if (attributeName.isEmpty) attributeName = "attr_$attributeNameIndex";

      String attributeValue;
      switch (attrValueType) {
        case RES_TYPE_NULL:
          // 混淆 APK: typed value 为空时尝试 rawValue
          // 仅在 rawValue 索引超出 Resource ID Map 范围时使用
          if (attributeValueIndex >= resourceIdMap.length &&
              attributeValueIndex >= 0 &&
              attributeValueIndex < strings.length) {
            final rawStr = strings[attributeValueIndex];
            if (rawStr.isNotEmpty &&
                !rawStr.startsWith('http://') &&
                !rawStr.startsWith('https://')) {
              attributeValue = rawStr;
              break;
            }
          }
          attributeValue =
              (attributeResourceId == 0) ? "<undefined>" : "<empty>";
          break;
        case RES_TYPE_REFERENCE:
          attributeValue = '@res/0x${attributeResourceId.toRadixString(16)}';
          break;
        case RES_TYPE_ATTRIBUTE:
          attributeValue = '@attr/0x${attributeResourceId.toRadixString(16)}';
          break;
        case RES_TYPE_STRING:
          attributeValue = _safeGet(strings, attributeValueIndex);
          break;
        case RES_TYPE_FLOAT:
          final buf = Uint8List(4);
          buf[0] = attributeResourceId & 0xff;
          buf[1] = (attributeResourceId >> 8) & 0xff;
          buf[2] = (attributeResourceId >> 16) & 0xff;
          buf[3] = (attributeResourceId >> 24) & 0xff;
          final value = ByteData.sublistView(buf).buffer.asFloat32List().first;
          attributeValue = value.toString();
          break;
        case RES_TYPE_DIMENSION:
          double value = resValue(attributeResourceId);
          String type = getDimensionType(attributeResourceId);
          attributeValue = '$value$type';
          break;
        case RES_TYPE_FRACTION:
          final value = resValue(attributeResourceId);
          final type = getFractionType(attributeResourceId);
          attributeValue = '$value$type';
          break;
        case RES_TYPE_DYNAMIC_REFERENCE:
          attributeValue = '@dyn/0x${attributeResourceId.toRadixString(16)}';
          break;
        case RES_TYPE_INT_DEC:
          attributeValue = attributeResourceId.toString();
          break;
        case RES_TYPE_INT_HEX:
          attributeValue =
              '0x${(attributeResourceId & 0xffffffff).toRadixString(16)}';
          break;
        case RES_TYPE_INT_BOOLEAN:
          attributeValue =
              (attributeResourceId == RES_VALUE_TRUE) ? 'true' : 'false';
          break;
        case RES_TYPE_INT_COLOR_ARGB8:
        case RES_TYPE_INT_COLOR_ARGB4:
          // ARGB: output all 4 channels as-is with # prefix
          attributeValue =
              '#${(attributeResourceId & 0xffffffff).toRadixString(16).padLeft(8, '0')}';
          break;
        case RES_TYPE_INT_COLOR_RGB8:
        case RES_TYPE_INT_COLOR_RGB4:
          // RGB: alpha is implicitly 0xFF
          attributeValue =
              '#ff${(attributeResourceId & 0x00ffffff).toRadixString(16).padLeft(6, '0')}';
          break;
        default:
          attributeValue =
              '0x${(attributeResourceId & 0xffffffff).toRadixString(16)}';
      }

      sb.write('$attributeName="$attributeValue"');
    }
  }

  List<String> parseStrings(ByteDataReader reader) {
    int stringMarker = reader.readInt16();
    if (stringMarker != RES_XML_STRING_TABLE) {
      throw FormatException(
          'Invalid String table identifier. Expecting 0x${RES_XML_STRING_TABLE.toRadixString(16)}, found 0x${stringMarker.toRadixString(16)}');
    }
    int headerSize = reader.readInt16();
    int chunkSize = reader.readInt32();
    int numStrings = reader.readInt32();
    int numStyles = reader.readInt32();
    int flags = reader.readInt32();
    int stringStart = reader.readInt32();
    reader.readInt32(); // stylesStart

    bool isUtf8Encoded = (flags & UTF8_FLAG) != 0;

    return parseUsingByteBuffer(
      chunkSize,
      headerSize,
      numStrings,
      numStyles,
      isUtf8Encoded,
      stringStart,
      reader,
    );
  }

  List<String> parseUsingByteBuffer(
      int chunkSize,
      int headerSize,
      int numStrings,
      int numStyles,
      bool isUtf8Encoded,
      int stringStart,
      ByteDataReader reader) {
    int dataSize = chunkSize - headerSize;
    Uint8List buffer = Uint8List(dataSize);
    reader.readFully(buffer);
    ByteDataReader bdr = ByteDataReader.wrapUint8List(buffer);

    List<String> packedStrings = List<String>.filled(numStrings, '');
    List<int> offsets = List<int>.filled(numStrings, 0);

    for (int i = 0; i < numStrings; i++) {
      offsets[i] = bdr.readInt32();
    }

    // Skip style offsets table if present.
    if (numStyles > 0) {
      bdr.skipBytes(numStyles * 4);
    }

    final stringsStart = stringStart - headerSize;
    if (stringsStart < 0 || stringsStart >= dataSize) {
      throw FormatException(
          'Invalid string pool start: stringStart=$stringStart headerSize=$headerSize dataSize=$dataSize');
    }

    // Read the strings from each offset
    for (int i = 0; i < numStrings; i++) {
      final stringPos = stringsStart + offsets[i];
      if (stringPos < 0 || stringPos >= bdr.length) continue;
      bdr.position = stringPos;
      try {
        if (isUtf8Encoded) {
          _readLength8(bdr); // utf16 length, not needed for decoding.
          final utf8Len = _readLength8(bdr);
          if (utf8Len < 0 || utf8Len > bdr.remain) continue;
          final bytes = bdr.readUint8List(utf8Len);
          packedStrings[i] = utf8.decode(bytes, allowMalformed: true);
        } else {
          final utf16Len = _readLength16(bdr);
          final byteLen = utf16Len * 2;
          if (utf16Len < 0 || byteLen > bdr.remain) continue;
          final bytes = bdr.readUint8List(byteLen);
          final codeUnits = Uint16List.view(
            bytes.buffer,
            bytes.offsetInBytes,
            utf16Len,
          );
          packedStrings[i] = String.fromCharCodes(codeUnits);
        }
      } catch (_) {
        // 跳过解析失败的字符串
      }
    }
    return packedStrings;
  }

  int _readLength8(ByteDataReader reader) {
    final first = reader.readUint8();
    if ((first & 0x80) == 0) {
      return first;
    }
    final second = reader.readUint8();
    return ((first & 0x7f) << 8) | second;
  }

  int _readLength16(ByteDataReader reader) {
    final first = reader.readUint16();
    if ((first & 0x8000) == 0) {
      return first;
    }
    final second = reader.readUint16();
    return ((first & 0x7fff) << 16) | second;
  }

  /// 从混淆属性的 ns 字段中恢复可能被藏匿的值字符串
  void _rescueNsValue(XmlElement element, List<String> packedStrings,
      List<int> resourceIdMap, int nsIndex) {
    if (nsIndex >= resourceIdMap.length &&
        nsIndex >= 0 &&
        nsIndex < packedStrings.length) {
      final nsStr = packedStrings[nsIndex];
      if (nsStr.isNotEmpty &&
          !nsStr.startsWith('http://') &&
          !nsStr.startsWith('https://')) {
        element.extraStrings.add(nsStr);
      }
    }
  }

  /// 解析 Resource ID Map chunk (0x0180)
  /// 返回一个列表，索引对应字符串池索引，值为 Android 框架资源 ID
  List<int> _parseResourceIdMap(
      ByteDataReader reader, int chunkStart, int headerSize, int chunkSize) {
    final dataStart = chunkStart + headerSize;
    final dataSize = chunkSize - headerSize;
    final count = dataSize ~/ 4;
    reader.position = dataStart;
    return List<int>.generate(count, (_) => reader.readUint32());
  }

  /// 通过字符串池索引获取名称，优先使用 Resource ID Map
  /// (混淆 APK 的字符串池可能被篡改，Resource ID Map 更可靠)
  String _resolveStringOrResourceId(
      List<String> strings, List<int> resourceIdMap, int index) {
    // 优先使用 Resource ID Map（对框架属性更可靠）
    if (index >= 0 && index < resourceIdMap.length) {
      final resId = resourceIdMap[index];
      final name = _kFrameworkAttrNames[resId];
      if (name != null) return name;
    }

    // 回退到字符串池
    return _safeGet(strings, index);
  }

  /// 安全访问字符串列表，越界时返回空字符串
  static String _safeGet(List<String> strings, int index) {
    if (index < 0 || index >= strings.length) return '';
    return strings[index];
  }

  static int getUnsignedShort(ByteData data, int position,
      [Endian endian = Endian.little]) {
    return data.getInt16(position, endian) & 0xffff;
  }

  static int getUnsignedByte(ByteData data, int position) {
    return data.getInt8(position) & 0xff;
  }

  static int getUnsignedInt(ByteData data, int position,
      [Endian endian = Endian.little]) {
    return data.getInt32(position, endian) & 0xffffffff;
  }

  static String getDimensionType(int data) {
    switch ((data >> COMPLEX_UNIT_SHIFT) & COMPLEX_UNIT_MASK) {
      case 0:
        return "px";
      case 1:
        return "dp";
      case 2:
        return "sp";
      case 3:
        return "pt";
      case 4:
        return "in";
      case 5:
        return "mm";
      default:
        return " (unknown unit)";
    }
  }

  static String getFractionType(int data) {
    switch ((data >> COMPLEX_UNIT_SHIFT) & COMPLEX_UNIT_MASK) {
      case COMPLEX_UNIT_FRACTION:
        return "%%";
      case COMPLEX_UNIT_FRACTION_PARENT:
        return "%%p";
      default:
        return "(unknown unit)";
    }
  }

  static double resValue(int data) {
    double value = (data & (COMPLEX_MANTISSA_MASK << COMPLEX_MANTISSA_SHIFT)) *
        RADIX_MULTS[(data >> COMPLEX_RADIX_SHIFT) & COMPLEX_RADIX_MASK];
    return value;
  }
}
