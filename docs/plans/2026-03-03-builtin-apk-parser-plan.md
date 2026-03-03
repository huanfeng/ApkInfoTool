# APK 内置解析器实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 分三阶段实现纯 Dart APK 解析库，逐步替代 aapt2 外部依赖。

**Architecture:** 独立纯 Dart package `packages/apk_parser/` 实现 AndroidManifest.xml 二进制解析 + resources.arsc 资源表解析，通过 ZIP 直接读取 APK 内文件。主程序通过 path 依赖引用，设置中可切换解析引擎。

**Tech Stack:** Dart, archive (ZIP), 二进制解析（Android ResourceTypes.h 格式）

**Design Doc:** `docs/plans/2026-03-03-builtin-apk-parser-design.md`

---

## 阶段 1：解析耗时埋点

### Task 1: 为普通 APK 解析路径添加耗时埋点

**Files:**
- Modify: `lib/apkparser/apk_info.dart:408-460` (普通 APK 的 getApkInfo 后半段)

**Step 1: 在普通 APK 解析路径中添加分阶段计时**

将 `apk_info.dart` 第 409-460 行的普通 APK 解析逻辑改为使用 `Stopwatch` 记录各阶段耗时：

```dart
  // 原有的APK解析逻辑
  final aaptPath = CommandTools.findAapt2Path();
  if (aaptPath == null || aaptPath.isEmpty) {
    throw Exception(t.parse.please_set_path(name: 'aapt2'));
  }
  final totalSw = Stopwatch()..start();
  final phaseSw = Stopwatch();

  try {
    // aapt2 dump badging
    phaseSw..reset()..start();
    var result = await Process.run(
      aaptPath,
      ['dump', 'badging', apk],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(
      const Duration(seconds: 120),
      onTimeout: () {
        throw TimeoutException('Parse timeout');
      },
    );
    final aapt2BadgingMs = phaseSw.elapsedMilliseconds;

    var exitCode = result.exitCode;
    if (exitCode == 0) {
      // 解析 aapt2 输出
      phaseSw..reset()..start();
      parseApkInfoFromOutput(result.stdout.toString(), apkInfo);
      final outputParseMs = phaseSw.elapsedMilliseconds;

      // 图标收集 + 渲染
      phaseSw..reset()..start();
      final iconImage = await apkInfo.loadIcon();
      if (iconImage != null) {
        apkInfo.mainIconImage ??= iconImage;
      }
      final iconMs = phaseSw.elapsedMilliseconds;

      // 签名检查
      var signatureMs = 0;
      if (Config.enableSignature.value) {
        phaseSw..reset()..start();
        try {
          final signInfo = await getSignatureInfo(apk);
          apkInfo.signatureInfo = signInfo;
        } catch (e) {
          log.warning("getApkInfo: 获取签名信息失败: $e");
          apkInfo.signatureInfo = "获取签名信息失败: $e";
        }
        signatureMs = phaseSw.elapsedMilliseconds;
      }

      totalSw.stop();
      log.info("[PERF] getApkInfo: total=${totalSw.elapsedMilliseconds}ms"
          " | aapt2_badging=${aapt2BadgingMs}ms"
          " | output_parse=${outputParseMs}ms"
          " | icon=${iconMs}ms"
          " | signature=${signatureMs}ms");

      return apkInfo;
    }
  } catch (e) {
    log.warning("getApkInfo: error=$e");
  }

  return null;
```

注意：移除原有的 `start`/`end`/`cost` 变量（第 414、429-432 行），用新的 Stopwatch 替代。

**Step 2: 验证编译通过**

Run: `cd D:/Develop/workspace/flutter_project/apk_info_tool && flutter analyze lib/apkparser/apk_info.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/apkparser/apk_info.dart
git commit -m "perf: 为普通 APK 解析路径添加分阶段耗时日志"
```

---

### Task 2: 为 XAPK/ZIP 解析路径添加耗时埋点

**Files:**
- Modify: `lib/apkparser/apk_info.dart:255-407` (XAPK/ZIP 的 getApkInfo 前半段)

**Step 1: 在 XAPK/ZIP 路径中添加分阶段计时**

在 `getApkInfo()` 函数的 XAPK/ZIP 分支（第 278 行 `if (_isArchiveApk(apk) || zipAsArchive)` 块）内添加 Stopwatch 埋点：

需要记录的阶段：
- `zip_open`: `zip.open(apk)` 耗时
- `xapk_manifest`: `parseXapkManifest()` 耗时
- `zip_extract`: `zip.extractFile()` 耗时
- `aapt2_badging`: 内部 `Process.run(aapt2)` 耗时
- `output_parse`: `parseApkInfoFromOutput()` 耗时
- `icon`: `loadIcon()` / `loadXapkIcon()` 耗时
- `total`: 整个 XAPK 分支耗时

在 try 块开头添加 `final totalSw = Stopwatch()..start();` 和 `final phaseSw = Stopwatch();`，在每个关键操作前后记录 `phaseSw..reset()..start()` 和 `xxxMs = phaseSw.elapsedMilliseconds`。

在 return 前输出：
```dart
log.info("[PERF] getApkInfo(archive): total=${totalSw.elapsedMilliseconds}ms"
    " | zip_open=${zipOpenMs}ms"
    " | xapk_manifest=${manifestMs}ms"
    " | zip_extract=${extractMs}ms"
    " | aapt2_badging=${aapt2Ms}ms"
    " | output_parse=${parseMs}ms"
    " | icon=${iconMs}ms");
```

**Step 2: 验证编译通过**

Run: `cd D:/Develop/workspace/flutter_project/apk_info_tool && flutter analyze lib/apkparser/apk_info.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/apkparser/apk_info.dart
git commit -m "perf: 为 XAPK/ZIP 解析路径添加分阶段耗时日志"
```

---

## 阶段 2：独立解析库

### Task 3: 创建 packages/apk_parser 包骨架

**Files:**
- Create: `packages/apk_parser/pubspec.yaml`
- Create: `packages/apk_parser/lib/apk_parser.dart`
- Create: `packages/apk_parser/lib/src/models.dart`

**Step 1: 创建 pubspec.yaml**

```yaml
name: apk_parser
description: Pure Dart APK parser - parses AndroidManifest.xml and resources.arsc directly from APK/ZIP files.
version: 0.1.0
publish_to: none

environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  archive:
    git: https://github.com/huanfeng/archive.git
  xml: ^6.5.0

dev_dependencies:
  test: ^1.24.0
```

**Step 2: 创建 ApkMeta 数据模型 `lib/src/models.dart`**

```dart
/// APK 解析结果数据模型
class ApkMeta {
  String? packageName;
  int? versionCode;
  String? versionName;
  int? minSdkVersion;
  int? targetSdkVersion;
  int? compileSdkVersion;
  String? compileSdkVersionCodename;
  String? platformBuildVersionName;
  int? platformBuildVersionCode;

  String? label;
  Map<String, String> labels = {};

  String? applicationName;
  String? applicationIcon;
  Map<int, String> iconPaths = {};

  List<String> permissions = [];
  List<String> features = [];
  List<String> featuresNotRequired = [];
  List<String> screenSizes = [];
  List<String> nativeCodes = [];
  List<String> locales = [];
  List<int> densities = [];

  List<ActivityInfo> launchableActivities = [];

  @override
  String toString() {
    return 'ApkMeta{packageName: $packageName, versionCode: $versionCode, '
        'versionName: $versionName, label: $label, '
        'minSdk: $minSdkVersion, targetSdk: $targetSdkVersion, '
        'permissions: ${permissions.length}, features: ${features.length}, '
        'nativeCodes: $nativeCodes, locales: ${locales.length}}';
  }
}

class ActivityInfo {
  String? name;
  String? label;
  String? icon;

  ActivityInfo({this.name, this.label, this.icon});

  @override
  String toString() => 'ActivityInfo{name: $name, label: $label, icon: $icon}';
}
```

