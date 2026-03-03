# APK 内置解析器设计方案

## 背景

当前项目通过调用外部工具 `aapt2 dump badging` 解析 APK 基础信息，在大文件上耗时严重（aapt2 会扫描大量无关资源）。项目已有二进制 XML 反编译器（`BinaryXmlDecompressor`）和 ZIP 读取能力（`ZipHelper`），但从未用于 AndroidManifest.xml 解析。

本方案目标：实现纯 Dart 的 APK 解析库，分阶段替代 aapt2 依赖，提升大文件解析速度并消除临时解压文件。

## 分阶段实施

### 阶段 1：解析耗时埋点

在 `getApkInfo()` 流程中增加 `Stopwatch` 埋点，建立性能基准。

**记录阶段：**

| 阶段 | 位置 | 场景 |
|------|------|------|
| ZIP 打开 | `zip.open()` | XAPK/ZIP |
| ZIP 文件提取 | `zip.extractFile()` | XAPK/ZIP |
| XAPK manifest 解析 | `parseXapkManifest()` | XAPK/ZIP |
| aapt2 dump badging | `Process.run(aapt2, ['dump', 'badging'])` | 所有 APK |
| aapt2 输出解析 | `parseApkInfoFromOutput()` | 所有 APK |
| 图标收集 | `collectIconCandidates()` | 所有 APK |
| 图标渲染 | `loadIcon()` | 所有 APK |
| 签名检查 | `getSignatureInfo()` | 可选 |
| 总耗时 | 整个 `getApkInfo()` | 所有 |

**输出格式：**
```
[PERF] getApkInfo: total=3245ms | aapt2_badging=2800ms | output_parse=12ms | icon_collect=320ms | icon_render=95ms | signature=0ms
```

**改动范围：** 仅 `apk_info.dart` 一个文件。

---

### 阶段 2：独立解析库

位置：`packages/apk_parser/`，纯 Dart package，不依赖 Flutter。

#### 2.1 包结构

```
packages/apk_parser/
├── pubspec.yaml
├── lib/
│   ├── apk_parser.dart           # 公共导出
│   └── src/
│       ├── apk_reader.dart       # ZIP 读取封装，统一入口
│       ├── manifest_parser.dart  # AndroidManifest.xml 二进制解析 → 结构化数据
│       ├── arsc_parser.dart      # resources.arsc 解析器
│       ├── binary_xml.dart       # 从主项目迁移 + 增强（结构化 XmlElement 输出）
│       ├── byte_data_reader.dart # 从主项目迁移
│       ├── models.dart           # ApkMeta 数据模型
│       └── arsc/
│           ├── string_pool.dart      # 字符串池解析
│           ├── resource_table.dart   # ResTable 主结构
│           ├── type_spec.dart        # TypeSpec 解析
│           └── resource_value.dart   # 资源值解析
├── bin/
│   ├── parse.dart                # CLI：解析单个 APK 并输出结果
│   └── compare.dart              # CLI：对比 Dart 解析 vs aapt2
└── test/
    └── arsc_parser_test.dart
```

#### 2.2 数据模型

```dart
class ApkMeta {
  String? packageName;
  int? versionCode;
  String? versionName;
  int? minSdkVersion;
  int? targetSdkVersion;
  int? compileSdkVersion;
  String? label;                    // 通过 arsc 解析后的实际文本
  Map<String, String> labels;       // locale → label 多语言
  String? applicationIcon;          // 图标资源引用 ID
  Map<int, String> iconPaths;       // dpi → 实际文件路径
  List<String> permissions;
  List<String> features;
  List<String> screenSizes;
  List<String> nativeCodes;         // 扫描 lib/ 目录
  List<String> locales;             // 通过 arsc 获取
  List<String> densities;           // 通过 arsc 获取
  List<LaunchableActivity> activities;
}
```

#### 2.3 解析流程

