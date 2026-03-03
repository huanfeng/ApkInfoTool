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
    InputFileStream? inputStream;
    try {
      inputStream = InputFileStream(filePath);
      _archive = ZipDecoder().decodeStream(inputStream);
      return true;
    } catch (e) {
      return false;
    } finally {
      inputStream?.closeSync();
    }
  }

  /// 从内存数据打开（用于嵌套 ZIP 场景）
  bool openBytes(Uint8List data) {
    try {
      _archive = ZipDecoder().decodeBytes(data);
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
    final manifestBytes = manifestFile.content;
    final meta = ManifestParser.parse(manifestBytes);

    // 2. 读取并解析 resources.arsc
    final arscFile = archive.findFile('resources.arsc');
    if (arscFile != null) {
      final arscBytes = arscFile.content;
      try {
        _arscParser = ArscParser(arscBytes);
        _resolveLabel(meta);
        _resolveIconPaths(meta);
        meta.locales = _arscParser!.getLocales().toList();
        meta.densities = _arscParser!.getDensities().toList();
      } catch (e) {
        // arsc 解析失败不影响基本信息
      }
    }

    // 3. 扫描 lib/ 目录获取 native codes
    meta.nativeCodes = _scanNativeCodes();

    return meta;
  }

  ArscParser? get arscParser => _arscParser;

  Uint8List? readFile(String fileName) {
    final file = _archive?.findFile(fileName);
    return file?.content;
  }

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

    if (meta.label != null && meta.label!.startsWith('@res/0x')) {
      final resId = int.tryParse(meta.label!.substring(5), radix: 16);
      if (resId != null) {
        final resolved = parser.getStringValue(resId);
        if (resolved != null) meta.label = resolved;

        for (final locale in parser.getLocales()) {
          final localizedLabel = parser.getStringValue(resId, locale: locale);
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

    final paths = parser.getAllFilePaths(resId);
    for (final entry in paths) {
      meta.iconPaths[entry.key] = entry.value;
    }
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
          abis.add(parts[1]);
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