**Step 3: 创建公共导出 `lib/apk_parser.dart`**

```dart
library apk_parser;

export 'src/models.dart';
```

**Step 4: 验证包结构**

Run: `cd D:/Develop/workspace/flutter_project/apk_info_tool/packages/apk_parser && dart pub get`
Expected: 成功获取依赖

**Step 5: Commit**

```bash
git add packages/apk_parser/
git commit -m "feat(apk_parser): 创建独立纯 Dart 解析库包骨架"
```

---

### Task 4: 迁移 ByteDataReader 到独立包

**Files:**
- Create: `packages/apk_parser/lib/src/byte_data_reader.dart`（从 `lib/utils/byte_data_reader.dart` 复制）

**Step 1: 复制 ByteDataReader**

将 `lib/utils/byte_data_reader.dart` 的完整内容复制到 `packages/apk_parser/lib/src/byte_data_reader.dart`，不做任何修改。

**Step 2: 在导出文件中添加导出**

在 `lib/apk_parser.dart` 中添加：
```dart
export 'src/byte_data_reader.dart';
```

**Step 3: Commit**

```bash
git add packages/apk_parser/
git commit -m "feat(apk_parser): 迁移 ByteDataReader 到独立包"
```

---

### Task 5: 迁移并增强 BinaryXmlDecompressor

**Files:**
- Create: `packages/apk_parser/lib/src/binary_xml.dart`（从 `lib/apkparser/binary_xml.dart` 迁移 + 增强）
- Create: `packages/apk_parser/test/binary_xml_test.dart`

**Step 1: 复制并修改 BinaryXmlDecompressor**

从 `lib/apkparser/binary_xml.dart` 复制到 `packages/apk_parser/lib/src/binary_xml.dart`。

修改点：
1. 移除 `import 'package:apk_info_tool/utils/byte_data_reader.dart'` → `import 'byte_data_reader.dart'`
2. 移除 `import 'package:apk_info_tool/utils/logger.dart'` 和所有 `log.fine(...)` 调用 → 改为可选的日志回调或直接移除
3. 新增 `decompressToDocument()` 方法，返回结构化的 `XmlDocument`

**Step 2: 实现 `decompressToDocument()` 方法**

在 `BinaryXmlDecompressor` 类中新增方法，复用现有的字符串池解析和 chunk 遍历逻辑，但不写 StringBuffer，而是构建 `XmlElement` 树：

```dart
/// 解析二进制 XML 为结构化文档树
XmlDocument decompressToDocument(Uint8List bytes) {
  final reader = ByteDataReader.wrapUint8List(bytes, endian: Endian.little);

  int fileMarker = reader.readInt32();
  if (fileMarker != PACKED_XML_IDENTIFIER) {
    throw FormatException(
        'Invalid packed XML identifier. Expecting 0x${PACKED_XML_IDENTIFIER.toRadixString(16)}, found 0x${fileMarker.toRadixString(16)}');
  }
  reader.skipBytes(4);

  List<String> packedStrings = parseStrings(reader);

  final doc = XmlDocument();
  final stack = <XmlElement>[doc];

  while (reader.remain >= 8) {
    final chunkStart = reader.position;
    int tag = reader.readInt16();
    reader.readInt16();
    int chunkSize = reader.readInt32();
    if (chunkSize < 8) break;
    final chunkEnd = chunkStart + chunkSize;
    if (chunkEnd > reader.length) break;

    switch (tag) {
      case START_NAMESPACE_TAG:
      case END_NAMESPACE_TAG:
      case RES_XML_RESOURCE_MAP_TYPE:
        break;
      case START_ELEMENT_TAG:
        final element = _parseStartElement(reader, packedStrings);
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
        reader.skipBytes(8);
        reader.readInt32(); // name
        reader.skipBytes(8);
        break;
    }

    if (reader.position != chunkEnd) {
      reader.position = chunkEnd;
    }
  }

  return doc;
}

XmlElement _parseStartElement(ByteDataReader reader, List<String> strings) {
  reader.skipBytes(8);
  int namespaceIndex = reader.readInt32();
  int nameIndex = reader.readInt32();

  final element = XmlElement();
  element.name = strings[nameIndex];
  if (appendNamespaces && namespaceIndex >= 0) {
    element.name = '${strings[namespaceIndex]}:${element.name}';
  }

  // Parse attributes
  int marker = reader.readInt32();
  int numAttributes = reader.readUint16();
  reader.skipBytes(6);

  for (int i = 0; i < numAttributes; i++) {
    int attrNamespaceIndex = reader.readInt32();
    int attrNameIndex = reader.readInt32();
    int attrValueIndex = reader.readInt32();
    reader.readUint16();
    reader.readUint8();
    int attrValueType = reader.readUint8();
    int attrResourceId = reader.readInt32();

    String attrName = strings[attrNameIndex];
    if (attrName.isEmpty) attrName = 'unknown';

    String attrValue = _resolveAttributeValue(
        attrValueType, attrValueIndex, attrResourceId, strings);

    element.attributes[attrName] = attrValue;
  }

  return element;
}

String _resolveAttributeValue(
    int type, int valueIndex, int resourceId, List<String> strings) {
  // 复用现有 parseAttributes 中的 switch 逻辑，但返回 String 而非写 StringBuffer
  return switch (type) {
    RES_TYPE_NULL => (resourceId == 0) ? '' : '',
    RES_TYPE_REFERENCE => '@res/0x${resourceId.toRadixString(16)}',
    RES_TYPE_ATTRIBUTE => '@attr/0x${resourceId.toRadixString(16)}',
    RES_TYPE_STRING => strings[valueIndex],
    RES_TYPE_INT_DEC => resourceId.toString(),
    RES_TYPE_INT_HEX => '0x${(resourceId & 0xffffffff).toRadixString(16)}',
    RES_TYPE_INT_BOOLEAN => (resourceId == RES_VALUE_TRUE) ? 'true' : 'false',
    RES_TYPE_INT_COLOR_ARGB8 || RES_TYPE_INT_COLOR_ARGB4 =>
      '#${(resourceId & 0xffffffff).toRadixString(16).padLeft(8, '0')}',
    RES_TYPE_INT_COLOR_RGB8 || RES_TYPE_INT_COLOR_RGB4 =>
      '#ff${(resourceId & 0x00ffffff).toRadixString(16).padLeft(6, '0')}',
    RES_TYPE_DIMENSION => '${resValue(resourceId)}${getDimensionType(resourceId)}',
    RES_TYPE_FRACTION => '${resValue(resourceId)}${getFractionType(resourceId)}',
    RES_TYPE_DYNAMIC_REFERENCE => '@dyn/0x${resourceId.toRadixString(16)}',
    RES_TYPE_FLOAT => _parseFloat(resourceId).toString(),
    _ => '0x${(resourceId & 0xffffffff).toRadixString(16)}',
  };
}

static double _parseFloat(int bits) {
  final buf = Uint8List(4);
  buf[0] = bits & 0xff;
  buf[1] = (bits >> 8) & 0xff;
  buf[2] = (bits >> 16) & 0xff;
  buf[3] = (bits >> 24) & 0xff;
  return ByteData.sublistView(buf).buffer.asFloat32List().first;
}
```

