import 'dart:typed_data';
import 'byte_data_reader.dart';
import 'arsc/string_pool.dart';
import 'arsc/resource_value.dart';
import 'arsc/type_spec.dart';

/// resources.arsc 完整解析器
///
/// 解析 Android 资源表二进制格式，支持按资源 ID 查询字符串值、
/// 文件路径，以及获取所有 locale 和 density 变体。
///
/// 资源 ID 结构: 0xPPTTEEEE
/// - PP: package id
/// - TT: type id (1-based)
/// - EEEE: entry index
class ArscParser {
  late final StringPool _globalStringPool;
  final List<_Package> _packages = [];

  ArscParser(Uint8List data) {
    _parse(ByteDataReader.wrapUint8List(data, endian: Endian.little));
  }

  /// 通过资源 ID 获取字符串值
  /// [resourceId] 格式: 0xPPTTEEEE
  /// [locale] 可选的 locale 过滤 (如 "zh-CN", "en")
  String? getStringValue(int resourceId, {String? locale}) {
    final packageId = (resourceId >> 24) & 0xFF;
    final typeId = (resourceId >> 16) & 0xFF;
    final entryIndex = resourceId & 0xFFFF;

    final package = _findPackage(packageId);
    if (package == null) return null;

    final typeSpec = package.findTypeSpec(typeId);
    if (typeSpec == null) return null;

    // 优先查找匹配 locale 的配置，否则查找默认配置
    for (final config in typeSpec.configs) {
      final configLocale = config.config.locale;
      if (locale != null && locale.isNotEmpty) {
        if (configLocale != locale) continue;
      } else {
        if (configLocale.isNotEmpty) continue;
      }

      final entry = config.entries[entryIndex];
      if (entry == null || entry.value == null) continue;

      if (entry.value!.isString) {
        return _globalStringPool.get(entry.value!.data);
      }
    }

    // 如果没有找到默认配置的值，尝试任意配置
    if (locale == null || locale.isEmpty) {
      for (final config in typeSpec.configs) {
        final entry = config.entries[entryIndex];
        if (entry == null || entry.value == null) continue;
        if (entry.value!.isString) {
          return _globalStringPool.get(entry.value!.data);
        }
      }
    }

    return null;
  }

  /// 通过资源 ID 获取文件路径
  /// [resourceId] 格式: 0xPPTTEEEE
  /// [density] 可选的 density 过滤 (如 160, 240, 320, 480)
  String? getFilePath(int resourceId, {int? density}) {
    final packageId = (resourceId >> 24) & 0xFF;
    final typeId = (resourceId >> 16) & 0xFF;
    final entryIndex = resourceId & 0xFFFF;

    final package = _findPackage(packageId);
    if (package == null) return null;

    final typeSpec = package.findTypeSpec(typeId);
    if (typeSpec == null) return null;

    // 优先匹配指定 density
    if (density != null) {
      for (final config in typeSpec.configs) {
        if (config.config.density != density) continue;
        final entry = config.entries[entryIndex];
        if (entry == null || entry.value == null) continue;
        if (entry.value!.isString) {
          return _globalStringPool.get(entry.value!.data);
        }
      }
    }

    // 回退到默认（density=0）或任意配置
    for (final config in typeSpec.configs) {
      if (density != null && config.config.density != 0) continue;
      final entry = config.entries[entryIndex];
      if (entry == null || entry.value == null) continue;
      if (entry.value!.isString) {
        return _globalStringPool.get(entry.value!.data);
      }
    }

    // 最后尝试任意
    for (final config in typeSpec.configs) {
      final entry = config.entries[entryIndex];
      if (entry == null || entry.value == null) continue;
      if (entry.value!.isString) {
        return _globalStringPool.get(entry.value!.data);
      }
    }

    return null;
  }

