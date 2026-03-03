import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:apk_info_tool/apkparser/binary_xml.dart';
import 'package:apk_info_tool/utils/logger.dart';
import 'package:apk_info_tool/utils/zip_helper.dart';
import 'package:apk_parser/apk_parser.dart' as apk_parser;
import 'package:path_drawing/path_drawing.dart';
import 'package:xml/xml.dart' as xml;

/// Adaptive icon 导出 SVG 时的结构化数据
class AdaptiveIconSvgData {
  final String? backgroundColor; // #AARRGGBB hex
  final xml.XmlElement? backgroundVector;
  final xml.XmlElement? foregroundVector;

  /// 前景层缩放比例（与 AdaptiveIconRenderer 渲染一致）。
  /// vector drawable 前景使用 1.28x，bitmap 使用 1.60x。
  final double foregroundScale;

  AdaptiveIconSvgData({
    this.backgroundColor,
    this.backgroundVector,
    this.foregroundVector,
    this.foregroundScale = 1.0,
  });

  bool get hasContent =>
      backgroundColor != null ||
      backgroundVector != null ||
      foregroundVector != null;
}

class AdaptiveIconRenderer {
  AdaptiveIconRenderer({
    required this.apkPath,
    required this.aaptPath,
    required this.zip,
  });

  final String apkPath;
  final String aaptPath;
  final ZipHelper zip;

  /// 释放缓存的 dart:ui.Image GPU 资源
  void dispose() {
    for (final image in _bitmapCache.values) {
      image.dispose();
    }
    _bitmapCache.clear();
    _failedBitmapPath.clear();
  }

  /// 从 ArscParser 数据预加载资源表，替代 aapt2 dump resources
  void preloadResourceTableFromArsc(
      Map<int, apk_parser.ResourceInfo> resources) {
    final byId = <String, _ResourceEntry>{};
    final byName = <String, List<_ResourceEntry>>{};

    for (final info in resources.values) {
      final id = _normalizeResourceId(info.idHex);
      final name = info.name.toLowerCase();
      final entry = byId.putIfAbsent(
        id,
        () => _ResourceEntry(id: id, name: name),
      );
      entry.name = name;

      for (final path in info.filePaths) {
        final normalized = _normalizeZipPath(path);
        if (normalized.isNotEmpty && !entry.filePaths.contains(normalized)) {
          entry.filePaths.add(normalized);
        }
      }
      for (final refId in info.references) {
        final refHex =
            '@res/0x${refId.toRadixString(16).padLeft(8, '0')}';
        if (!entry.references.contains(refHex)) {
          entry.references.add(refHex);
        }
      }

      final list = byName.putIfAbsent(name, () => []);
      if (!list.contains(entry)) list.add(entry);
    }

    _resourceTable = _ResourceTable(byId: byId, byName: byName);
    _debug(
        'resourceTable preloaded from arsc: byId=${byId.length}, byName=${byName.length}');
  }

  static const int _kCanvasSize = 432;
  static const int _kMaxDepth = 16;
  static const double _kAdaptiveForegroundScaleBitmap = 1.60;
  static const double _kAdaptiveForegroundScaleVector = 1.28;
  static final RegExp _kResourceIdPattern = RegExp(
    r'^@(?:res/)?(0x[0-9a-fA-F]+)$',
  );
  static final RegExp _kNamedResourcePattern = RegExp(
    r'^@(?:\+)?(?:[\w.]+:)?([a-zA-Z_][\w-]*)/([a-zA-Z0-9_.$-]+)$',
  );
  static final RegExp _kHexColorPattern = RegExp(
    r'^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
  );
  static final RegExp _kResourceLinePattern = RegExp(
    r'^\s*resource\s+(0x[0-9a-fA-F]+)\s+([A-Za-z0-9_./$-]+)',
  );
  static final RegExp _kResourceFilePattern = RegExp(
    r'\(file\)\s+([^\s)]+)',
    caseSensitive: false,
  );
  static final RegExp _kResourceFileNoMarkerPattern = RegExp(
    r'(?:^|\s)(res/[^\s"]+\.(?:png|jpg|jpeg|webp|xml|9\.png))',
    caseSensitive: false,
  );
  static final RegExp _kResourceColorPattern = RegExp(
    r'#[0-9a-fA-F]{6,8}\b',
  );
  static final RegExp _kResourceRefPattern = RegExp(
    r'@(0x[0-9a-fA-F]+|(?:[\w.]+:)?[a-zA-Z_][\w-]*/[a-zA-Z0-9_.$-]+)',
  );
  static final RegExp _kDensityPattern = RegExp(
    r'-(ldpi|mdpi|hdpi|xhdpi|xxhdpi|xxxhdpi)(?:-|$)',
  );
  static final RegExp _kLeadingNumberPattern =
      RegExp(r'^[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');
  static final RegExp _kAndroidIntLiteralPattern = RegExp(
    r'^(?:0x-?[0-9a-fA-F]+|-?0x[0-9a-fA-F]+|-?[0-9]+)$',
  );
  static const Map<String, String> _kFrameworkColorFallback = {
    '0x0106000c': '#ff000000', // android:color/black
    '0x0106000d': '#ffffffff', // android:color/white
    '0x01060000': '#00000000', // android:color/transparent
    '0x0106000e': '#ff444444', // android:color/darker_gray
    '0x01060010': '#ffaaaaaa', // android:color/lighter_gray
    '0x01060012': '#ff0000ff', // android:color/holo_blue_bright
    '0x01060013': '#ff0099cc', // android:color/holo_blue_dark
    '0x01060014': '#ff33b5e5', // android:color/holo_blue_light
    '0x01060015': '#ffff8800', // android:color/holo_orange_dark
    '0x01060016': '#ffffbb33', // android:color/holo_orange_light
    '0x01060017': '#ff669900', // android:color/holo_green_dark
    '0x01060018': '#ff99cc00', // android:color/holo_green_light
    '0x01060019': '#ffcc0000', // android:color/holo_red_dark
    '0x0106001a': '#ffff4444', // android:color/holo_red_light
    '0x0106001b': '#ff9933cc', // android:color/holo_purple
  };

  final BinaryXmlDecompressor _binaryXmlDecompressor = BinaryXmlDecompressor();
  _ResourceTable? _resourceTable;
  List<String>? _zipFiles;
  final Map<String, Image> _bitmapCache = {};
  final Set<String> _failedBitmapPath = {};
  Map<String, String>? _zipFileLowerMap;
  bool _didDraw = false;
  int _drawFillCount = 0;
  int _drawStrokeCount = 0;
  int _drawRectCount = 0;
  int _drawBitmapCount = 0;
  int _vectorPathTotal = 0;
  int _vectorPathFilled = 0;
  int _vectorPathStroked = 0;
  int _resolvedRefCount = 0;

  Future<Image?> render(
    String iconPath, {
    int? canvasSize,
    bool transparentBackground = false,
  }) async {
    final normalized = _normalizeZipPath(iconPath);
    if (normalized.isEmpty) return null;

    final size = canvasSize ?? _kCanvasSize;

    try {
      _didDraw = false;
      _drawFillCount = 0;
      _drawStrokeCount = 0;
      _drawRectCount = 0;
      _drawBitmapCount = 0;
      _vectorPathTotal = 0;
      _vectorPathFilled = 0;
      _vectorPathStroked = 0;
      _resolvedRefCount = 0;
      _debug('render start: iconPath=$normalized, apkPath=$apkPath, canvasSize=$size');
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final rect = Rect.fromLTWH(
        0,
        0,
        size.toDouble(),
        size.toDouble(),
      );
      if (!transparentBackground) {
        // 绘制白色底色：避免透明背景在深色主题下显示为黑色
        canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
      }
      await _renderDrawable(canvas, rect, normalized, 0);
      if (!_didDraw) {
        _debug('render end: no drawing happened');
        return null;
      }
      final picture = recorder.endRecording();
      _debug(
          'render end: drawn=true fills=$_drawFillCount strokes=$_drawStrokeCount rects=$_drawRectCount bitmaps=$_drawBitmapCount vectorPath(total=$_vectorPathTotal, filled=$_vectorPathFilled, stroked=$_vectorPathStroked) refs=$_resolvedRefCount');
      final image = await picture.toImage(size, size);
      picture.dispose();
      return image;
    } catch (e) {
      log.warning('AdaptiveIconRenderer.render failed: $e');
      return null;
    }
  }

  /// 将图标路径解析为底层的 vector drawable XML 元素。
  /// 对于 adaptive-icon XML，会跟踪 foreground drawable 引用。
  /// 如果找不到 vector drawable，返回 null。
  Future<xml.XmlElement?> resolveToVectorElement(String iconPath) async {
    final normalized = _normalizeZipPath(iconPath);
    if (normalized.isEmpty) return null;
    if (!normalized.toLowerCase().endsWith('.xml')) return null;

    final root = await _loadXmlRoot(normalized);
    if (root == null) return null;

    final tag = root.name.local.toLowerCase();
    if (tag == 'vector') return root;

    if (tag == 'adaptive-icon') {
      // 优先从 foreground 层查找
      final foreground = _findDirectChild(root, 'foreground');
      if (foreground != null) {
        final result = await _resolveContainerToVector(foreground, 0);
        if (result != null) return result;
      }

      // 回退到 background 层
      final background = _findDirectChild(root, 'background');
      if (background != null) {
        final result = await _resolveContainerToVector(background, 0);
        if (result != null) return result;
      }
    }

    return null;
  }

