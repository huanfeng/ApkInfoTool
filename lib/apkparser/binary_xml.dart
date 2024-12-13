// ignore_for_file: constant_identifier_names
// from: https://github.com/google/android-classyshark/blob/master/ClassySharkWS/src/com/google/classyshark/silverghost/translator/xml/XmlDecompressor.java

import 'dart:convert';
import 'dart:typed_data';

import 'package:apk_info_tool/utils/byte_data_reader.dart';

class XmlElement {
  String name = "";
  Map<String, String> attributes = {};
  List<XmlElement> children = [];
}

class XmlDocument extends XmlElement {}

class BinaryXmlDecompressor {
  // Identifiers for XML Chunk Types
  static const int PACKED_XML_IDENTIFIER = 0x00080003;
  static const int END_DOC_TAG = 0x0101;
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

    int ident = 0;
    while (true) {
      int tag = reader.readInt16();
      int headerSize = reader.readInt16();
      int chunkSize = reader.readInt32();

      switch (tag) {
        case RES_XML_FIRST_CHUNK_TYPE:
        case RES_XML_RESOURCE_MAP_TYPE:
          // Skip chunk
          break;
        case START_ELEMENT_TAG:
          parseStartTag(result, reader, packedStrings, ident);
          ident++;
          break;
        case END_ELEMENT_TAG:
          ident--;
          parseEndTag(result, reader, packedStrings, ident);
          break;
        case CDATA_TAG:
          parseCDataTag(result, reader, packedStrings, ident);
          break;
        default:
          print('Unknown Tag 0x${tag.toRadixString(16)}');
      }

      if (tag == END_DOC_TAG) break;
    }

    return result.toString();
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
      sb.write(strings[nameStringIndex]);
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
      sb.write(strings[namespaceStringIndex]);
      sb.write(':');
    }

    int nameStringIndex = reader.readInt32();
    sb.write(strings[nameStringIndex]);
    sb.write('>\n');
  }

  void parseStartTag(
      StringBuffer sb, ByteDataReader reader, List<String> strings, int ident) {
    sb.write(' ' * (ident * IDENT_SIZE));
    sb.write('<');
    //Skipping 3 integers:
    // 1 - a flag?, like 38000000
    // 2 - Line of where this tag appeared in the original source file
    // 3 - Unknown: always FFFFFFFF?
    reader.skipBytes(8);
    int namespaceStringIndex = reader.readInt32();
    if (appendNamespaces && namespaceStringIndex >= 0) {
      sb.write(strings[namespaceStringIndex]);
      sb.write(':');
    }

    int nameStringIndex = reader.readInt32();
    sb.write(strings[nameStringIndex]);
    parseAttributes(sb, reader, strings, ident);
    sb.write('>\n');
  }

  void parseAttributes(
      StringBuffer sb, ByteDataReader reader, List<String> strings, int ident) {
    int marker = reader.readInt32();
    if (marker != ATTRS_MARKER) {
      print(
          'Expecting ${ATTRS_MARKER.toRadixString(16)}, Found ${marker.toRadixString(16)}');
    }

    int numAttributes = reader.readInt32();

    // Skipping 1 unknown integer (always 00000000)
    reader.skipBytes(4);

    for (int i = 0; i < numAttributes; i++) {
      sb.write('\n');
      sb.write(' ' * (ident * IDENT_SIZE + ATTR_IDENT_SIZE));

      int attributeNamespaceIndex = reader.readInt32();
      int attributeNameIndex = reader.readInt32();
      int attributeValueIndex = reader.readInt32();

      // Skipping 3 bytes, as there are 3 unknown bytes
      reader.skipBytes(3);
      int attrValueType = reader.readInt8();
      int attributeResourceId = reader.readInt32();

      if (appendNamespaces && attributeNamespaceIndex >= 0) {
        sb.write(strings[attributeNamespaceIndex]);
        sb.write(":");
      }

      String attributeName = strings[attributeNameIndex];
      if (attributeName.isEmpty) attributeName = "unknown";

      String attributeValue;
      switch (attrValueType) {
        case RES_TYPE_NULL:
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
          attributeValue = strings[attributeValueIndex];
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
          attributeValue = '0x${attributeResourceId.toRadixString(16)}';
          break;
        case RES_TYPE_INT_BOOLEAN:
          attributeValue =
              (attributeResourceId == RES_VALUE_TRUE) ? 'true' : 'false';
          break;
        default:
          attributeValue = '0x${attributeResourceId.toRadixString(16)}';
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
    int stylesStart = reader.readInt32();

    bool isUtf8Encoded = (flags & UTF8_FLAG) != 0;
    int glyphSize = isUtf8Encoded ? 1 : 2;

    return parseUsingByteBuffer(chunkSize, headerSize, numStrings, numStyles,
        isUtf8Encoded, glyphSize, reader);
  }

  List<String> parseUsingByteBuffer(
      int chunkSize,
      int headerSize,
      int numStrings,
      int numStyles,
      bool isUtf8Encoded,
      int glyphSize,
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

    // Read the strings from each offset
    int stringsStart = bdr.position;
    for (int i = 0; i < numStrings; i++) {
      bdr.position = stringsStart + offsets[i];
      int len;
      if (isUtf8Encoded) {
        len = bdr.readInt8() & 0xff;
        bdr.skipBytes(1);
      } else {
        len = bdr.readInt16() & 0xffff;
      }
      if (isUtf8Encoded) {
        Uint8List bytes = bdr.getUint8List(stringsStart + offsets[i] + 2, len);
        packedStrings[i] = utf8.decode(bytes);
      } else {
        Uint16List utf16CodeUnits =
            bdr.getUint16List(stringsStart + offsets[i] + 2, len);
        packedStrings[i] = String.fromCharCodes(utf16CodeUnits);
      }
    }
    return packedStrings;
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
