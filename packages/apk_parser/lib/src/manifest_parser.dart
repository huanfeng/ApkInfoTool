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

      for (final activity in application.children) {
        if (activity.name != 'activity' &&
            activity.name != 'activity-alias') {
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
}
