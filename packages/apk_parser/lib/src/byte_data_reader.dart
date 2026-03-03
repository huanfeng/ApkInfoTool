import 'dart:typed_data';

class ByteDataReader {
  late ByteData _data;
  late Endian _endian;
  int _position = 0;

  int get position => _position;

  set position(int newPosion) {
    checkPosition(newPosion);
    _position = newPosion;
  }

  ByteDataReader._(ByteData data, {Endian endian = Endian.little}) {
    _data = data;
    _endian = endian;
  }

  factory ByteDataReader.wrapUint8List(Uint8List data,
      {int start = 0, int? end, Endian endian = Endian.little}) {
    return ByteDataReader._(ByteData.sublistView(data, start, end),
        endian: endian);
  }

  factory ByteDataReader.wrapByteData(ByteData data,
      {Endian endian = Endian.little}) {
    return ByteDataReader._(data, endian: endian);
  }

  int get length => _data.lengthInBytes;

  int get remain => length - _position;

  void checkPosition(int newPosition) {
    if (newPosition < 0 || newPosition > length) {
      throw Exception(
          'checkPosition: position out of range, newPosition: $newPosition,  total: $length');
    }
  }

  void _move(int length) {
    checkPosition(_position + length);
    _position += length;
  }

  int readInt8() {
    final value = _data.getInt8(_position);
    _move(1);
    return value;
  }

  int readInt16() {
    final value = _data.getInt16(_position, _endian);
    _move(2);
    return value;
  }

  int readInt32() {
    final value = _data.getInt32(_position, _endian);
    _move(4);
    return value;
  }

  ByteDataReader skipBytes(int length) {
    _move(length);
    return this;
  }

  // 从指定位置获取Uint8List, 不会移动position
  Uint8List getUint8List(int offset, int length) {
    return _data.buffer.asUint8List(
      _data.offsetInBytes + offset,
      length,
    );
  }

  // 从指定位置获取Uint16List, 不会移动position
  Uint16List getUint16List(int offset, int length) {
    return _data.buffer.asUint16List(
      _data.offsetInBytes + offset,
      length,
    );
  }

  ByteDataReader readFully(Uint8List buffer) {
    checkPosition(_position + buffer.length);
    buffer.setAll(
      0,
      _data.buffer.asUint8List(_data.offsetInBytes + _position, buffer.length),
    );
    _move(buffer.length);
    return this;
  }

  int readUint8() {
    return readInt8().toUnsigned(8);
  }

  int readUint16() {
    return readInt16().toUnsigned(16);
  }

  int readUint32() {
    return readInt32().toUnsigned(32);
  }

  Uint8List readUint8List(int length) {
    checkPosition(_position + length);
    final bytes =
        _data.buffer.asUint8List(_data.offsetInBytes + _position, length);
    _move(length);
    return bytes;
  }
}