```
APK (ZIP)
  ├─ AndroidManifest.xml → BinaryXmlDecompressor → XmlElement 树
  │    ├─ 直接值：package, version, sdk, permissions, features, screens
  │    └─ 资源引用 ID：label=@res/0x7f0d001a, icon=@res/0x7f080001
  ├─ resources.arsc → ArscParser
  │    ├─ 字符串池（StringPool）
  │    ├─ 资源表（ResTable → Package → TypeSpec → Type → Entry）
  │    └─ 按 ID 解析：label → "微信", icon → "res/mipmap-xxxhdpi/ic_launcher.png"
  └─ lib/ 目录扫描 → nativeCodes = [arm64-v8a, armeabi-v7a]
```

#### 2.4 BinaryXmlDecompressor 增强

- 新增 `decompressToElements()` → 输出结构化 `XmlElement` 树
- 原有 `decompressXml()` 保持不变（向后兼容）

#### 2.5 ArscParser API

```dart
class ArscParser {
  ArscParser(Uint8List data);

  String? getStringValue(int resourceId, {String? locale});
  String? getFilePath(int resourceId, {int? density});
  List<String> getLocales();
  List<int> getDensities();
}
```

参考实现：android-classyshark / apktool 的 Java ResourceTypes 解析。

#### 2.6 对比测试 CLI

`bin/compare.dart`：
- 输入：单个 APK 文件或目录（自动扫描 `.apk`）
- 需要系统中有 aapt2 作为对照组
- 逐字段自动对比（packageName, versionCode, label 等）
- 输出差异报告 + 耗时对比统计 + 汇总

---

### 阶段 3：集成主程序

#### 3.1 配置项

`config.dart` 新增：
```dart
static const kParserBuiltin = "builtin";
static const kParserAapt2 = "aapt2";
static final parserEngine = ConfigItem("parser_engine", kParserAapt2);
```

设置页面增加解析引擎切换项。

#### 3.2 集成方式

`pubspec.yaml` 添加 path 依赖：
```yaml
dependencies:
  apk_parser:
    path: packages/apk_parser
```

#### 3.3 解析入口改造

`getApkInfo()` 根据配置选择路径：
- `builtin`：ZIP 打开 → ManifestParser + ArscParser → 填充 ApkInfo
- `aapt2`：现有流程不变

两条路径共用同一个 `ApkInfo` 数据模型。

#### 3.4 XAPK 场景改进

builtin 模式下无需提取 base.apk 到临时文件，直接在内存中解析嵌套 ZIP 内的 AndroidManifest.xml + resources.arsc。

#### 3.5 不替换的部分

- 签名信息仍走 apksigner（独立功能，默认关闭）
- 图标渲染流程不变（已基于 ZIP 读取）

#### 3.6 渐进演进

```
v1: 默认 aapt2，设置可切换 builtin
v2: 默认 builtin，设置可回退 aapt2
v3: 可选移除 aapt2 依赖
```

---

## 工作量与难度

| 阶段 | 工作量 | 难度 |
|------|--------|------|
| 阶段 1：耗时埋点 | 0.5 天 | 低 |
| 阶段 2a：包骨架 + Manifest 解析 | 1-2 天 | 低 |
| 阶段 2b：resources.arsc 解析器 | 5-8 天 | 高 |
| 阶段 2c：对比测试 CLI | 1-2 天 | 中 |
| 阶段 3：集成 + 设置页 | 2-3 天 | 中 |
| **总计** | **约 10-15 天** | |

arsc 解析器是关键路径，占总工作量 40-50%。

## 技术风险

1. **resources.arsc 边界情况多** — Android 版本迭代会引入新的资源类型和编码方式，需要用大量真实 APK 测试覆盖
2. **嵌套 ZIP 内存占用** — XAPK 中 base.apk 需要在内存中解析，超大 APK 可能需要流式处理
3. **字符串编码** — arsc 中的 UTF-8/UTF-16 混合编码需要正确处理