**Step 3: 编写基础测试**

`packages/apk_parser/test/binary_xml_test.dart`:
```dart
import 'package:test/test.dart';
import 'package:apk_parser/apk_parser.dart';

void main() {
  group('BinaryXmlDecompressor', () {
    test('decompressXml 和 decompressToDocument 应解析相同内容', () {
      // 使用实际 APK 中的 AndroidManifest.xml 二进制数据测试
      // 此测试在 compare.dart CLI 中通过真实 APK 验证
    });
  });
}
```

**Step 4: 更新导出**

`lib/apk_parser.dart` 添加：
```dart
export 'src/binary_xml.dart';
```

**Step 5: Commit**

```bash
git add packages/apk_parser/
git commit -m "feat(apk_parser): 迁移 BinaryXmlDecompressor 并新增结构化解析"
```

---

### Task 6: 实现 ManifestParser

**Files:**
- Create: `packages/apk_parser/lib/src/manifest_parser.dart`

**Step 1: 实现 ManifestParser**

```dart
import 'dart:typed_data';
import 'binary_xml.dart';
import 'models.dart';

/// 从 AndroidManifest.xml 的二进制数据解析 APK 元信息
class ManifestParser {
  /// 解析二进制 AndroidManifest.xml，返回 ApkMeta
  /// 资源引用（@res/0x...）不在此处解析，需要后续通过 ArscParser 处理
  static ApkMeta parse(Uint8List manifestBytes) {
    final decompressor = BinaryXmlDecompressor();
    final doc = decompressor.decompressToDocument(manifestBytes);
    final meta = ApkMeta();

    // 查找 <manifest> 根元素
    final manifest = _findElement(doc, 'manifest');
    if (manifest == null) return meta;

    meta.packageName = manifest.attributes['package'];
    meta.versionCode = _parseInt(manifest.attributes['versionCode']);
    meta.versionName = manifest.attributes['versionName'];
    meta.compileSdkVersion = _parseInt(manifest.attributes['compileSdkVersion']);
    meta.compileSdkVersionCodename = manifest.attributes['compileSdkVersionCodename'];
    meta.platformBuildVersionName = manifest.attributes['platformBuildVersionName'];
    meta.platformBuildVersionCode = _parseInt(manifest.attributes['platformBuildVersionCode']);

    // <uses-sdk>
    final usesSdk = _findElement(manifest, 'uses-sdk');
    if (usesSdk != null) {
      meta.minSdkVersion = _parseInt(usesSdk.attributes['minSdkVersion']);
      meta.targetSdkVersion = _parseInt(usesSdk.attributes['targetSdkVersion']);
    }

    // <uses-permission>
    for (final child in manifest.children) {
      if (child.name == 'uses-permission') {
        final name = child.attributes['name'];
        if (name != null && name.isNotEmpty) {
          meta.permissions.add(name);
        }
      }
    }

    // <uses-feature>
    for (final child in manifest.children) {
      if (child.name == 'uses-feature') {
        final name = child.attributes['name'];
        if (name != null && name.isNotEmpty) {
          final required = child.attributes['required'];
          if (required == 'false') {
            meta.featuresNotRequired.add(name);
          } else {
            meta.features.add(name);
          }
        }
      }
    }

    // <supports-screens>
    final screens = _findElement(manifest, 'supports-screens');
    if (screens != null) {
      for (final attr in screens.attributes.entries) {
        if (attr.value == 'true') {
          meta.screenSizes.add(attr.key);
        }
      }
    }

    // <application>
    final application = _findElement(manifest, 'application');
    if (application != null) {
      meta.applicationName = application.attributes['name'];
      meta.label = application.attributes['label'];
      meta.applicationIcon = application.attributes['icon'];

      // 查找 launchable activities（含 MAIN + LAUNCHER intent-filter）
      for (final activity in application.children) {
        if (activity.name != 'activity' && activity.name != 'activity-alias') {
          continue;
        }
        if (_isLaunchableActivity(activity)) {
          meta.launchableActivities.add(ActivityInfo(
            name: activity.attributes['name'],
            label: activity.attributes['label'],
            icon: activity.attributes['icon'],
          ));
        }
      }
    }

    return meta;
  }

  static bool _isLaunchableActivity(XmlElement activity) {
    for (final child in activity.children) {
      if (child.name != 'intent-filter') continue;
      bool hasMain = false;
      bool hasLauncher = false;
      for (final filterChild in child.children) {
        if (filterChild.name == 'action' &&
            filterChild.attributes['name'] == 'android.intent.action.MAIN') {
          hasMain = true;
        }
        if (filterChild.name == 'category' &&
            filterChild.attributes['name'] ==
                'android.intent.category.LAUNCHER') {
          hasLauncher = true;
        }
      }
      if (hasMain && hasLauncher) return true;
    }
    return false;
  }

  static XmlElement? _findElement(XmlElement parent, String name) {
    for (final child in parent.children) {
      if (child.name == name) return child;
    }
    return null;
  }

  static int? _parseInt(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('0x')) {
      return int.tryParse(value.substring(2), radix: 16);
    }
    return int.tryParse(value);
  }
}
```

**Step 2: 更新导出**

`lib/apk_parser.dart` 添加：
```dart
export 'src/manifest_parser.dart';
```

**Step 3: Commit**

```bash
git add packages/apk_parser/
git commit -m "feat(apk_parser): 实现 ManifestParser 解析 AndroidManifest.xml"
```

---

### Task 7: 实现 ArscParser - 字符串池

**Files:**
- Create: `packages/apk_parser/lib/src/arsc/string_pool.dart`

**Step 1: 实现 StringPool**

参考 Android ResourceTypes.h 中的 `ResStringPool_header` 结构：

```dart
import 'dart:convert';
import 'dart:typed_data';
import '../byte_data_reader.dart';

/// resources.arsc 字符串池解析
/// 对应 Android ResStringPool_header 结构
class StringPool {
  final List<String> strings;
  final List<List<StringPoolSpan>> styles;

  StringPool._(this.strings, this.styles);

  String? get(int index) {
    if (index < 0 || index >= strings.length) return null;
    return strings[index];
  }

  int get length => strings.length;

  /// 从字节流解析字符串池
  /// reader 应指向 ResStringPool_header 起始位置（type 字段之前）
  static StringPool parse(ByteDataReader reader) {
    final headerStart = reader.position;

    final type = reader.readUint16();        // type: RES_STRING_POOL_TYPE = 0x0001
    final headerSize = reader.readUint16();  // header size
    final totalSize = reader.readUint32();   // total chunk size
    final stringCount = reader.readUint32(); // number of strings
    final styleCount = reader.readUint32();  // number of style spans
    final flags = reader.readUint32();       // flags (UTF8_FLAG = 0x100, SORTED_FLAG = 0x001)
    final stringsStart = reader.readUint32(); // offset to string data from header start
    final stylesStart = reader.readUint32();  // offset to style data from header start

    final isUtf8 = (flags & 0x100) != 0;

    // 读取字符串偏移量表
    final stringOffsets = List<int>.generate(
        stringCount, (_) => reader.readUint32());

    // 跳过样式偏移量表
    final styleOffsets = List<int>.generate(
        styleCount, (_) => reader.readUint32());

    // 解析字符串数据
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
        final codeUnits = Uint16List.view(
            bytes.buffer, bytes.offsetInBytes, utf16Len);
        strings.add(String.fromCharCodes(codeUnits));
      }
    }

    // 跳到 chunk 末尾
    reader.position = headerStart + totalSize;

    return StringPool._(strings, const []);
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

class StringPoolSpan {
  final int nameIndex;
  final int firstChar;
  final int lastChar;
  StringPoolSpan(this.nameIndex, this.firstChar, this.lastChar);
}
```