  /// 获取资源 ID 对应的所有 density 变体文件路径
  List<MapEntry<int, String>> getAllFilePaths(int resourceId) {
    final packageId = (resourceId >> 24) & 0xFF;
    final typeId = (resourceId >> 16) & 0xFF;
    final entryIndex = resourceId & 0xFFFF;

    final package = _findPackage(packageId);
    if (package == null) return [];

    final typeSpec = package.findTypeSpec(typeId);
    if (typeSpec == null) return [];

    final results = <MapEntry<int, String>>[];
    for (final config in typeSpec.configs) {
      final entry = config.entries[entryIndex];
      if (entry == null || entry.value == null) continue;
      if (entry.value!.isString) {
        final path = _globalStringPool.get(entry.value!.data);
        if (path != null) {
          results.add(MapEntry(config.config.density, path));
        }
      }
    }
    return results;
  }

  /// 获取资源表中所有的 locale 列表
  Set<String> getLocales() {
    final locales = <String>{};
    for (final package in _packages) {
      for (final typeSpec in package.typeSpecs.values) {
        for (final config in typeSpec.configs) {
          final locale = config.config.locale;
          if (locale.isNotEmpty) {
            locales.add(locale);
          }
        }
      }
    }
    return locales;
  }

  /// 获取资源表中所有的 density 列表
  Set<int> getDensities() {
    final densities = <int>{};
    for (final package in _packages) {
      for (final typeSpec in package.typeSpecs.values) {
        for (final config in typeSpec.configs) {
          if (config.config.density > 0) {
            densities.add(config.config.density);
          }
        }
      }
    }
    return densities;
  }

  _Package? _findPackage(int id) {
    for (final package in _packages) {
      if (package.id == id) return package;
    }
    return null;
  }

  void _parse(ByteDataReader reader) {
    // ResTable_header
    reader.readUint16(); // type 0x0002
    final headerSize = reader.readUint16();
    reader.readUint32(); // total size
    final packageCount = reader.readUint32();

    if (headerSize > 12) {
      reader.skipBytes(headerSize - 12);
    }

    // Global string pool
    _globalStringPool = StringPool.parse(reader);

    // Parse packages
    for (var i = 0; i < packageCount && reader.remain > 0; i++) {
      _packages.add(_parsePackage(reader));
    }
  }

  _Package _parsePackage(ByteDataReader reader) {
    final packageStart = reader.position;

    final type = reader.readUint16(); // RES_TABLE_PACKAGE_TYPE = 0x0200
    final headerSize = reader.readUint16();
    final totalSize = reader.readUint32();
    final packageId = reader.readUint32();

    assert(type == type); // suppress warning

    // Package name: 128 uint16 chars = 256 bytes
    final nameBytes = reader.readUint8List(256);
    final nameCodeUnits =
        Uint16List.view(nameBytes.buffer, nameBytes.offsetInBytes, 128);
    var packageName = String.fromCharCodes(nameCodeUnits);
    final nullIndex = packageName.indexOf('\x00');
    if (nullIndex >= 0) {
      packageName = packageName.substring(0, nullIndex);
    }

    final typeStringsOffset = reader.readUint32();
    reader.readUint32(); // lastPublicType
    final keyStringsOffset = reader.readUint32();
    reader.readUint32(); // lastPublicKey

    // Skip to end of header
    final headerRead = reader.position - packageStart;
    if (headerSize > headerRead) {
      reader.skipBytes(headerSize - headerRead);
    }

    // Parse type string pool
    reader.position = packageStart + typeStringsOffset;
    final typeStringPool = StringPool.parse(reader);

    // Parse key string pool
    reader.position = packageStart + keyStringsOffset;
    final keyStringPool = StringPool.parse(reader);

    final package = _Package(
      id: packageId,
      name: packageName,
      typeStringPool: typeStringPool,
      keyStringPool: keyStringPool,
    );

    // Parse remaining chunks (TypeSpec and Type)
    final packageEnd = packageStart + totalSize;
    while (reader.position < packageEnd && reader.remain >= 8) {
      final chunkStart = reader.position;
      final chunkType = reader.readUint16();
      final chunkHeaderSize = reader.readUint16();
      final chunkSize = reader.readUint32();

      if (chunkSize < 8) break; // invalid chunk

      switch (chunkType) {
        case 0x0202: // RES_TABLE_TYPE_SPEC_TYPE
          _parseTypeSpec(reader, chunkHeaderSize, package);
          break;
        case 0x0201: // RES_TABLE_TYPE_TYPE
          _parseType(reader, chunkStart, chunkHeaderSize, chunkSize, package);
          break;
        default:
          // Skip unknown chunk
          break;
      }

      // Ensure we move to the next chunk
      reader.position = chunkStart + chunkSize;
    }

    reader.position = packageEnd;
    return package;
  }

