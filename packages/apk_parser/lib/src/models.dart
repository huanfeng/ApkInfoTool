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