**Step 2: Commit**

```bash
git add packages/apk_parser/
git commit -m "feat(apk_parser): 实现 arsc StringPool 字符串池解析"
```

---

### Task 8: 实现 ArscParser - ResourceTable 核心结构

**Files:**
- Create: `packages/apk_parser/lib/src/arsc/resource_table.dart`
- Create: `packages/apk_parser/lib/src/arsc/type_spec.dart`
- Create: `packages/apk_parser/lib/src/arsc/resource_value.dart`

**Step 1: 实现 ResourceValue 和 ResourceEntry**

`packages/apk_parser/lib/src/arsc/resource_value.dart`:

```dart
import 'dart:typed_data';
import '../byte_data_reader.dart';

/// 对应 Android Res_value 结构
class ResourceValue {
  final int size;
  final int type;
  final int data;

  ResourceValue({required this.size, required this.type, required this.data});

  /// 资源值类型常量
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

  static ResourceValue read(ByteDataReader reader) {
    final size = reader.readUint16();
    reader.readUint8(); // res0
    final type = reader.readUint8();
    final data = reader.readUint32();
    return ResourceValue(size: size, type: type, data: data);
  }
}

/// 对应 Android ResTable_entry
class ResourceEntry {
  final int flags;
  final int keyIndex;
  final ResourceValue? value;
  final Map<int, ResourceValue>? mapValues; // for complex/bag entries

  ResourceEntry({
    required this.flags,
    required this.keyIndex,
    this.value,
    this.mapValues,
  });

  bool get isComplex => (flags & 0x0001) != 0;
}

/// 资源配置（对应 ResTable_config）
class ResourceConfig {
  final int size;
  final int mcc;
  final int mnc;
  final String language;
  final String country;
  final int density;
  final int screenWidth;
  final int screenHeight;
  // 其他配置字段可按需添加

  ResourceConfig({
    this.size = 0,
    this.mcc = 0,
    this.mnc = 0,
    this.language = '',
    this.country = '',
    this.density = 0,
    this.screenWidth = 0,
    this.screenHeight = 0,
  });

  String get locale {
    if (language.isEmpty) return '';
    if (country.isEmpty) return language;
    return '${language}-$country';
  }

  static ResourceConfig read(ByteDataReader reader) {
    final startPos = reader.position;
    final size = reader.readUint32();

    if (size < 28) {
      // minimal config size
      reader.position = startPos + size;
      return ResourceConfig(size: size);
    }

    final mcc = reader.readUint16();
    final mnc = reader.readUint16();

    // language and country are 2-byte char arrays
    final langBytes = reader.readUint8List(2);
    final countryBytes = reader.readUint8List(2);
    final language = _decodeChars(langBytes);
    final country = _decodeChars(countryBytes);

    // orientation, touchscreen, density (skip to density)
    reader.readUint8(); // orientation
    reader.readUint8(); // touchscreen
    final density = reader.readUint16();

    // 跳过剩余配置字段
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
```

**Step 2: 实现 TypeSpec**

`packages/apk_parser/lib/src/arsc/type_spec.dart`:

```dart
import 'resource_value.dart';

/// 一个 type 下所有配置的资源条目集合
class TypeSpec {
  final int id;               // type id (1-based)
  final String name;          // type name: string, mipmap, drawable, etc.
  final List<int> entryFlags; // per-entry config flags
  final List<TypeConfig> configs;

  TypeSpec({
    required this.id,
    required this.name,
    required this.entryFlags,
    required this.configs,
  });
}

/// 一个 type 在特定配置下的所有 entry
class TypeConfig {
  final ResourceConfig config;
  final Map<int, ResourceEntry> entries; // entryIndex -> entry

  TypeConfig({required this.config, required this.entries});
}
```

**Step 3: Commit**

```bash
git add packages/apk_parser/
git commit -m "feat(apk_parser): 实现 arsc 核心数据结构 (ResourceValue, Entry, Config, TypeSpec)"
```

---

### Task 9: 实现 ArscParser 主解析器

**Files:**
- Create: `packages/apk_parser/lib/src/arsc_parser.dart`

**Step 1: 实现 ArscParser**

这是最复杂的部分，解析 resources.arsc 的完整二进制结构：

