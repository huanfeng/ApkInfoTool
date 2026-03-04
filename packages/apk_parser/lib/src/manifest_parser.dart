import 'dart:typed_data';
import 'binary_xml.dart';
import 'models.dart';

class ManifestParser {
  static ApkMeta parse(Uint8List manifestBytes) {
    final decompressor = BinaryXmlDecompressor();
    final doc = decompressor.decompressToDocument(manifestBytes);
    final meta = ApkMeta();

    final manifest = _findElement(doc, 'manifest');
    if (manifest == null) return meta;

    meta.packageName = manifest.attributes['package'];
    meta.versionCode = _parseInt(manifest.attributes['versionCode']);
    meta.versionName = manifest.attributes['versionName'];

    // 混淆 APK 可能无法通过属性名找到 package，
    // 启发式查找：在 manifest 属性中寻找类似包名的字符串值
    if (meta.packageName == null) {
      meta.packageName = _guessPackageName(manifest);
    }
    // 混淆 APK: versionName 可能被藏匿在 ns 字段中
    if (meta.versionName == null) {
      meta.versionName = _guessVersionName(manifest);
    }

    meta.compileSdkVersion =
        _parseInt(manifest.attributes['compileSdkVersion']);
    meta.compileSdkVersionCodename =
        manifest.attributes['compileSdkVersionCodename'];
    meta.platformBuildVersionName =
        manifest.attributes['platformBuildVersionName'];
    meta.platformBuildVersionCode =
        _parseInt(manifest.attributes['platformBuildVersionCode']);

    // <uses-sdk>
    final usesSdk = _findElement(manifest, 'uses-sdk');
    if (usesSdk != null) {
      meta.minSdkVersion = _parseInt(usesSdk.attributes['minSdkVersion']);
      meta.targetSdkVersion =
          _parseInt(usesSdk.attributes['targetSdkVersion']);
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
      // 属性名映射：binary XML 中是 smallScreens 等，aapt2 格式是 small 等
      const screenNameMap = {
        'smallScreens': 'small',
        'normalScreens': 'normal',
        'largeScreens': 'large',
        'xlargeScreens': 'xlarge',
        'anyDensity': 'anyDensity',
        'resizeable': 'resizeable',
      };
      for (final attr in screens.attributes.entries) {
        if (attr.value == 'true') {
          final mapped = screenNameMap[attr.key];
          meta.screenSizes.add(mapped ?? attr.key);
        }
      }
    }
    // 没有解析到任何 screen 属性时（元素不存在或属性被混淆），
    // targetSdkVersion >= 4 默认支持所有屏幕尺寸
    if (meta.screenSizes.isEmpty && (meta.targetSdkVersion ?? 0) >= 4) {
      meta.screenSizes = ['small', 'normal', 'large', 'xlarge'];
    }

    // <application>
    final application = _findElement(manifest, 'application');
    if (application != null) {
      meta.applicationName = application.attributes['name'];
      meta.label = application.attributes['label'];
      meta.applicationIcon = application.attributes['icon'];

      // 混淆 APK: name/label 可能无法通过标准属性名找到
      if (meta.applicationName == null) {
        meta.applicationName = _guessClassName(application);
      }

      for (final activity in application.children) {
        if (activity.name != 'activity' &&
            activity.name != 'activity-alias') {
          continue;
        }
        if (_isLaunchableActivity(activity)) {
          String? activityName = activity.attributes['name'];
          // 混淆 APK: activity name 可能在非标准属性中
          if (activityName == null) {
            activityName = _guessClassName(activity);
          }
          meta.launchableActivities.add(ActivityInfo(
            name: activityName,
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
            filterChild.attributes['name'] ==
                'android.intent.action.MAIN') {
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

  // ========== 混淆 APK 启发式查找方法 ==========

  /// 启发式包名查找：在属性值中寻找符合 Java 包名格式的最短匹配
  static final _packageNamePattern =
      RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$');

  static String? _guessPackageName(XmlElement manifest) {
    String? shortest;
    for (final value in manifest.attributes.values) {
      if (_isPackageNameCandidate(value)) {
        if (shortest == null || value.length < shortest.length) {
          shortest = value;
        }
      }
    }
    return shortest;
  }

  static bool _isPackageNameCandidate(String value) {
    return value.contains('.') &&
        !value.startsWith('@') &&
        !value.startsWith('http') &&
        !value.contains(' ') &&
        _packageNamePattern.hasMatch(value);
  }

  /// 启发式版本名查找：在属性值和 extraStrings 中寻找版本号模式
  static final _versionPattern = RegExp(r'^\d+\.\d+(\.\d+)*([.\-_a-zA-Z0-9]*)$');

  static String? _guessVersionName(XmlElement manifest) {
    // 先搜索属性值
    for (final value in manifest.attributes.values) {
      if (_versionPattern.hasMatch(value)) return value;
    }
    // 搜索混淆属性中恢复的额外字符串
    for (final str in manifest.extraStrings) {
      if (_versionPattern.hasMatch(str)) return str;
    }
    return null;
  }

  /// 启发式类名查找：在属性值中寻找完全限定类名或以点开头的类名
  /// 如 "com.example.MainActivity" 或 ".MainActivity"
  static String? _guessClassName(XmlElement element) {
    for (final value in element.attributes.values) {
      if (value.contains('.') &&
          !value.startsWith('@') &&
          !value.startsWith('http') &&
          !value.contains(' ') &&
          _packageNamePattern.hasMatch(value)) {
        return value;
      }
    }
    return null;
  }
}