  /// 将 adaptive-icon 图标路径解析为包含 background 和 foreground 的完整结构。
  /// 用于 SVG 导出时保留所有图层信息。
  Future<AdaptiveIconSvgData?> resolveAdaptiveIconForSvg(
      String iconPath) async {
    final normalized = _normalizeZipPath(iconPath);
    if (normalized.isEmpty ||
        !normalized.toLowerCase().endsWith('.xml')) {
      return null;
    }

    final root = await _loadXmlRoot(normalized);
    if (root == null ||
        root.name.local.toLowerCase() != 'adaptive-icon') {
      return null;
    }

    String? bgColor;
    xml.XmlElement? bgVector;
    xml.XmlElement? fgVector;

    // 解析 background 层
    final background = _findDirectChild(root, 'background');
    if (background != null) {
      // 先尝试解析为 vector drawable
      bgVector = await _resolveContainerToVector(background, 0);
      if (bgVector == null) {
        // 尝试解析为纯色
        final drawableRef =
            _attr(background, 'drawable') ?? _findDrawableLikeValue(background);
        if (drawableRef != null && drawableRef.isNotEmpty) {
          final color = await _resolveColorRef(drawableRef, 0);
          if (color != null) {
            bgColor =
                '#${(color.toARGB32() & 0xffffffff).toRadixString(16).padLeft(8, '0')}';
          }
        }
        // 回退：尝试从内联子元素提取颜色（如 <color>, <shape> 等）
        if (bgColor == null) {
          final color = await _resolveContainerColor(background, 0);
          if (color != null) {
            bgColor =
                '#${(color.toARGB32() & 0xffffffff).toRadixString(16).padLeft(8, '0')}';
          }
        }
      }
    }

    // 解析 foreground 层
    final foreground = _findDirectChild(root, 'foreground');
    if (foreground != null) {
      fgVector = await _resolveContainerToVector(foreground, 0);
    }

    if (bgColor == null && bgVector == null && fgVector == null) {
      return null;
    }

    return AdaptiveIconSvgData(
      backgroundColor: bgColor,
      backgroundVector: bgVector,
      foregroundVector: fgVector,
      foregroundScale:
          fgVector != null ? _kAdaptiveForegroundScaleVector : 1.0,
    );
  }

  Future<xml.XmlElement?> _resolveContainerToVector(
      xml.XmlElement container, int depth) async {
    if (depth > _kMaxDepth) return null;

    // 检查内联 vector 子元素
    final vectorChild = _findDirectChild(container, 'vector');
    if (vectorChild != null) return vectorChild;

    // 解析 drawable 属性引用
    final drawableRef = _attr(container, 'drawable');
    if (drawableRef != null && drawableRef.isNotEmpty) {
      final resolvedPath = await _resolveDrawableToPath(drawableRef, depth + 1);
      if (resolvedPath != null &&
          resolvedPath.toLowerCase().endsWith('.xml')) {
        final resolvedRoot = await _loadXmlRoot(resolvedPath);
        if (resolvedRoot != null) {
          final resolvedTag = resolvedRoot.name.local.toLowerCase();
          if (resolvedTag == 'vector') return resolvedRoot;
          // 递归处理嵌套的 adaptive-icon 或其他容器
          if (resolvedTag == 'adaptive-icon') {
            final fg = _findDirectChild(resolvedRoot, 'foreground');
            if (fg != null) {
              final result = await _resolveContainerToVector(fg, depth + 1);
              if (result != null) return result;
            }
          }
        }
      }
    }

    return null;
  }

  /// 解析 vector drawable 元素中的资源引用颜色。
  /// 将 `@...` 颜色引用替换为 `#AARRGGBB` 格式的实际颜色值。
  Future<void> resolveVectorColorRefs(xml.XmlElement vector) async {
    await _resolveElementColors(vector, 0);
  }

  Future<void> _resolveElementColors(
      xml.XmlElement element, int depth) async {
    if (depth > _kMaxDepth) return;
    final tag = element.name.local.toLowerCase();

    if (tag == 'path') {
      await _resolveColorAttrs(
          element, ['fillColor', 'strokeColor'], depth);
    } else if (tag == 'vector' || tag == 'group') {
      for (final child in element.childElements) {
        await _resolveElementColors(child, depth + 1);
      }
    }
  }

  Future<void> _resolveColorAttrs(
      xml.XmlElement element, List<String> attrNames, int depth) async {
    for (final attrName in attrNames) {
      final value = _attr(element, attrName);
      if (value == null || value.isEmpty) continue;

      // 已经是 #AARRGGBB 格式的颜色 → VectorToSvg 可以直接处理
      if (_isColorLiteral(value.trim())) continue;

      // 尝试解析所有格式：Android 整数字面量、@ref 资源引用等
      final resolved = await _resolveColorRef(value, depth + 1);
      if (resolved != null) {
        final hexColor =
            '#${(resolved.toARGB32() & 0xffffffff).toRadixString(16).padLeft(8, '0')}';
        for (final attr in element.attributes) {
          if (attr.name.local == attrName) {
            element.setAttribute(attr.name.qualified, hexColor);
            break;
          }
        }
      }
    }
  }

  /// 解析 vector drawable 元素中的渐变资源引用。
  /// 将 `@...` 渐变引用解析并嵌入为 `<resolvedGradient>` 子元素，
  /// 供 VectorToSvg 转换为 SVG 渐变定义。
  Future<void> resolveVectorGradientRefs(xml.XmlElement vector) async {
    await _resolveElementGradients(vector, 0);
  }

  Future<void> _resolveElementGradients(
      xml.XmlElement element, int depth) async {
    if (depth > _kMaxDepth) return;
    final tag = element.name.local.toLowerCase();

    if (tag == 'path') {
      await _resolveGradientAttr(element, 'fillColor', depth);
    } else if (tag == 'vector' || tag == 'group') {
      for (final child in element.childElements) {
        await _resolveElementGradients(child, depth + 1);
      }
    }
  }

  Future<void> _resolveGradientAttr(
      xml.XmlElement element, String attrName, int depth) async {
    final value = _attr(element, attrName);
    if (value == null || value.isEmpty) return;

    final trimmed = value.trim();
    // 已经是颜色值 → 不需要处理
    if (_isColorLiteral(trimmed)) return;
    if (_isAndroidIntLiteral(trimmed)) return;
    if (trimmed.startsWith('#')) return;
    // 不是资源引用 → 跳过
    if (!trimmed.startsWith('@')) return;

    // 解析资源引用，查找是否指向渐变 XML
    final resolved = await _resolveResourceReference(trimmed, depth + 1);
    if (resolved == null || resolved == trimmed) return;
    if (!resolved.toLowerCase().endsWith('.xml')) return;

    final root = await _loadXmlRoot(resolved);
    if (root == null) return;
    if (root.name.local.toLowerCase() != 'gradient') return;

    // 构建嵌入的渐变元素
    final gradientElement =
        await _buildSvgGradientElement(root, depth + 1);
    if (gradientElement == null) return;

    // 将渐变元素嵌入 path，标记 fillColor 为 __gradient__
    element.children.add(gradientElement);
    for (final attr in element.attributes) {
      if (attr.name.local == attrName) {
        element.setAttribute(attr.name.qualified, '__gradient__');
        break;
      }
    }
  }

  Future<xml.XmlElement?> _buildSvgGradientElement(
      xml.XmlElement root, int depth) async {
    if (depth > _kMaxDepth) return null;

    final gradientType = (_attr(root, 'type') ?? 'linear').toLowerCase();
    final type = _parseGradientType(gradientType);

    final colors = <String>[];
    final offsets = <double>[];

    // 从 <item> 子元素解析 stop
    for (final item
        in root.childElements.where((e) => e.name.local == 'item')) {
      final colorValue = _attr(item, 'color');
      final color = await _resolveColorRef(colorValue, depth + 1);
      if (color == null) continue;
      colors.add(
          '#${(color.toARGB32() & 0xffffffff).toRadixString(16).padLeft(8, '0')}');
      offsets.add(_parseDimension(_attr(item, 'offset')));
    }

    // 回退：从 startColor/centerColor/endColor 属性解析
    if (colors.isEmpty) {
      final startColor =
          await _resolveColorRef(_attr(root, 'startColor'), depth + 1);
      final centerColor =
          await _resolveColorRef(_attr(root, 'centerColor'), depth + 1);
      final endColor =
          await _resolveColorRef(_attr(root, 'endColor'), depth + 1);
      if (startColor != null && endColor != null) {
        colors.add(
            '#${(startColor.toARGB32() & 0xffffffff).toRadixString(16).padLeft(8, '0')}');
        offsets.add(0);
        if (centerColor != null) {
          colors.add(
              '#${(centerColor.toARGB32() & 0xffffffff).toRadixString(16).padLeft(8, '0')}');
          offsets.add(0.5);
        }
        colors.add(
            '#${(endColor.toARGB32() & 0xffffffff).toRadixString(16).padLeft(8, '0')}');
        offsets.add(1);
      }
    }

    if (colors.length < 2) return null;

    // 构建 XML 元素
    final elem = xml.XmlElement(xml.XmlName('resolvedGradient'));
    switch (type) {
      case _GradientType.linear:
        elem.setAttribute('type', 'linear');
        elem.setAttribute(
            'startX', _parseDimension(_attr(root, 'startX')).toString());
        elem.setAttribute(
            'startY', _parseDimension(_attr(root, 'startY')).toString());
        elem.setAttribute(
            'endX', _parseDimension(_attr(root, 'endX')).toString());
        elem.setAttribute(
            'endY', _parseDimension(_attr(root, 'endY')).toString());
        break;
      case _GradientType.radial:
        elem.setAttribute('type', 'radial');
        elem.setAttribute(
            'centerX', _parseDimension(_attr(root, 'centerX')).toString());
        elem.setAttribute(
            'centerY', _parseDimension(_attr(root, 'centerY')).toString());
        elem.setAttribute('gradientRadius',
            _parseDimension(_attr(root, 'gradientRadius')).toString());
        break;
      case _GradientType.sweep:
        elem.setAttribute('type', 'sweep');
        elem.setAttribute(
            'centerX', _parseDimension(_attr(root, 'centerX')).toString());
        elem.setAttribute(
            'centerY', _parseDimension(_attr(root, 'centerY')).toString());
        break;
    }

    for (int i = 0; i < colors.length; i++) {
      final stop = xml.XmlElement(xml.XmlName('stop'));
      stop.setAttribute('offset', offsets[i].toString());
      stop.setAttribute('color', colors[i]);
      elem.children.add(stop);
    }

    return elem;
  }