```dart
import 'dart:typed_data';
import 'byte_data_reader.dart';
import 'arsc/string_pool.dart';
import 'arsc/resource_value.dart';
import 'arsc/type_spec.dart';

/// resources.arsc 解析器
/// 解析 Android 资源表，支持按 ID 查找字符串值和文件路径
class ArscParser {
  late final StringPool _globalStringPool;
  final List<_Package> _packages = [];

  /// 从 resources.arsc 的原始字节解析
  ArscParser(Uint8List data) {
    _parse(ByteDataReader.wrapUint8List(data, endian: Endian.little));
  }

  /// 按资源 ID 查找字符串值
  /// [locale] 可选，指定语言（如 'zh-CN'），null 表示默认
  String? getStringValue(int resourceId, {String? locale}) {
    final packageId = (resourceId >> 24) & 0xff;
    final typeId = (resourceId >> 16) & 0xff;
    final entryId = resourceId & 0xffff;

    final pkg = _findPackage(packageId);
    if (pkg == null) return null;

    final typeSpec = pkg.findTypeSpec(typeId);
    if (typeSpec == null) return null;

    // 优先匹配指定 locale，回退到默认配置
    ResourceEntry? bestEntry;
    for (final config in typeSpec.configs) {
      final entry = config.entries[entryId];
      if (entry == null) continue;
      if (locale != null && config.config.locale == locale) {
        bestEntry = entry;
        break;
      }
      if (config.config.locale.isEmpty) {
        bestEntry ??= entry;
      }
    }

    if (bestEntry == null) return null;
    final value = bestEntry.value;
    if (value == null) return null;

    if (value.isString) {
      return _globalStringPool.get(value.data);
    }
    return null;
  }

  /// 按资源 ID 查找文件路径
  /// [density] 可选，指定 DPI（如 480），null 表示最高密度
  String? getFilePath(int resourceId, {int? density}) {
    final packageId = (resourceId >> 24) & 0xff;
    final typeId = (resourceId >> 16) & 0xff;
    final entryId = resourceId & 0xffff;

    final pkg = _findPackage(packageId);
    if (pkg == null) return null;

    final typeSpec = pkg.findTypeSpec(typeId);
    if (typeSpec == null) return null;

    ResourceEntry? bestEntry;
    int bestDensityDiff = 0x7fffffff;

    for (final config in typeSpec.configs) {
      final entry = config.entries[entryId];
      if (entry == null) continue;
      final value = entry.value;
      if (value == null || !value.isString) continue;

      final configDensity = config.config.density;
      if (density != null) {
        final diff = (configDensity - density).abs();
        if (diff < bestDensityDiff) {
          bestDensityDiff = diff;
          bestEntry = entry;
        }
      } else {
        // 无指定密度时，选最高密度
        if (bestEntry == null || configDensity > (bestEntry.value?.data ?? 0)) {
          bestEntry = entry;
        }
      }
    }

    if (bestEntry?.value == null) return null;
    return _globalStringPool.get(bestEntry!.value!.data);
  }

  /// 按资源 ID 查找所有密度的文件路径映射
  Map<int, String> getAllFilePaths(int resourceId) {
    final packageId = (resourceId >> 24) & 0xff;
    final typeId = (resourceId >> 16) & 0xff;
    final entryId = resourceId & 0xffff;

    final pkg = _findPackage(packageId);
    if (pkg == null) return {};

    final typeSpec = pkg.findTypeSpec(typeId);
    if (typeSpec == null) return {};

    final result = <int, String>{};
    for (final config in typeSpec.configs) {
      final entry = config.entries[entryId];
      if (entry == null) continue;
      final value = entry.value;
      if (value == null || !value.isString) continue;
      final path = _globalStringPool.get(value.data);
      if (path != null) {
        result[config.config.density] = path;
      }
    }
    return result;
  }

  /// 获取所有 locale 列表
  List<String> getLocales() {
    final locales = <String>{};
    for (final pkg in _packages) {
      for (final typeSpec in pkg.typeSpecs.values) {
        for (final config in typeSpec.configs) {
          final locale = config.config.locale;
          if (locale.isNotEmpty) locales.add(locale);
        }
      }
    }
    return locales.toList()..sort();
  }

  /// 获取所有 density 列表
  List<int> getDensities() {
    final densities = <int>{};
    for (final pkg in _packages) {
      for (final typeSpec in pkg.typeSpecs.values) {
        for (final config in typeSpec.configs) {
          if (config.config.density > 0) {
            densities.add(config.config.density);
          }
        }
      }
    }
    return densities.toList()..sort();
  }

  _Package? _findPackage(int id) {
    for (final pkg in _packages) {
      if (pkg.id == id) return pkg;
    }
    return _packages.isNotEmpty ? _packages.first : null;
  }

  // ─── 解析逻辑 ───

  void _parse(ByteDataReader reader) {
    // ResTable_header
    final tableType = reader.readUint16();   // RES_TABLE_TYPE = 0x0002
    final headerSize = reader.readUint16();
    final totalSize = reader.readUint32();
    final packageCount = reader.readUint32();

    // 跳到 header 结束位置
    if (headerSize > 12) {
      reader.skipBytes(headerSize - 12);
    }

    // 全局字符串池
    _globalStringPool = StringPool.parse(reader);

    // 解析各 package
    for (var i = 0; i < packageCount && reader.remain > 0; i++) {
      _packages.add(_parsePackage(reader));
    }
  }

  _Package _parsePackage(ByteDataReader reader) {
    final chunkStart = reader.position;
    final type = reader.readUint16();       // RES_TABLE_PACKAGE_TYPE = 0x0200
    final headerSize = reader.readUint16();
    final chunkSize = reader.readUint32();
    final chunkEnd = chunkStart + chunkSize;

    final id = reader.readUint32();

    // Package name (128 uint16 chars)
    final nameBytes = reader.readUint8List(256);
    final nameUnits = Uint16List.view(nameBytes.buffer, nameBytes.offsetInBytes, 128);
    final nameEnd = nameUnits.indexOf(0);
    final name = String.fromCharCodes(
        nameEnd >= 0 ? nameUnits.sublist(0, nameEnd) : nameUnits);

    final typeStringsOffset = reader.readUint32();
    final lastPublicType = reader.readUint32();
    final keyStringsOffset = reader.readUint32();
    final lastPublicKey = reader.readUint32();

    // 跳到 header 结束
    reader.position = chunkStart + headerSize;

    // Type 字符串池
    final typeStringPool = StringPool.parse(reader);
    // Key 字符串池
    final keyStringPool = StringPool.parse(reader);

    final pkg = _Package(
      id: id,
      name: name,
      typeStringPool: typeStringPool,
      keyStringPool: keyStringPool,
    );

    // 解析 TypeSpec 和 Type chunks
    while (reader.position < chunkEnd && reader.remain >= 8) {
      final subChunkStart = reader.position;
      final subType = reader.readUint16();
      final subHeaderSize = reader.readUint16();
      final subChunkSize = reader.readUint32();
      final subChunkEnd = subChunkStart + subChunkSize;

      if (subChunkSize < 8 || subChunkEnd > chunkEnd) break;

      switch (subType) {
        case 0x0202: // RES_TABLE_TYPE_SPEC_TYPE
          _parseTypeSpec(reader, subHeaderSize, pkg);
          break;
        case 0x0201: // RES_TABLE_TYPE_TYPE
          _parseType(reader, subChunkStart, subHeaderSize, subChunkSize, pkg);
          break;
      }

      reader.position = subChunkEnd;
    }

    reader.position = chunkEnd;
    return pkg;
  }

  void _parseTypeSpec(ByteDataReader reader, int headerSize, _Package pkg) {
    final typeId = reader.readUint8();
    reader.skipBytes(3); // res0, res1
    final entryCount = reader.readUint32();

    final flags = List<int>.generate(entryCount, (_) => reader.readUint32());

    final typeName = pkg.typeStringPool.get(typeId - 1) ?? 'type$typeId';

    pkg.typeSpecs[typeId] = TypeSpec(
      id: typeId,
      name: typeName,
      entryFlags: flags,
      configs: [],
    );
  }

  void _parseType(ByteDataReader reader, int chunkStart, int headerSize,
      int chunkSize, _Package pkg) {
    final typeId = reader.readUint8();
    reader.readUint8(); // flags
    reader.readUint16(); // reserved
    final entryCount = reader.readUint32();
    final entriesStart = reader.readUint32();

    // 读取 ResTable_config
    final config = ResourceConfig.read(reader);

    // 跳到 entry 偏移量表
    reader.position = chunkStart + headerSize;

    // Entry 偏移量表
    final offsets = List<int>.generate(entryCount, (_) => reader.readUint32());

    final dataStart = chunkStart + entriesStart;
    final entries = <int, ResourceEntry>{};

    for (var i = 0; i < entryCount; i++) {
      if (offsets[i] == 0xffffffff) continue; // NO_ENTRY

      reader.position = dataStart + offsets[i];

      final entrySize = reader.readUint16();
      final entryFlags = reader.readUint16();
      final keyIndex = reader.readUint32();

      final isComplex = (entryFlags & 0x0001) != 0;

      if (isComplex) {
        // ResTable_map_entry
        final parentRef = reader.readUint32();
        final mapCount = reader.readUint32();
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
        final value = ResourceValue.read(reader);
        entries[i] = ResourceEntry(
          flags: entryFlags,
          keyIndex: keyIndex,
          value: value,
        );
      }
    }

    // 将此 TypeConfig 追加到对应的 TypeSpec
    final typeSpec = pkg.typeSpecs[typeId];
    if (typeSpec != null) {
      typeSpec.configs.add(TypeConfig(config: config, entries: entries));
    }
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
```

**Step 2: 更新导出**

`lib/apk_parser.dart` 添加：
```dart
export 'src/arsc_parser.dart';
```

**Step 3: Commit**

```bash
git add packages/apk_parser/
git commit -m "feat(apk_parser): 实现 ArscParser resources.arsc 完整解析器"
```

---

### Task 10: 实现 ApkReader 统一入口

**Files:**
- Create: `packages/apk_parser/lib/src/apk_reader.dart`

