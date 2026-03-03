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

/// 资源表条目信息（用于将 ArscParser 数据导出给图标渲染器等外部使用）
class ResourceInfo {
  final int resourceId;
  final String typeName;
  final String keyName;
  final List<String> filePaths;
  final List<int> references;

  ResourceInfo({
    required this.resourceId,
    required this.typeName,
    required this.keyName,
    List<String>? filePaths,
    List<int>? references,
  })  : filePaths = filePaths ?? [],
        references = references ?? [];

  String get name => '$typeName/$keyName';

  String get idHex =>
      '0x${resourceId.toRadixString(16).padLeft(8, '0')}';
}

class ActivityInfo {
  String? name;
  String? label;
  String? icon;

  ActivityInfo({this.name, this.label, this.icon});

  @override
  String toString() => 'ActivityInfo{name: $name, label: $label, icon: $icon}';
}