  Future<List<String>> findBitmapAlternativesForPath(String filePath) async {
    final normalized = _normalizeZipPath(filePath);
    if (normalized.isEmpty) return const [];
    final table = await _loadResourceTable();
    if (table == null) return const [];

    final lower = normalized.toLowerCase();
    final result = <String>{};
    final matchedEntryNames = <String>{};
    for (final entry in table.byId.values) {
      final hasTarget = entry.filePaths.any(
        (p) => _normalizeZipPath(p).toLowerCase() == lower,
      );
      if (!hasTarget) continue;
      matchedEntryNames.add(entry.name);
      for (final file in entry.filePaths) {
        final candidate = _normalizeZipPath(file);
        if (_isBitmapPath(candidate)) {
          result.add(candidate);
        }
      }
    }

    final sorted = result.toList()
      ..sort((a, b) => _fileScore(b).compareTo(_fileScore(a)));
    if (sorted.isNotEmpty) {
      _debug(
          'findBitmapAlternativesForPath: $normalized -> ${sorted.join(", ")} entries=${matchedEntryNames.join("|")}');
    }
    return sorted;
  }

  Future<void> _renderDrawable(
    Canvas canvas,
    Rect rect,
    String source,
    int depth,
  ) async {
    if (depth > _kMaxDepth || source.isEmpty || rect.isEmpty) return;
    final trimmed = source.trim();
    if (trimmed.isEmpty) return;
    if (_isColorLiteral(trimmed)) {
      final color = _parseColor(trimmed);
      if (color != null) {
        canvas.drawRect(rect, Paint()..color = color);
        _didDraw = true;
        _drawRectCount++;
      }
      return;
    }

    if (_looksLikeZipPath(trimmed)) {
      await _renderDrawableFile(canvas, rect, trimmed, depth + 1);
      return;
    }

    if (!trimmed.startsWith('@')) {
      final tryPath = _normalizeZipPath(trimmed);
      if (_looksLikeZipPath(tryPath)) {
        await _renderDrawableFile(canvas, rect, tryPath, depth + 1);
      }
      return;
    }

    final resolved = await _resolveResourceReference(trimmed, depth + 1);
    if (resolved == null || resolved == trimmed) return;
    await _renderDrawable(canvas, rect, resolved, depth + 1);
  }

  Future<void> _renderDrawableFile(
    Canvas canvas,
    Rect rect,
    String filePath,
    int depth,
  ) async {
    final normalized = _normalizeZipPath(filePath);
    if (normalized.isEmpty) return;

    if (_isBitmapPath(normalized)) {
      final image = await _decodeBitmap(normalized);
      if (image == null) return;
      final src =
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
      final dst = _fitContain(src.size, rect);
      final paint = Paint()..filterQuality = FilterQuality.high;
      canvas.drawImageRect(image, src, dst, paint);
      _didDraw = true;
      _drawBitmapCount++;
      return;
    }

    if (!normalized.toLowerCase().endsWith('.xml')) {
      final genericBitmap = await _decodeBitmap(normalized);
      if (genericBitmap != null) {
        final src = Rect.fromLTWH(
          0,
          0,
          genericBitmap.width.toDouble(),
          genericBitmap.height.toDouble(),
        );
        final dst = _fitContain(src.size, rect);
        final paint = Paint()..filterQuality = FilterQuality.high;
        canvas.drawImageRect(genericBitmap, src, dst, paint);
        _didDraw = true;
        _drawBitmapCount++;
        return;
      }
      return;
    }
    final root = await _loadXmlRoot(normalized);
    if (root == null) return;
    await _renderXmlDrawableElement(canvas, rect, root, depth + 1);
  }

  Future<void> _renderXmlDrawableElement(
    Canvas canvas,
    Rect rect,
    xml.XmlElement root,
    int depth,
  ) async {
    final tag = root.name.local.toLowerCase();
    switch (tag) {
      case 'adaptive-icon':
      case 'monochrome':
        await _renderAdaptiveIcon(canvas, rect, root, depth + 1);
        return;
      case 'vector':
        await _renderVectorDrawable(canvas, rect, root, depth + 1);
        return;
      case 'layer-list':
        await _renderLayerList(canvas, rect, root, depth + 1);
        return;
      case 'inset':
        await _renderInsetDrawable(canvas, rect, root, depth + 1);
        return;
      case 'shape':
        await _renderShapeDrawable(canvas, rect, root, depth + 1);
        return;
      case 'bitmap':
        await _renderBitmapDrawable(canvas, rect, root, depth + 1);
        return;
      case 'selector':
        await _renderSelectorDrawable(canvas, rect, root, depth + 1);
        return;
      default:
        final drawable = _attr(root, 'drawable');
        if (drawable != null) {
          await _renderDrawable(canvas, rect, drawable, depth + 1);
          return;
        }
        final child = _firstElementChild(root);
        if (child != null) {
          await _renderXmlDrawableElement(canvas, rect, child, depth + 1);
        }
    }
  }