**Step 1: 实现 ApkReader**

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'manifest_parser.dart';
import 'arsc_parser.dart';
import 'models.dart';

/// APK 文件读取和解析的统一入口
class ApkReader {
  Archive? _archive;
  ArscParser? _arscParser;

  /// 打开 APK 文件（ZIP 格式）
  Future<bool> open(String filePath) async {
    try {
      final inputStream = InputFileStream(filePath);
      _archive = ZipDecoder().decodeStream(inputStream);
      inputStream.closeSync();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 从内存数据打开（用于嵌套 ZIP 场景，如 XAPK 中的 base.apk）
  bool openBytes(Uint8List data) {
    try {
      _archive = ZipDecoder().decodeBuffer(InputStream(data));
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 解析 APK 基础信息
  Future<ApkMeta?> parse() async {
    final archive = _archive;
    if (archive == null) return null;

    // 1. 读取并解析 AndroidManifest.xml
    final manifestFile = archive.findFile('AndroidManifest.xml');
    if (manifestFile == null) return null;
    final manifestBytes = manifestFile.content as Uint8List;
    final meta = ManifestParser.parse(manifestBytes);

    // 2. 读取并解析 resources.arsc
    final arscFile = archive.findFile('resources.arsc');
    if (arscFile != null) {
      final arscBytes = arscFile.content as Uint8List;
      _arscParser = ArscParser(arscBytes);

      // 解析 label 资源引用
      _resolveLabel(meta);
      // 解析图标路径
      _resolveIconPaths(meta);
      // 获取 locales 和 densities
      meta.locales = _arscParser!.getLocales();
      meta.densities = _arscParser!.getDensities();
    }

    // 3. 扫描 lib/ 目录获取 native codes
    meta.nativeCodes = _scanNativeCodes();

    return meta;
  }

  /// 获取内部的 ArscParser 实例（图标渲染等高级用途）
  ArscParser? get arscParser => _arscParser;

  /// 读取 APK 内指定文件的内容
  Uint8List? readFile(String fileName) {
    final file = _archive?.findFile(fileName);
    return file?.content as Uint8List?;
  }

  /// 列出 APK 内所有文件
  List<String> listFiles({String? extension}) {
    final files = _archive?.files ?? [];
    final lowerExt = extension?.toLowerCase();
    return files
        .where((f) => f.isFile)
        .map((f) => f.name)
        .where((name) =>
            lowerExt == null || name.toLowerCase().endsWith(lowerExt))
        .toList();
  }

  void _resolveLabel(ApkMeta meta) {
    final parser = _arscParser;
    if (parser == null) return;

    // 解析默认 label
    if (meta.label != null && meta.label!.startsWith('@res/0x')) {
      final resId = int.tryParse(meta.label!.substring(5), radix: 16);
      if (resId != null) {
        meta.label = parser.getStringValue(resId) ?? meta.label;

        // 获取多语言 labels
        for (final locale in parser.getLocales()) {
          final localizedLabel =
              parser.getStringValue(resId, locale: locale);
          if (localizedLabel != null) {
            meta.labels[locale] = localizedLabel;
          }
        }
      }
    }
  }

  void _resolveIconPaths(ApkMeta meta) {
    final parser = _arscParser;
    if (parser == null) return;

    final iconRef = meta.applicationIcon;
    if (iconRef == null || !iconRef.startsWith('@res/0x')) return;

    final resId = int.tryParse(iconRef.substring(5), radix: 16);
    if (resId == null) return;

    meta.iconPaths = parser.getAllFilePaths(resId);
  }

  List<String> _scanNativeCodes() {
    final archive = _archive;
    if (archive == null) return [];

    final abis = <String>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name;
      if (name.startsWith('lib/')) {
        final parts = name.split('/');
        if (parts.length >= 3) {
          abis.add(parts[1]); // e.g., arm64-v8a
        }
      }
    }
    return abis.toList()..sort();
  }

  void close() {
    _archive?.clearSync();
    _archive = null;
    _arscParser = null;
  }
}
```

**Step 2: 更新导出**

`lib/apk_parser.dart` 添加：
```dart
export 'src/apk_reader.dart';
```

**Step 3: Commit**

```bash
git add packages/apk_parser/
git commit -m "feat(apk_parser): 实现 ApkReader 统一解析入口"
```

---

### Task 11: 实现 parse.dart CLI

**Files:**
- Create: `packages/apk_parser/bin/parse.dart`

**Step 1: 实现单 APK 解析 CLI**

```dart
import 'dart:io';
import 'package:apk_parser/apk_parser.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run bin/parse.dart <apk_file>');
    exit(1);
  }

  final filePath = args[0];
  if (!File(filePath).existsSync()) {
    print('Error: File not found: $filePath');
    exit(1);
  }

  final sw = Stopwatch()..start();
  final reader = ApkReader();

  if (!await reader.open(filePath)) {
    print('Error: Failed to open APK file');
    exit(1);
  }