  void _parseTypeSpec(
      ByteDataReader reader, int headerSize, _Package package) {
    final typeId = reader.readUint8();
    reader.readUint8(); // res0
    reader.readUint16(); // res1
    final entryCount = reader.readUint32();

    // Read entry flags
    final entryFlags = List<int>.generate(entryCount, (_) => reader.readUint32());

    // Get type name
    final typeName = package.typeStringPool.get(typeId - 1) ?? 'type$typeId';

    // Create or update TypeSpec
    if (!package.typeSpecs.containsKey(typeId)) {
      package.typeSpecs[typeId] = TypeSpec(
        id: typeId,
        name: typeName,
        entryFlags: entryFlags,
        configs: [],
      );
    }
  }

  void _parseType(ByteDataReader reader, int chunkStart, int headerSize,
      int chunkSize, _Package package) {
    final typeId = reader.readUint8();
    reader.readUint8(); // res0
    reader.readUint16(); // res1
    final entryCount = reader.readUint32();
    final entriesStart = reader.readUint32();

    // Parse config
    final config = ResourceConfig.read(reader);

    // Jump to entry offsets (right after header)
    reader.position = chunkStart + headerSize;

    // Read entry offsets
    final entryOffsets =
        List<int>.generate(entryCount, (_) => reader.readUint32());

    // Parse entries
    final entriesDataStart = chunkStart + entriesStart;
    final entries = <int, ResourceEntry>{};

    for (var i = 0; i < entryCount; i++) {
      if (entryOffsets[i] == 0xFFFFFFFF) continue; // NO_ENTRY

      reader.position = entriesDataStart + entryOffsets[i];

      // Parse entry header
      final entrySize = reader.readUint16();
      final entryFlags = reader.readUint16();
      final keyIndex = reader.readUint32();

      final isComplex = (entryFlags & 0x0001) != 0;

      if (isComplex) {
        // Complex/bag entry: ResTable_map_entry
        final parentRef = reader.readUint32();
        final mapCount = reader.readUint32();

        assert(parentRef == parentRef); // suppress warning
        assert(entrySize == entrySize); // suppress warning

        final mapValues = <int, ResourceValue>{};
        for (var j = 0; j < mapCount; j++) {
          final mapName = reader.readUint32();
          final mapValue = ResourceValue.read(reader);
          mapValues[mapName] = mapValue;
        }

        entries[i] = ResourceEntry(
          flags: entryFlags,
          keyIndex: keyIndex,
          mapValues: mapValues,
        );
      } else {
        // Simple entry: Res_value
        final value = ResourceValue.read(reader);
        entries[i] = ResourceEntry(
          flags: entryFlags,
          keyIndex: keyIndex,
          value: value,
        );
      }
    }

    // Ensure TypeSpec exists
    if (!package.typeSpecs.containsKey(typeId)) {
      final typeName =
          package.typeStringPool.get(typeId - 1) ?? 'type$typeId';
      package.typeSpecs[typeId] = TypeSpec(
        id: typeId,
        name: typeName,
        entryFlags: [],
        configs: [],
      );
    }

    package.typeSpecs[typeId]!.configs.add(
      TypeConfig(config: config, entries: entries),
    );
  }
}

class _Package {
  final int id;
  final String name;
  final StringPool typeStringPool;
  final StringPool keyStringPool;
  final Map<int, TypeSpec> typeSpecs = {};

  _Package({
    required this.id,
    required this.name,
    required this.typeStringPool,
    required this.keyStringPool,
  });

  TypeSpec? findTypeSpec(int typeId) => typeSpecs[typeId];
}