  Future<void> _renderAdaptiveIcon(
    Canvas canvas,
    Rect rect,
    xml.XmlElement root,
    int depth,
  ) async {
    final background = _findDirectChild(root, 'background');
    final foreground = _findDirectChild(root, 'foreground');
    final monochrome = _findDirectChild(root, 'monochrome');
    _debug(
        'adaptive-icon: bg=${_attr(background, 'drawable')} fg=${_attr(foreground, 'drawable')} mono=${_attr(monochrome, 'drawable')}');

    canvas.save();
    canvas.clipPath(_defaultAdaptiveMask(rect));

    // 绘制白色底色作为安全兜底：所有规范的自适应图标背景层都应不透明，
    // 但如果背景颜色资源解析失败（如混淆 APK 的颜色引用），
    // 避免出现透明/黑色背景。正常的背景层会覆盖此底色。
    canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));

    final scaleTarget = foreground ?? monochrome;
    final foregroundScale =
        await _resolveAdaptiveForegroundScale(scaleTarget, depth + 1);
    final foregroundRect = _scaleRectAroundCenter(rect, foregroundScale);

    if (background != null) {
      await _renderDrawableContainer(canvas, rect, background, depth + 1);
    }
    if (foreground != null) {
      await _renderDrawableContainer(
          canvas, foregroundRect, foreground, depth + 1);
    } else if (monochrome != null) {
      await _renderDrawableContainer(
          canvas, foregroundRect, monochrome, depth + 1);
    }
    canvas.restore();
  }

  Future<double> _resolveAdaptiveForegroundScale(
    xml.XmlElement? container,
    int depth,
  ) async {
    if (container == null || depth > _kMaxDepth) {
      return _kAdaptiveForegroundScaleBitmap;
    }
    final raw = (_attr(container, 'drawable')?.trim().isNotEmpty ?? false)
        ? _attr(container, 'drawable')!.trim()
        : _findDrawableLikeValue(container);
    if (raw == null || raw.isEmpty) {
      return _kAdaptiveForegroundScaleBitmap;
    }
    final resolved = await _resolveDrawableToPath(raw, depth + 1);
    if (resolved == null || resolved.isEmpty) {
      return _kAdaptiveForegroundScaleBitmap;
    }
    if (resolved.toLowerCase().endsWith('.xml')) {
      final root = await _loadXmlRoot(resolved);
      final tag = root?.name.local.toLowerCase();
      if (tag == 'vector') {
        return _kAdaptiveForegroundScaleVector;
      }
    }
    return _kAdaptiveForegroundScaleBitmap;
  }

  Future<String?> _resolveDrawableToPath(String value, int depth) async {
    if (depth > _kMaxDepth) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (_looksLikeZipPath(trimmed)) {
      return _normalizeZipPath(trimmed);
    }
    if (!trimmed.startsWith('@')) {
      return null;
    }
    return _resolveResourceReference(trimmed, depth + 1);
  }

  Future<void> _renderDrawableContainer(
    Canvas canvas,
    Rect rect,
    xml.XmlElement container,
    int depth,
  ) async {
    final drawable = _attr(container, 'drawable');
    if (drawable != null && drawable.isNotEmpty) {
      await _renderDrawable(canvas, rect, drawable, depth + 1);
      return;
    }

    final fallbackDrawable = _findDrawableLikeValue(container);
    if (fallbackDrawable != null) {
      await _renderDrawable(canvas, rect, fallbackDrawable, depth + 1);
      return;
    }

    final child = _firstElementChild(container);
    if (child != null) {
      await _renderXmlDrawableElement(canvas, rect, child, depth + 1);
    }
  }

  Future<void> _renderLayerList(
    Canvas canvas,
    Rect rect,
    xml.XmlElement root,
    int depth,
  ) async {
    for (final item
        in root.childElements.where((e) => e.name.local == 'item')) {
      final inset = _parseInsets(item);
      final inner = Rect.fromLTRB(
        rect.left + inset.left,
        rect.top + inset.top,
        rect.right - inset.right,
        rect.bottom - inset.bottom,
      );
      if (inner.isEmpty) continue;
      await _renderDrawableContainer(canvas, inner, item, depth + 1);
    }
  }

  Future<void> _renderInsetDrawable(
    Canvas canvas,
    Rect rect,
    xml.XmlElement root,
    int depth,
  ) async {
    final inset = _parseInsets(root);
    final inner = Rect.fromLTRB(
      rect.left + inset.left,
      rect.top + inset.top,
      rect.right - inset.right,
      rect.bottom - inset.bottom,
    );
    if (inner.isEmpty) return;
    await _renderDrawableContainer(canvas, inner, root, depth + 1);
  }

  Future<void> _renderBitmapDrawable(
    Canvas canvas,
    Rect rect,
    xml.XmlElement root,
    int depth,
  ) async {
    final source = _attr(root, 'src') ?? _attr(root, 'drawable');
    if (source == null || source.isEmpty) return;
    await _renderDrawable(canvas, rect, source, depth + 1);
  }

  Future<void> _renderSelectorDrawable(
    Canvas canvas,
    Rect rect,
    xml.XmlElement root,
    int depth,
  ) async {
    final item = _findDirectChild(root, 'item');
    if (item == null) return;
    await _renderDrawableContainer(canvas, rect, item, depth + 1);
  }

  Future<void> _renderShapeDrawable(
    Canvas canvas,
    Rect rect,
    xml.XmlElement root,
    int depth,
  ) async {
    final shapeType = (_attr(root, 'shape') ?? 'rectangle').toLowerCase();
    final solid = _findDirectChild(root, 'solid');
    final gradient = _findDirectChild(root, 'gradient');
    final stroke = _findDirectChild(root, 'stroke');
    final corners = _findDirectChild(root, 'corners');

    final fillColor = await _resolveColorRef(
      solid == null ? null : _attr(solid, 'color'),
      depth + 1,
    );
    final fillGradient = gradient == null
        ? null
        : await _buildGradientFromElement(gradient, rect, depth + 1);
    if (fillColor != null || fillGradient != null) {
      final fillPaint = Paint();
      if (fillGradient != null) {
        fillPaint.shader = fillGradient;
      } else {
        fillPaint.color = fillColor!;
      }
      if (shapeType == 'oval') {
        canvas.drawOval(rect, fillPaint);
        _didDraw = true;
        _drawFillCount++;
      } else {
        final radius = _parseDimension(_attr(corners, 'radius'));
        if (radius > 0) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(radius)),
            fillPaint,
          );
          _didDraw = true;
          _drawFillCount++;
        } else {
          canvas.drawRect(rect, fillPaint);
          _didDraw = true;
          _drawRectCount++;
        }
      }
    }

    if (stroke != null) {
      final strokeColor =
          await _resolveColorRef(_attr(stroke, 'color'), depth + 1);
      final strokeWidth = _parseDimension(_attr(stroke, 'width'));
      if (strokeColor != null && strokeWidth > 0) {
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..color = strokeColor;
        if (shapeType == 'oval') {
          canvas.drawOval(rect.deflate(strokeWidth / 2), paint);
          _didDraw = true;
          _drawStrokeCount++;
        } else {
          final radius = _parseDimension(_attr(corners, 'radius'));
          if (radius > 0) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                rect.deflate(strokeWidth / 2),
                Radius.circular(math.max(radius - strokeWidth / 2, 0)),
              ),
              paint,
            );
            _didDraw = true;
            _drawStrokeCount++;
          } else {
            canvas.drawRect(rect.deflate(strokeWidth / 2), paint);
            _didDraw = true;
            _drawStrokeCount++;
          }
        }
      }
    }
  }

  Future<void> _renderVectorDrawable(
    Canvas canvas,
    Rect rect,
    xml.XmlElement vector,
    int depth,
  ) async {
    final viewportWidth = _parseDimension(_attr(vector, 'viewportWidth'));
    final viewportHeight = _parseDimension(_attr(vector, 'viewportHeight'));
    final width = viewportWidth > 0
        ? viewportWidth
        : math.max(_parseDimension(_attr(vector, 'width')), 1);
    final height = viewportHeight > 0
        ? viewportHeight
        : math.max(_parseDimension(_attr(vector, 'height')), 1);
    final vw = viewportWidth > 0 ? viewportWidth : width;
    final vh = viewportHeight > 0 ? viewportHeight : height;
    if (vw <= 0 || vh <= 0) return;
    final vectorAlpha =
        _parseDimension(_attr(vector, 'alpha'), fallback: 1).clamp(0.0, 1.0);
    canvas.save();
    canvas.translate(rect.left, rect.top);
    canvas.scale(rect.width / vw, rect.height / vh);
    await _renderVectorChildren(
      canvas,
      vector.childElements,
      depth + 1,
      vectorAlpha,
    );
    canvas.restore();
  }

  Future<void> _renderVectorChildren(
    Canvas canvas,
    Iterable<xml.XmlElement> elements,
    int depth,
    double inheritedAlpha,
  ) async {
    for (final child in elements) {
      final tag = child.name.local.toLowerCase();
      if (tag == 'group') {
        await _renderVectorGroup(
          canvas,
          child,
          depth + 1,
          inheritedAlpha,
        );
      } else if (tag == 'path') {
        await _renderVectorPath(
          canvas,
          child,
          depth + 1,
          inheritedAlpha,
        );
      } else if (tag == 'clip-path') {
        final pathData = _attr(child, 'pathData');
        if (pathData == null || pathData.isEmpty) continue;
        try {
          final path = parseSvgPathData(pathData);
          canvas.clipPath(path);
        } catch (_) {
          // Ignore invalid clip paths.
        }
      }
    }
  }

  Future<void> _renderVectorGroup(
    Canvas canvas,
    xml.XmlElement group,
    int depth,
    double inheritedAlpha,
  ) async {
    final rotation = _parseDimension(_attr(group, 'rotation'));
    final pivotX = _parseDimension(_attr(group, 'pivotX'));
    final pivotY = _parseDimension(_attr(group, 'pivotY'));
    final scaleX = _parseDimension(_attr(group, 'scaleX'), fallback: 1);
    final scaleY = _parseDimension(_attr(group, 'scaleY'), fallback: 1);
    final translateX = _parseDimension(_attr(group, 'translateX'));
    final translateY = _parseDimension(_attr(group, 'translateY'));
    final groupAlpha =
        _parseDimension(_attr(group, 'alpha'), fallback: 1).clamp(0.0, 1.0);
    final combinedAlpha = (inheritedAlpha * groupAlpha).clamp(0.0, 1.0);
    canvas.save();
    canvas.translate(translateX, translateY);
    canvas.translate(pivotX, pivotY);
    canvas.rotate(rotation * math.pi / 180.0);
    canvas.scale(scaleX, scaleY);
    canvas.translate(-pivotX, -pivotY);
    await _renderVectorChildren(
      canvas,
      group.childElements,
      depth + 1,
      combinedAlpha,
    );
    canvas.restore();
  }

  Future<void> _renderVectorPath(
    Canvas canvas,
    xml.XmlElement element,
    int depth,
    double inheritedAlpha,
  ) async {
    final pathData = _attr(element, 'pathData');
    if (pathData == null || pathData.isEmpty) return;

    Path path;
    try {
      path = parseSvgPathData(pathData);
    } catch (_) {
      return;
    }

    final fillType = (_attr(element, 'fillType') ?? '').trim().toLowerCase();
    if (fillType == 'evenodd' || fillType == '1' || fillType == '0x1') {
      path.fillType = PathFillType.evenOdd;
    } else if (fillType == 'nonzero' || fillType == '0' || fillType == '0x0') {
      path.fillType = PathFillType.nonZero;
    }
    final trimStart = _parseDimension(_attr(element, 'trimPathStart'));
    final trimEnd = _parseDimension(_attr(element, 'trimPathEnd'), fallback: 1);
    final trimOffset = _parseDimension(_attr(element, 'trimPathOffset'));
    if ((trimStart - 0).abs() > 1e-6 ||
        (trimEnd - 1).abs() > 1e-6 ||
        trimOffset.abs() > 1e-6) {
      path = _applyTrimPath(path, trimStart, trimEnd, trimOffset);
    }
    _vectorPathTotal++;

    final fillRaw = _attr(element, 'fillColor');
    final fillAlpha =
        (_parseDimension(_attr(element, 'fillAlpha'), fallback: 1) *
                inheritedAlpha)
            .clamp(0.0, 1.0);
    final resolvedFill = await _resolveVectorFill(fillRaw, path, depth + 1);
    if (resolvedFill != null && fillAlpha > 0) {
      final paint = Paint()..style = PaintingStyle.fill;
      if (resolvedFill.color != null) {
        paint.color = _applyAlpha(resolvedFill.color!, fillAlpha);
      } else if (resolvedFill.shader != null) {
        paint.shader = resolvedFill.shader;
        if (fillAlpha < 1.0) {
          paint.colorFilter = ColorFilter.mode(
            Color.fromARGB(
                (fillAlpha * 255).round().clamp(0, 255), 255, 255, 255),
            BlendMode.modulate,
          );
        }
      }
      canvas.drawPath(path, paint);
      _didDraw = true;
      _drawFillCount++;
      _vectorPathFilled++;
    }

    final strokeColor = await _resolveColorRef(
      _attr(element, 'strokeColor'),
      depth + 1,
    );
    final strokeWidth = _parseDimension(_attr(element, 'strokeWidth'));
    final strokeAlpha =
        (_parseDimension(_attr(element, 'strokeAlpha'), fallback: 1) *
                inheritedAlpha)
            .clamp(0.0, 1.0);
    if (strokeColor != null && strokeWidth > 0 && strokeAlpha > 0) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = _applyAlpha(strokeColor, strokeAlpha);
      final cap = (_attr(element, 'strokeLineCap') ?? '').toLowerCase();
      if (cap == 'round') paint.strokeCap = StrokeCap.round;
      if (cap == 'square') paint.strokeCap = StrokeCap.square;
      final join = (_attr(element, 'strokeLineJoin') ?? '').toLowerCase();
      if (join == 'round') paint.strokeJoin = StrokeJoin.round;
      if (join == 'bevel') paint.strokeJoin = StrokeJoin.bevel;
      final miter = _parseDimension(_attr(element, 'strokeMiterLimit'));
      if (miter > 0) paint.strokeMiterLimit = miter;
      canvas.drawPath(path, paint);
      _didDraw = true;
      _drawStrokeCount++;
      _vectorPathStroked++;
    }
  }

  Future<_ResolvedVectorFill?> _resolveVectorFill(
    String? rawValue,
    Path path,
    int depth,
  ) async {
    if (rawValue == null || rawValue.isEmpty) return null;

    final trimmed = rawValue.trim();

    // 1. 直接解析颜色字面量（不需要递归，无视 depth 限制）
    if (_isColorLiteral(trimmed)) {
      final color = _parseColor(trimmed);
      if (color != null) {
        return _ResolvedVectorFill(color: color, debugLabel: 'color:$color');
      }
    }
    if (_isAndroidIntLiteral(trimmed)) {
      final color = _parseAndroidColorInt(trimmed);
      if (color != null) {
        return _ResolvedVectorFill(
            color: color, debugLabel: 'int-color:$color');
      }
    }

    // 2. 仅在需要递归解析资源引用时检查 depth
    if (depth > _kMaxDepth) return null;
    if (!trimmed.startsWith('@')) return null;

    // 3. 解析资源引用（只解析一次，避免 _resolveColorRef 内部再次重复解析）
    final resolved = await _resolveResourceReference(trimmed, depth + 1);
    if (resolved == null || resolved == trimmed) return null;

    // 4. 解析结果是 XML 文件：先尝试渐变，再尝试颜色
    if (resolved.toLowerCase().endsWith('.xml')) {
      final gradient = await _resolveGradientFromXml(
        resolved,
        path.getBounds(),
        depth + 1,
      );
      if (gradient != null) {
        return _ResolvedVectorFill(
          shader: gradient,
          debugLabel: 'gradient:$resolved',
        );
      }
      final xmlColor = await _resolveColorFromXml(resolved, depth + 1);
      if (xmlColor != null) {
        return _ResolvedVectorFill(
          color: xmlColor,
          debugLabel: 'xml-color:$resolved->$xmlColor',
        );
      }
    }

    // 5. 解析结果不是 XML 或 XML 解析失败：作为颜色值解析
    final finalColor = await _resolveColorRef(resolved, depth + 1);
    if (finalColor != null) {
      return _ResolvedVectorFill(
        color: finalColor,
        debugLabel: 'ref-color:$resolved->$finalColor',
      );
    }
    return null;
  }

  Future<Gradient?> _resolveGradientFromXml(
    String filePath,
    Rect pathBounds,
    int depth,
  ) async {
    if (depth > _kMaxDepth) return null;
    final root = await _loadXmlRoot(filePath);
    if (root == null) return null;
    if (root.name.local.toLowerCase() != 'gradient') return null;
    return _buildGradientFromElement(root, pathBounds, depth + 1);
  }

  Future<Gradient?> _buildGradientFromElement(
    xml.XmlElement root,
    Rect pathBounds,
    int depth,
  ) async {
    if (depth > _kMaxDepth) return null;
    final gradientType = (_attr(root, 'type') ?? 'linear').toLowerCase();
    final colors = <Color>[];
    final offsets = <double>[];

    for (final item
        in root.childElements.where((e) => e.name.local == 'item')) {
      final colorValue = _attr(item, 'color');
      final color = await _resolveColorRef(colorValue, depth + 1);
      if (color == null) {
        _debug(
            'gradient item color skipped: raw=$colorValue (unresolvable at depth=$depth)');
        continue;
      }
      colors.add(color);
      offsets.add(_parseDimension(_attr(item, 'offset')));
    }

    if (colors.isEmpty) {
      final startColor =
          await _resolveColorRef(_attr(root, 'startColor'), depth + 1);
      final centerColor =
          await _resolveColorRef(_attr(root, 'centerColor'), depth + 1);
      final endColor =
          await _resolveColorRef(_attr(root, 'endColor'), depth + 1);
      if (startColor != null && endColor != null) {
        colors.add(startColor);
        offsets.add(0);
        if (centerColor != null) {
          colors.add(centerColor);
          offsets.add(0.5);
        }
        colors.add(endColor);
        offsets.add(1);
      }
    }

    if (colors.length < 2) return null;
    final normalizedOffsets = _normalizeGradientStops(offsets, colors.length);
    final tileMode = _parseTileMode(_attr(root, 'tileMode'));

    final type = _parseGradientType(gradientType);
    if (type == _GradientType.radial) {
      final center = Offset(
        _parseDimension(_attr(root, 'centerX'),
            fallback: pathBounds.isEmpty ? 0 : pathBounds.center.dx),
        _parseDimension(_attr(root, 'centerY'),
            fallback: pathBounds.isEmpty ? 0 : pathBounds.center.dy),
      );
      final radius = _parseDimension(
        _attr(root, 'gradientRadius'),
        fallback: pathBounds.isEmpty
            ? 1
            : math.max(pathBounds.width, pathBounds.height) / 2,
      );
      return Gradient.radial(
        center,
        radius,
        colors,
        normalizedOffsets,
        tileMode,
      );
    }
    if (type == _GradientType.sweep) {
      final center = Offset(
        _parseDimension(_attr(root, 'centerX'),
            fallback: pathBounds.isEmpty ? 0 : pathBounds.center.dx),
        _parseDimension(_attr(root, 'centerY'),
            fallback: pathBounds.isEmpty ? 0 : pathBounds.center.dy),
      );
      return Gradient.sweep(
        center,
        colors,
        normalizedOffsets,
        tileMode,
      );
    }

    var start = Offset(
      _parseDimension(_attr(root, 'startX'),
          fallback: pathBounds.isEmpty ? 0 : pathBounds.left),
      _parseDimension(_attr(root, 'startY'),
          fallback: pathBounds.isEmpty ? 0 : pathBounds.top),
    );
    var end = Offset(
      _parseDimension(_attr(root, 'endX'),
          fallback: pathBounds.isEmpty ? 1 : pathBounds.right),
      _parseDimension(_attr(root, 'endY'),
          fallback: pathBounds.isEmpty ? 0 : pathBounds.bottom),
    );
    if ((start - end).distanceSquared == 0 && !pathBounds.isEmpty) {
      final angle = _parseDimension(_attr(root, 'angle'));
      final rad = angle * math.pi / 180.0;
      final half = math.max(pathBounds.width, pathBounds.height) * 0.5;
      final center = pathBounds.center;
      final dir = Offset(math.cos(rad), math.sin(rad));
      start = center - dir * half;
      end = center + dir * half;
    }
    return Gradient.linear(start, end, colors, normalizedOffsets, tileMode);
  }

  Future<Color?> _resolveColorRef(String? value, int depth) async {
    if (value == null || value.isEmpty) return null;
    final trimmed = value.trim();
    // 颜色字面量不需要递归解析，无视 depth 限制
    if (_isColorLiteral(trimmed)) {
      return _parseColor(trimmed);
    }
    if (_isAndroidIntLiteral(trimmed)) {
      final parsed = _parseAndroidColorInt(trimmed);
      return parsed;
    }

    // 仅在需要递归解析资源引用时检查 depth
    if (depth > _kMaxDepth) return null;
    if (!trimmed.startsWith('@')) return null;
    final resolved = await _resolveResourceReference(trimmed, depth + 1);
    if (resolved == null || resolved == trimmed) return null;
    if (resolved.toLowerCase().endsWith('.xml')) {
      final xmlColor = await _resolveColorFromXml(resolved, depth + 1);
      if (xmlColor != null) {
        return xmlColor;
      }
    }
    return _resolveColorRef(resolved, depth + 1);
  }

  Future<String?> _resolveResourceReference(String reference, int depth) async {
    if (depth > _kMaxDepth) return null;
    final trimmed = reference.trim();
    if (trimmed.isEmpty) return null;
    if (_isColorLiteral(trimmed) || _looksLikeZipPath(trimmed)) return trimmed;

    final table = await _loadResourceTable();
    if (table == null) return null;

    final idMatch = _kResourceIdPattern.firstMatch(trimmed);
    if (idMatch != null) {
      final id = _normalizeResourceId(idMatch.group(1)!);
      final entry = table.byId[id];
      final resolved = _resolveEntryValue(entry);
      final withFallback = resolved ?? _resolveFrameworkReference(id);
      _resolvedRefCount++;
      if (_resolvedRefCount <= 20) {
        _debug(
            'resolveRef: $trimmed -> $withFallback (${entry?.name})');
      }
      return withFallback;
    }

    final nameMatch = _kNamedResourcePattern.firstMatch(trimmed);
    if (nameMatch != null) {
      final nameKey =
          '${nameMatch.group(1)!.toLowerCase()}/${nameMatch.group(2)!.toLowerCase()}';
      final entries = table.byName[nameKey];
      if (entries == null || entries.isEmpty) return null;
      final picked = _pickBestEntry(entries);
      final resolved = _resolveEntryValue(picked);
      _resolvedRefCount++;
      if (_resolvedRefCount <= 20) {
        _debug(
            'resolveRef: $trimmed -> $resolved (${picked.name})');
      }
      return resolved;
    }
    return null;
  }

  String? _resolveEntryValue(_ResourceEntry? entry) {
    if (entry == null) return null;
    if (entry.filePaths.isNotEmpty) {
      return _pickBestFilePath(entry.filePaths);
    }
    if (entry.colors.isNotEmpty) {
      return entry.colors.first;
    }
    if (entry.references.isNotEmpty) {
      return entry.references.first;
    }
    // Fallback: 资源条目有名称但无数据时，按名称在 zip 中查找匹配文件
    if (entry.name.isNotEmpty) {
      final found = _findFileByResourceName(entry.name);
      if (found != null) {
        _debug('resolveEntryValue fallback: ${entry.name} -> $found');
        return found;
      }
    }
    return null;
  }

  /// 根据资源名（如 mipmap/ic_launcher_foreground）在 zip 文件列表中查找匹配的文件。
  /// 优先返回高密度位图，其次 XML。
  String? _findFileByResourceName(String resourceName) {
    // resourceName 格式: "type/name"，例如 "mipmap/ic_launcher_foreground"
    final parts = resourceName.split('/');
    if (parts.length != 2) return null;
    final type = parts[0].toLowerCase(); // e.g. "mipmap", "drawable"
    final name = parts[1].toLowerCase(); // e.g. "ic_launcher_foreground"

    _zipFiles ??= zip.listFiles();

    // 关联资源类型：mipmap <-> drawable 可互相搜索
    final relatedTypes = <String>{type};
    if (type == 'mipmap') relatedTypes.add('drawable');
    if (type == 'drawable') relatedTypes.add('mipmap');

    final candidates = <String>[];
    final broadCandidates = <String>[];

    for (final f in _zipFiles!) {
      final lower = f.toLowerCase();
      if (!lower.startsWith('res/')) continue;
      // 提取文件名（不含扩展名）
      final lastSlash = f.lastIndexOf('/');
      if (lastSlash < 0) continue;
      final fileName = f.substring(lastSlash + 1).toLowerCase();
      final dotIndex = fileName.lastIndexOf('.');
      final baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
      if (baseName != name) continue;

      // 检查目录是否与资源类型匹配
      final afterRes = lower.substring(4); // 去掉 "res/"
      bool matched = false;
      for (final t in relatedTypes) {
        if (afterRes.startsWith('$t-') || afterRes.startsWith('$t/')) {
          matched = true;
          break;
        }
      }
      if (matched) {
        candidates.add(f);
      } else {
        broadCandidates.add(f);
      }
    }

    // 优先使用精确匹配类型的候选
    final selected = candidates.isNotEmpty ? candidates : broadCandidates;
    if (selected.isEmpty) {
      _debug(
          'findFileByResourceName: no match for $resourceName (zipFiles=${_zipFiles!.length})');
      return null;
    }
    if (selected.length == 1) return selected.first;
    selected.sort((a, b) => _fileScore(b).compareTo(_fileScore(a)));
    _debug(
        'findFileByResourceName: $resourceName -> ${selected.first} (${selected.length} candidates)');
    return selected.first;
  }

  _ResourceEntry _pickBestEntry(List<_ResourceEntry> entries) {
    final sorted = [...entries];
    sorted.sort((a, b) => _entryScore(b).compareTo(_entryScore(a)));
    return sorted.first;
  }

  int _entryScore(_ResourceEntry entry) {
    if (entry.filePaths.isNotEmpty) {
      return _fileScore(_pickBestFilePath(entry.filePaths));
    }
    if (entry.colors.isNotEmpty) return 10;
    if (entry.references.isNotEmpty) return 5;
    return 0;
  }

  String _pickBestFilePath(List<String> filePaths) {
    final sorted = filePaths.toSet().toList();
    sorted.sort((a, b) => _fileScore(b).compareTo(_fileScore(a)));
    return sorted.first;
  }

  int _fileScore(String path) {
    final lower = path.toLowerCase();
    var score = 0;
    final hasExtension =
        lower.contains('.') && lower.lastIndexOf('/') < lower.lastIndexOf('.');
    final isXml = lower.endsWith('.xml');
    if (isXml) {
      score += 420;
    } else if (!isXml &&
        (lower.endsWith('.png') ||
            lower.endsWith('.webp') ||
            lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg'))) {
      score += 180;
    } else if (!isXml && !hasExtension) {
      score += 160;
    }
    if (lower.contains('anydpi-v26')) {
      score += isXml ? 20 : 160;
    } else if (lower.contains('anydpi')) {
      score += isXml ? 15 : 120;
    }
    final density = _kDensityPattern.firstMatch(lower)?.group(1);
    const densityScore = <String, int>{
      'xxxhdpi': 70,
      'xxhdpi': 65,
      'xhdpi': 60,
      'hdpi': 55,
      'mdpi': 50,
      'ldpi': 45,
    };
    if (density != null) score += densityScore[density] ?? 0;
    return score;
  }

  String? _resolveFrameworkReference(String id) {
    final normalized = _normalizeResourceId(id);
    if (!normalized.startsWith('0x01')) return null;
    return _kFrameworkColorFallback[normalized];
  }

  Future<_ResourceTable?> _loadResourceTable() async {
    if (_resourceTable != null) return _resourceTable;
    try {
      final result = await Process.run(
        aaptPath,
        ['dump', 'resources', apkPath],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 120));
      if (result.exitCode != 0) {
        log.warning('aapt2 dump resources failed: ${result.stderr}');
        return null;
      }
      _resourceTable = _parseResourceTable(result.stdout.toString());
      _debug(
          'resourceTable loaded: byId=${_resourceTable!.byId.length}, byName=${_resourceTable!.byName.length}');
      return _resourceTable;
    } catch (e) {
      log.warning('loadResourceTable failed: $e');
      return null;
    }
  }

  _ResourceTable _parseResourceTable(String output) {
    final byId = <String, _ResourceEntry>{};
    final byName = <String, List<_ResourceEntry>>{};
    _ResourceEntry? current;
    List<String>? currentRawLines;
    final emptyEntryRawLines = <String, List<String>>{};

    for (final rawLine in output.split('\n')) {
      final line = rawLine.trimRight();
      final resourceMatch = _kResourceLinePattern.firstMatch(line);
      if (resourceMatch != null) {
        // 保存上一个条目的原始行（仅当条目为空且类型为 mipmap/drawable 时）
        if (current != null &&
            currentRawLines != null &&
            current.filePaths.isEmpty &&
            current.colors.isEmpty &&
            current.references.isEmpty) {
          final name = current.name;
          if (name.startsWith('mipmap/') || name.startsWith('drawable/')) {
            emptyEntryRawLines[current.id] = currentRawLines;
          }
        }
        final id = _normalizeResourceId(resourceMatch.group(1)!);
        final name = resourceMatch.group(2)!.trim().toLowerCase();
        current =
            byId.putIfAbsent(id, () => _ResourceEntry(id: id, name: name));
        current.name = name;
        currentRawLines = [];
        final list = byName.putIfAbsent(name, () => []);
        if (!list.contains(current)) list.add(current);
        continue;
      }
      if (current == null) continue;
      currentRawLines?.add(line);

      for (final m in _kResourceFilePattern.allMatches(line)) {
        current.filePaths.add(_normalizeZipPath(m.group(1)!));
      }
      if (current.filePaths.isEmpty) {
        for (final m in _kResourceFileNoMarkerPattern.allMatches(line)) {
          current.filePaths.add(_normalizeZipPath(m.group(1)!));
        }
      }
      // Fallback: 混淆 APK 可能输出裸文件名（如 uF.xml 或 "AndroidManifest.xml/0y.png"）
      if (current.filePaths.isEmpty) {
        for (var token in line.trim().split(RegExp(r'\s+'))) {
          // 去除 aapt2 输出中的包裹引号
          if (token.length >= 2 &&
              token.startsWith('"') &&
              token.endsWith('"')) {
            token = token.substring(1, token.length - 1);
          }
          final lower = token.toLowerCase();
          if ((lower.endsWith('.xml') ||
                  lower.endsWith('.png') ||
                  lower.endsWith('.webp') ||
                  lower.endsWith('.jpg') ||
                  lower.endsWith('.jpeg')) &&
              !token.contains('=') &&
              !token.startsWith('#') &&
              !token.startsWith('(') &&
              !token.startsWith('0x')) {
            current.filePaths.add(_normalizeZipPath(token));
          }
        }
      }
      for (final m in _kResourceColorPattern.allMatches(line)) {
        current.colors.add(m.group(0)!.toLowerCase());
      }
      for (final m in _kResourceRefPattern.allMatches(line)) {
        final raw = m.group(1)!;
        if (raw.toLowerCase().startsWith('0x')) {
          current.references.add('@${_normalizeResourceId(raw)}');
        } else {
          current.references.add('@${raw.toLowerCase()}');
        }
      }
    }

    // 保存最后一个条目的原始行
    if (current != null &&
        currentRawLines != null &&
        current.filePaths.isEmpty &&
        current.colors.isEmpty &&
        current.references.isEmpty) {
      final name = current.name;
      if (name.startsWith('mipmap/') || name.startsWith('drawable/')) {
        emptyEntryRawLines[current.id] = currentRawLines;
      }
    }

    for (final entry in byId.values) {
      entry.filePaths = entry.filePaths.toSet().toList();
      entry.colors = entry.colors.toSet().toList();
      entry.references = entry.references.toSet().toList();
    }

    // 输出空的 mipmap/drawable 条目的原始 aapt2 行，辅助调试
    for (final e in emptyEntryRawLines.entries) {
      final entry = byId[e.key];
      if (entry != null) {
        log.finer(
            'AdaptiveIconRenderer: emptyResourceEntry: ${entry.id} ${entry.name} rawLines=${e.value.length} content=${e.value.take(5).map((l) => l.trim()).join(" | ")}');
      }
    }

    return _ResourceTable(byId: byId, byName: byName);
  }

  Future<Image?> _decodeBitmap(String path) async {
    final normalized = _normalizeZipPath(path);
    if (_bitmapCache.containsKey(normalized)) return _bitmapCache[normalized];
    if (_failedBitmapPath.contains(normalized)) return null;

    final bytes = await _readZipFile(normalized);
    if (bytes == null || bytes.isEmpty) {
      _failedBitmapPath.add(normalized);
      return null;
    }

    try {
      final codec = await instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      _bitmapCache[normalized] = frame.image;
      return frame.image;
    } catch (e) {
      _failedBitmapPath.add(normalized);
      log.fine('decodeBitmap failed: $normalized, $e');
      return null;
    }
  }

  Future<xml.XmlElement?> _loadXmlRoot(String filePath) async {
    final bytes = await _readZipFile(filePath);
    if (bytes == null || bytes.isEmpty) return null;

    try {
      final xmlText = _decodeXmlText(bytes);
      final doc = xml.XmlDocument.parse(xmlText);
      return doc.rootElement;
    } catch (e) {
      final preview =
          utf8.decode(bytes.take(120).toList(), allowMalformed: true);
      log.fine(
          'loadXmlRoot failed: $filePath, $e, preview=${preview.replaceAll('\n', '\\n')}');
      return null;
    }
  }

  String _decodeXmlText(Uint8List bytes) {
    if (_looksLikeBinaryXml(bytes)) {
      try {
        return _binaryXmlDecompressor.decompressXml(bytes);
      } catch (_) {
        // Fall back to plain UTF-8 xml parsing for non-standard encodings.
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<Color?> _resolveColorFromXml(String filePath, int depth) async {
    if (depth > _kMaxDepth) return null;
    final root = await _loadXmlRoot(filePath);
    if (root == null) return null;
    final tag = root.name.local.toLowerCase();
    if (tag == 'selector') {
      final item = _findDirectChild(root, 'item');
      final colorAttr = item == null ? null : _attr(item, 'color');
      if (colorAttr == null || colorAttr.isEmpty) return null;
      return _resolveColorRef(colorAttr, depth + 1);
    }
    if (tag == 'color') {
      final text = root.innerText.trim();
      if (_isColorLiteral(text)) {
        return _parseColor(text);
      }
    }
    // <shape> 的 <solid> 子元素可以定义纯色
    if (tag == 'shape') {
      final solid = _findDirectChild(root, 'solid');
      if (solid != null) {
        final colorAttr = _attr(solid, 'color');
        if (colorAttr != null) {
          return _resolveColorRef(colorAttr, depth + 1);
        }
      }
    }
    return null;
  }

  /// 从容器元素的内联子元素中提取颜色。
  /// 支持 `<color>`, `<shape>` 等内联定义。
  Future<Color?> _resolveContainerColor(
      xml.XmlElement container, int depth) async {
    if (depth > _kMaxDepth) return null;
    for (final child in container.childElements) {
      final tag = child.name.local.toLowerCase();
      if (tag == 'color') {
        final colorAttr = _attr(child, 'color');
        if (colorAttr != null) {
          return _resolveColorRef(colorAttr, depth + 1);
        }
        final text = child.innerText.trim();
        if (text.isNotEmpty) {
          return _resolveColorRef(text, depth + 1);
        }
      } else if (tag == 'shape') {
        final solid = _findDirectChild(child, 'solid');
        if (solid != null) {
          final colorAttr = _attr(solid, 'color');
          if (colorAttr != null) {
            return _resolveColorRef(colorAttr, depth + 1);
          }
        }
      }
    }
    return null;
  }

  _GradientType _parseGradientType(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == '1' || value == 'radial') {
      return _GradientType.radial;
    }
    if (value == '2' || value == 'sweep') {
      return _GradientType.sweep;
    }
    return _GradientType.linear;
  }

  List<double>? _normalizeGradientStops(List<double> offsets, int colorCount) {
    if (colorCount < 2) return null;
    if (offsets.length != colorCount) {
      return null;
    }
    final result = <double>[];
    var needAuto = false;
    for (final value in offsets) {
      if (value.isNaN || value < 0 || value > 1) {
        needAuto = true;
        break;
      }
    }
    if (needAuto) {
      return null;
    }
    var last = -1.0;
    for (final value in offsets) {
      final clamped = value.clamp(0.0, 1.0);
      if (clamped < last) {
        needAuto = true;
        break;
      }
      result.add(clamped);
      last = clamped;
    }
    if (needAuto) {
      return null;
    }
    return result;
  }

  TileMode _parseTileMode(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value == '1' || value == 'repeat') {
      return TileMode.repeated;
    }
    if (value == '2' || value == 'mirror') {
      return TileMode.mirror;
    }
    if (value == '3' || value == 'decal') {
      return TileMode.decal;
    }
    return TileMode.clamp;
  }

  Path _applyTrimPath(
    Path original,
    double trimStart,
    double trimEnd,
    double trimOffset,
  ) {
    if (original.computeMetrics().isEmpty) return original;
    var start = trimStart + trimOffset;
    var end = trimEnd + trimOffset;
    start = start - start.floorToDouble();
    end = end - end.floorToDouble();

    final metrics = original.computeMetrics().toList();
    if (metrics.isEmpty) return original;
    final result = Path();

    void extractRange(PathMetric metric, double from, double to) {
      final total = metric.length;
      if (total <= 0) return;
      final clampedFrom = (from * total).clamp(0.0, total);
      final clampedTo = (to * total).clamp(0.0, total);
      if (clampedTo <= clampedFrom) return;
      result.addPath(
        metric.extractPath(clampedFrom, clampedTo, startWithMoveTo: true),
        Offset.zero,
      );
    }

    for (final metric in metrics) {
      if ((start - end).abs() <= 1e-6) {
        continue;
      }
      if (start < end) {
        extractRange(metric, start, end);
      } else {
        extractRange(metric, start, 1);
        extractRange(metric, 0, end);
      }
    }

    return result;
  }

  bool _looksLikeBinaryXml(Uint8List bytes) {
    if (bytes.length < 4) return false;
    final marker =
        bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
    return marker == BinaryXmlDecompressor.PACKED_XML_IDENTIFIER;
  }

  Future<Uint8List?> _readZipFile(String path) async {
    final normalized = _normalizeZipPath(path);
    if (normalized.isEmpty) return null;

    final candidates = <String>{
      normalized,
      normalized.replaceFirst(RegExp(r'^/'), ''),
      normalized.startsWith('res/')
          ? normalized.substring(4)
          : 'res/$normalized',
    };

    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      final data = await zip.readFileContent(candidate);
      if (data != null && data.isNotEmpty) return data;
    }

    final lowerMap = _getZipFileLowerMap();
    final match = lowerMap[normalized.toLowerCase()];
    if (match != null) {
      return zip.readFileContent(match);
    }
    return null;
  }

  Map<String, String> _getZipFileLowerMap() {
    if (_zipFileLowerMap == null) {
      _zipFiles ??= zip.listFiles();
      _zipFileLowerMap = {};
      for (final f in _zipFiles!) {
        // 保留第一个匹配，避免同名不同大小写的文件覆盖
        _zipFileLowerMap!.putIfAbsent(f.toLowerCase(), () => f);
      }
    }
    return _zipFileLowerMap!;
  }

  String _normalizeZipPath(String value) {
    var normalized = value.trim().replaceAll('\\', '/');
    // 去除混淆 APK 中 aapt2 输出的包裹引号
    if (normalized.length >= 2 &&
        normalized.startsWith('"') &&
        normalized.endsWith('"')) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    if (normalized.startsWith('file://')) {
      normalized = normalized.substring('file://'.length);
    }
    if (normalized.startsWith('/')) normalized = normalized.substring(1);
    return normalized;
  }

  String _normalizeResourceId(String value) {
    var tmp = value.trim().toLowerCase();
    if (tmp.startsWith('@')) {
      tmp = tmp.substring(1);
    }
    if (tmp.startsWith('res/')) {
      tmp = tmp.substring(4);
    }
    if (!tmp.startsWith('0x')) {
      tmp = '0x$tmp';
    }
    final parsed = int.tryParse(tmp.substring(2), radix: 16);
    if (parsed == null) {
      return tmp;
    }
    return '0x${parsed.toRadixString(16).padLeft(8, '0')}';
  }

  bool _looksLikeZipPath(String value) {
    final lower = value.toLowerCase();
    return lower.startsWith('res/') ||
        lower.endsWith('.xml') ||
        _isBitmapPath(lower);
  }

  bool _isBitmapPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg');
  }

  bool _isColorLiteral(String value) =>
      _kHexColorPattern.hasMatch(value.trim());

  bool _isAndroidIntLiteral(String value) =>
      _kAndroidIntLiteralPattern.hasMatch(value.trim());

  Color? _parseColor(String raw) {
    final value = raw.trim();
    if (!_kHexColorPattern.hasMatch(value)) return null;
    final hex = value.substring(1);
    int a = 255;
    int r = 0;
    int g = 0;
    int b = 0;

    if (hex.length == 3) {
      r = _hexToByte('${hex[0]}${hex[0]}');
      g = _hexToByte('${hex[1]}${hex[1]}');
      b = _hexToByte('${hex[2]}${hex[2]}');
    } else if (hex.length == 4) {
      a = _hexToByte('${hex[0]}${hex[0]}');
      r = _hexToByte('${hex[1]}${hex[1]}');
      g = _hexToByte('${hex[2]}${hex[2]}');
      b = _hexToByte('${hex[3]}${hex[3]}');
    } else if (hex.length == 6) {
      r = _hexToByte(hex.substring(0, 2));
      g = _hexToByte(hex.substring(2, 4));
      b = _hexToByte(hex.substring(4, 6));
    } else if (hex.length == 8) {
      a = _hexToByte(hex.substring(0, 2));
      r = _hexToByte(hex.substring(2, 4));
      g = _hexToByte(hex.substring(4, 6));
      b = _hexToByte(hex.substring(6, 8));
    }

    return Color.fromARGB(a, r, g, b);
  }

  int _hexToByte(String hex) {
    return int.tryParse(hex, radix: 16) ?? 0;
  }

  Color? _parseAndroidColorInt(String raw) {
    final signed = _parseAndroidIntLiteral(raw.trim());
    if (signed == null) return null;

    var color = signed & 0xffffffff;
    // 仅在非零 RGB 且 alpha 为 0 时补充 alpha（如 0x00FF00 → 0xFF00FF00）。
    // 值为 0x00000000 时保持透明，不添加 alpha。
    if ((color & 0xff000000) == 0 && color > 0 && color <= 0x00ffffff) {
      color |= 0xff000000;
    }
    return Color.fromARGB(
      (color >> 24) & 0xff,
      (color >> 16) & 0xff,
      (color >> 8) & 0xff,
      color & 0xff,
    );
  }

  int? _parseAndroidIntLiteral(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.startsWith('0x-')) {
      final body = value.substring(3);
      final parsed = int.tryParse(body, radix: 16);
      if (parsed == null) return null;
      return -parsed;
    }
    if (value.startsWith('-0x')) {
      final body = value.substring(3);
      final parsed = int.tryParse(body, radix: 16);
      if (parsed == null) return null;
      return -parsed;
    }
    if (value.startsWith('0x')) {
      return int.tryParse(value.substring(2), radix: 16);
    }
    return int.tryParse(value);
  }

  Color _applyAlpha(Color color, double alpha) {
    final effective = ((color.a * 255.0) * alpha).round().clamp(0, 255);
    return color.withAlpha(effective);
  }

  Rect _fitContain(Size source, Rect target) {
    if (source.width <= 0 || source.height <= 0 || target.isEmpty) {
      return target;
    }
    final scale =
        math.min(target.width / source.width, target.height / source.height);
    final width = source.width * scale;
    final height = source.height * scale;
    final dx = target.left + (target.width - width) / 2;
    final dy = target.top + (target.height - height) / 2;
    return Rect.fromLTWH(dx, dy, width, height);
  }

  Rect _scaleRectAroundCenter(Rect rect, double scale) {
    if (scale == 1 || rect.isEmpty) return rect;
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final width = rect.width * scale;
    final height = rect.height * scale;
    return Rect.fromCenter(
        center: Offset(cx, cy), width: width, height: height);
  }

  Path _defaultAdaptiveMask(Rect rect) {
    final size = math.min(rect.width, rect.height);
    final radius = size * 0.22;
    return Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      );
  }

  double _parseDimension(String? raw, {double fallback = 0}) {
    if (raw == null || raw.isEmpty) return fallback;
    final trimmed = raw.trim();
    final direct = double.tryParse(trimmed);
    if (direct != null && direct.isFinite) {
      return direct;
    }
    final match = _kLeadingNumberPattern.firstMatch(trimmed);
    if (match == null) return fallback;
    final result = double.tryParse(match.group(0)!);
    if (result == null || result.isNaN || !result.isFinite) return fallback;
    return result;
  }

  _Insets _parseInsets(xml.XmlElement? element) {
    if (element == null) return _Insets.zero();
    final inset = _parseDimension(_attr(element, 'inset'));
    final left = _parseDimension(_attr(element, 'insetLeft'), fallback: inset);
    final top = _parseDimension(_attr(element, 'insetTop'), fallback: inset);
    final right =
        _parseDimension(_attr(element, 'insetRight'), fallback: inset);
    final bottom =
        _parseDimension(_attr(element, 'insetBottom'), fallback: inset);
    return _Insets(left: left, top: top, right: right, bottom: bottom);
  }

  String? _attr(xml.XmlElement? element, String localName) {
    if (element == null) return null;
    for (final attribute in element.attributes) {
      if (attribute.name.local == localName) {
        return attribute.value;
      }
    }
    return null;
  }

  xml.XmlElement? _findDirectChild(xml.XmlElement element, String name) {
    for (final child in element.childElements) {
      if (child.name.local.toLowerCase() == name.toLowerCase()) {
        return child;
      }
    }
    return null;
  }

  xml.XmlElement? _firstElementChild(xml.XmlElement element) {
    final iterator = element.childElements.iterator;
    if (iterator.moveNext()) return iterator.current;
    return null;
  }

  String? _findDrawableLikeValue(xml.XmlElement element) {
    for (final attribute in element.attributes) {
      final value = attribute.value.trim();
      if (value.isEmpty) continue;
      if (value.startsWith('@') ||
          _looksLikeZipPath(value) ||
          _isColorLiteral(value) ||
          _isAndroidIntLiteral(value)) {
        return value;
      }
    }
    final text = element.innerText.trim();
    if (text.isNotEmpty &&
        (text.startsWith('@') ||
            _looksLikeZipPath(text) ||
            _isColorLiteral(text) ||
            _isAndroidIntLiteral(text))) {
      return text;
    }
    return null;
  }

  void _debug(String message) {
    log.fine('AdaptiveIconRenderer: $message');
  }
}

enum _GradientType { linear, radial, sweep }

class _ResolvedVectorFill {
  const _ResolvedVectorFill({
    this.color,
    this.shader,
    required this.debugLabel,
  });

  final Color? color;
  final Shader? shader;
  final String debugLabel;
}

class _ResourceTable {
  _ResourceTable({
    required this.byId,
    required this.byName,
  });

  final Map<String, _ResourceEntry> byId;
  final Map<String, List<_ResourceEntry>> byName;
}

class _ResourceEntry {
  _ResourceEntry({
    required this.id,
    required this.name,
  });

  final String id;
  String name;
  List<String> filePaths = [];
  List<String> colors = [];
  List<String> references = [];
}

class _Insets {
  _Insets({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  factory _Insets.zero() => _Insets(left: 0, top: 0, right: 0, bottom: 0);
}