  try {
    final meta = await reader.parse();
    sw.stop();

    if (meta == null) {
      print('Error: Failed to parse APK');
      exit(1);
    }

    print('=== APK Info (Dart parser) ===');
    print('Time: ${sw.elapsedMilliseconds}ms');
    print('');
    print('packageName:     ${meta.packageName}');
    print('versionCode:     ${meta.versionCode}');
    print('versionName:     ${meta.versionName}');
    print('label:           ${meta.label}');
    print('minSdkVersion:   ${meta.minSdkVersion}');
    print('targetSdkVersion:${meta.targetSdkVersion}');
    print('compileSdkVer:   ${meta.compileSdkVersion}');
    print('');
    print('permissions (${meta.permissions.length}):');
    for (final p in meta.permissions) {
      print('  $p');
    }
    print('');
    print('features (${meta.features.length}):');
    for (final f in meta.features) {
      print('  $f');
    }
    print('');
    print('nativeCodes:     ${meta.nativeCodes}');
    print('locales:         ${meta.locales.take(20).toList()}${meta.locales.length > 20 ? "... (${meta.locales.length} total)" : ""}');
    print('densities:       ${meta.densities}');
    print('');
    print('applicationIcon: ${meta.applicationIcon}');
    print('iconPaths:');
    meta.iconPaths.forEach((dpi, path) {
      print('  ${dpi}dpi -> $path');
    });
    print('');
    print('labels (${meta.labels.length} locales):');
    meta.labels.entries.take(10).forEach((e) {
      print('  ${e.key}: ${e.value}');
    });
    if (meta.labels.length > 10) {
      print('  ... (${meta.labels.length} total)');
    }
    print('');
    print('launchableActivities:');
    for (final a in meta.launchableActivities) {
      print('  $a');
    }
  } finally {
    reader.close();
  }
}
```

**Step 2: 验证运行**

Run: `cd D:/Develop/workspace/flutter_project/apk_info_tool/packages/apk_parser && dart pub get && dart run bin/parse.dart <some_apk_file>`
Expected: 输出 APK 解析结果

**Step 3: Commit**

```bash
git add packages/apk_parser/
git commit -m "feat(apk_parser): 实现 parse.dart CLI 解析工具"
```

---

### Task 12: 实现 compare.dart 对比测试 CLI

**Files:**
- Create: `packages/apk_parser/bin/compare.dart`

**Step 1: 实现对比测试 CLI**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:apk_parser/apk_parser.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run bin/compare.dart <apk_file_or_directory> [--aapt2 <path>]');
    exit(1);
  }

  final target = args[0];
  var aapt2Path = 'aapt2';
  final aapt2Index = args.indexOf('--aapt2');
  if (aapt2Index >= 0 && aapt2Index + 1 < args.length) {
    aapt2Path = args[aapt2Index + 1];
  }

  // 收集 APK 文件列表
  final apkFiles = <File>[];
  final entity = FileSystemEntity.typeSync(target);
  if (entity == FileSystemEntityType.directory) {
    final dir = Directory(target);
    await for (final file in dir.list(recursive: true)) {
      if (file is File && file.path.toLowerCase().endsWith('.apk')) {
        apkFiles.add(file);
      }
    }
  } else if (entity == FileSystemEntityType.file) {
    apkFiles.add(File(target));
  } else {
    print('Error: $target not found');
    exit(1);
  }

  if (apkFiles.isEmpty) {
    print('No APK files found');
    exit(1);
  }

  print('Found ${apkFiles.length} APK file(s)\n');

  var passCount = 0;
  var failCount = 0;
  var totalDartMs = 0;
  var totalAapt2Ms = 0;
  final failures = <String, List<String>>{};

  for (var i = 0; i < apkFiles.length; i++) {
    final file = apkFiles[i];
    final fileName = file.uri.pathSegments.last;
    print('${"=" * 50}');
    print('[${i + 1}/${apkFiles.length}] $fileName');
    print('${"=" * 50}');

    // Dart 解析
    final dartSw = Stopwatch()..start();
    final reader = ApkReader();
    ApkMeta? dartResult;
    try {
      if (await reader.open(file.path)) {
        dartResult = await reader.parse();
      }
    } catch (e) {
      print('  Dart parse error: $e');
    } finally {
      reader.close();
    }
    dartSw.stop();
    final dartMs = dartSw.elapsedMilliseconds;
    totalDartMs += dartMs;

    // aapt2 解析
    final aapt2Sw = Stopwatch()..start();
    Map<String, String>? aapt2Result;
    try {
      final result = await Process.run(
        aapt2Path,
        ['dump', 'badging', file.path],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 120));
      if (result.exitCode == 0) {
        aapt2Result = _parseAapt2Output(result.stdout.toString());
      }
    } catch (e) {
      print('  aapt2 error: $e');
    }
    aapt2Sw.stop();
    final aapt2Ms = aapt2Sw.elapsedMilliseconds;
    totalAapt2Ms += aapt2Ms;

    if (dartResult == null || aapt2Result == null) {
      print('  SKIP (parse failed)\n');
      continue;
    }

    // 逐字段对比
    final fields = _buildComparisonFields(dartResult, aapt2Result);
    var allMatch = true;
    final fileFailures = <String>[];

    print('  ${"Field".padRight(25)} ${"Dart".padRight(30)} ${"aapt2".padRight(30)} Match');
    print('  ${"-" * 90}');

    for (final field in fields) {
      final match = field.dartValue == field.aapt2Value;
      final icon = match ? 'OK' : 'FAIL';
      if (!match) {
        allMatch = false;
        fileFailures.add(field.name);
      }
      print('  ${field.name.padRight(25)} '
          '${_truncate(field.dartValue, 28).padRight(30)} '
          '${_truncate(field.aapt2Value, 28).padRight(30)} '
          '$icon');
    }

    final speedup = aapt2Ms > 0 ? (aapt2Ms / dartMs).toStringAsFixed(1) : '?';
    print('');
    print('  Time: Dart=${dartMs}ms  aapt2=${aapt2Ms}ms  (${speedup}x)');

    if (allMatch) {
      passCount++;
      print('  Result: PASS');
    } else {
      failCount++;
      failures[fileName] = fileFailures;
      print('  Result: FAIL (${fileFailures.join(", ")})');
    }
    print('');
  }

  // 汇总
  print('${"=" * 50}');
  print('Summary: ${apkFiles.length} APKs tested');
  print('  Pass: $passCount  Fail: $failCount');
  if (totalAapt2Ms > 0) {
    print('  Avg speedup: ${(totalAapt2Ms / totalDartMs).toStringAsFixed(1)}x');
  }
  if (failures.isNotEmpty) {
    print('  Failures:');
    failures.forEach((file, fields) {
      print('    $file: ${fields.join(", ")}');
    });
  }
}

class _CompareField {
  final String name;
  final String dartValue;
  final String aapt2Value;
  _CompareField(this.name, this.dartValue, this.aapt2Value);
}

List<_CompareField> _buildComparisonFields(
    ApkMeta dart, Map<String, String> aapt2) {
  return [
    _CompareField('packageName', dart.packageName ?? '', aapt2['packageName'] ?? ''),
    _CompareField('versionCode', '${dart.versionCode ?? ""}', aapt2['versionCode'] ?? ''),
    _CompareField('versionName', dart.versionName ?? '', aapt2['versionName'] ?? ''),
    _CompareField('label', dart.label ?? '', aapt2['label'] ?? ''),
    _CompareField('minSdkVersion', '${dart.minSdkVersion ?? ""}', aapt2['sdkVersion'] ?? ''),
    _CompareField('targetSdkVersion', '${dart.targetSdkVersion ?? ""}', aapt2['targetSdkVersion'] ?? ''),
    _CompareField('permissions', '${dart.permissions.length} items', aapt2['permissionCount'] ?? '?'),
    _CompareField('nativeCodes', dart.nativeCodes.join(','), aapt2['nativeCodes'] ?? ''),
  ];
}

Map<String, String> _parseAapt2Output(String output) {
  final result = <String, String>{};
  var permCount = 0;
  final nativeCodes = <String>[];

  for (final line in output.split('\n')) {
    final colonPos = line.indexOf(':');
    if (colonPos < 0) continue;
    final key = line.substring(0, colonPos).trim();
    final value = line.substring(colonPos + 1).trim();

    switch (key) {
      case 'package':
        final nameMatch = RegExp(r"name='([^']*)'").firstMatch(value);
        final vcMatch = RegExp(r"versionCode='([^']*)'").firstMatch(value);
        final vnMatch = RegExp(r"versionName='([^']*)'").firstMatch(value);
        if (nameMatch != null) result['packageName'] = nameMatch.group(1)!;
        if (vcMatch != null) result['versionCode'] = vcMatch.group(1)!;
        if (vnMatch != null) result['versionName'] = vnMatch.group(1)!;
      case 'application-label':
        result['label'] = value.replaceAll("'", '');
      case 'sdkVersion':
      case 'minSdkVersion':
        result['sdkVersion'] = value.replaceAll("'", '');
      case 'targetSdkVersion':
        result['targetSdkVersion'] = value.replaceAll("'", '');
      case 'uses-permission':
        permCount++;
      case 'native-code':
        nativeCodes.addAll(
            value.split(' ').map((s) => s.replaceAll("'", '').trim()).where((s) => s.isNotEmpty));
    }
  }

  result['permissionCount'] = '$permCount items';
  result['nativeCodes'] = nativeCodes.join(',');
  return result;
}

String _truncate(String s, int max) {
  return s.length <= max ? s : '${s.substring(0, max - 2)}..';
}
```

**Step 2: 验证运行**

Run: `cd D:/Develop/workspace/flutter_project/apk_info_tool/packages/apk_parser && dart run bin/compare.dart <some_apk_or_dir>`
Expected: 输出对比报告

**Step 3: Commit**

```bash
git add packages/apk_parser/
git commit -m "feat(apk_parser): 实现 compare.dart 对比测试 CLI"
```

---

### Task 13: 调试和修复 arsc 解析器（迭代任务）

这是一个迭代任务，通过 compare.dart 发现问题并逐个修复。

**预期常见问题：**
1. 字符串池偏移量计算错误（UTF-8/UTF-16 边界）
2. ResTable_type 的 entry 偏移量计算
3. ResTable_config 的 size 变体处理
4. Complex/Bag entry 解析
5. 多 Package 的资源 ID 匹配

**方法：**
- 对每个 compare 失败的字段，添加调试输出定位原因
- 修复后重新运行 compare 验证
- 每次修复独立 commit

---

## 阶段 3：集成主程序

### Task 14: 添加 parserEngine 配置项

**Files:**
- Modify: `lib/config.dart` — 添加 `parserEngine` 配置
- Modify: `lib/pages/setting_page.dart` — 添加 UI 切换项
- Modify: `lib/providers/setting_provider.dart` — 如需要

**Step 1: 在 config.dart 添加配置**

在 `Config` 类中，`enableDebug` 之后添加：

```dart
static const kParserBuiltin = "builtin";
static const kParserAapt2 = "aapt2";
static final parserEngine = ConfigItem("parser_engine", kParserAapt2);
```

并将 `parserEngine` 添加到 `_globalItems` 列表中。

**Step 2: 在设置页面添加切换项**

参考现有的 `aapt2Source` 切换项风格，添加解析引擎选择下拉框。

**Step 3: Commit**

```bash
git add lib/config.dart lib/pages/setting_page.dart
git commit -m "feat: 添加解析引擎配置项（aapt2/builtin 切换）"
```

---

### Task 15: 主项目添加 apk_parser 依赖

**Files:**
- Modify: `pubspec.yaml` — 添加 path 依赖

**Step 1: 添加依赖**

在 `pubspec.yaml` 的 `dependencies` 中添加：

```yaml
  apk_parser:
    path: packages/apk_parser
```

**Step 2: 获取依赖**

Run: `cd D:/Develop/workspace/flutter_project/apk_info_tool && flutter pub get`

**Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "feat: 添加 apk_parser 本地包依赖"
```

---

### Task 16: 实现 builtin 解析路径

**Files:**
- Modify: `lib/apkparser/apk_info.dart` — 在 `getApkInfo()` 中添加 builtin 分支

**Step 1: 在 getApkInfo 中添加 builtin 解析路径**

在普通 APK 解析入口（约第 409 行），根据 `Config.parserEngine.value` 选择解析方式：

```dart
if (Config.parserEngine.value == Config.kParserBuiltin) {
  // 内置 Dart 解析
  return await _getApkInfoBuiltin(apk, apkInfo);
}

// 原有 aapt2 逻辑不变...
```

新增 `_getApkInfoBuiltin` 函数：

```dart
Future<ApkInfo?> _getApkInfoBuiltin(String apk, ApkInfo apkInfo) async {
  final totalSw = Stopwatch()..start();
  final phaseSw = Stopwatch();

  final reader = ApkReader();
  try {
    phaseSw..reset()..start();
    if (!await reader.open(apk)) return null;
    final openMs = phaseSw.elapsedMilliseconds;

    phaseSw..reset()..start();
    final meta = await reader.parse();
    final parseMs = phaseSw.elapsedMilliseconds;

    if (meta == null) return null;

    // ApkMeta → ApkInfo 转换
    _applyMetaToApkInfo(meta, apkInfo);

    // 图标加载（复用现有逻辑，但图标路径来自 arsc）
    phaseSw..reset()..start();
    final iconImage = await apkInfo.loadIcon();
    if (iconImage != null) {
      apkInfo.mainIconImage ??= iconImage;
    }
    final iconMs = phaseSw.elapsedMilliseconds;

    // 签名（仍走 apksigner）
    var signatureMs = 0;
    if (Config.enableSignature.value) {
      phaseSw..reset()..start();
      try {
        apkInfo.signatureInfo = await getSignatureInfo(apk);
      } catch (e) {
        apkInfo.signatureInfo = "获取签名信息失败: $e";
      }
      signatureMs = phaseSw.elapsedMilliseconds;
    }

    totalSw.stop();
    log.info("[PERF] getApkInfo(builtin): total=${totalSw.elapsedMilliseconds}ms"
        " | open=${openMs}ms | parse=${parseMs}ms"
        " | icon=${iconMs}ms | signature=${signatureMs}ms");

    return apkInfo;
  } finally {
    reader.close();
  }
}

void _applyMetaToApkInfo(ApkMeta meta, ApkInfo apkInfo) {
  apkInfo.packageName = meta.packageName;
  apkInfo.versionCode = meta.versionCode;
  apkInfo.versionName = meta.versionName;
  apkInfo.sdkVersion = meta.minSdkVersion;
  apkInfo.targetSdkVersion = meta.targetSdkVersion;
  apkInfo.compileSdkVersion = meta.compileSdkVersion;
  apkInfo.compileSdkVersionCodename = meta.compileSdkVersionCodename;
  apkInfo.platformBuildVersionName = meta.platformBuildVersionName;
  apkInfo.platformBuildVersionCode = meta.platformBuildVersionCode;
  apkInfo.label = meta.label;
  apkInfo.labels = meta.labels;
  apkInfo.usesPermissions = meta.permissions;
  apkInfo.userFeatures = meta.features;
  apkInfo.userFeaturesNotRequired = meta.featuresNotRequired;
  apkInfo.supportsScreens = meta.screenSizes;
  apkInfo.nativeCodes = meta.nativeCodes;
  apkInfo.locales = meta.locales;
  apkInfo.densities = meta.densities.map((d) => d.toString()).toList();

  if (meta.applicationIcon != null) {
    apkInfo.mainIconPath = meta.applicationIcon;
  }
  // 从 arsc 解析的图标路径填充 icons map
  meta.iconPaths.forEach((dpi, path) {
    apkInfo.icons[dpi.toString()] = path;
  });

  if (meta.launchableActivities.isNotEmpty) {
    apkInfo.launchableActivity = meta.launchableActivities
        .map((a) => Component(name: a.name, label: a.label, icon: a.icon))
        .toList();
  }
  if (meta.applicationName != null) {
    apkInfo.application.name = meta.applicationName;
    apkInfo.application.label = meta.label;
    apkInfo.application.icon = meta.applicationIcon;
  }
}
```

**Step 2: 验证编译通过**

Run: `flutter analyze lib/apkparser/apk_info.dart`

**Step 3: Commit**

```bash
git add lib/apkparser/apk_info.dart
git commit -m "feat: 实现 builtin 内置解析路径，通过设置切换解析引擎"
```

---

### Task 17: 端到端验证

**Step 1:** 以 builtin 模式运行主程序，解析多个 APK，验证信息显示正确
**Step 2:** 以 aapt2 模式运行，对比结果一致性
**Step 3:** 验证 XAPK/ZIP 场景仍正常工作
**Step 4:** 验证图标渲染、签名检查等功能不受影响
**Step 5:** 确认无回退后合并

---

## 注意事项

1. **arsc 解析器是关键路径** — Task 9 的实现需要大量真实 APK 测试，预留充足调试时间
2. **BinaryXmlDecompressor 的迁移** — 新包中的副本不应引入 Flutter 依赖，确保纯 Dart
3. **渐进切换** — 阶段 3 初始默认 aapt2，经充分验证后再切换默认值
4. **archive 包兼容** — 新包和主项目共用同一个 fork 版本的 archive 包
