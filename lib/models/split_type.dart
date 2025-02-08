import 'package:apk_info_tool/gen/strings.g.dart';

enum SplitType {
  base,
  language,
  abi,
  density,
  unknown;

  static SplitType fromId(String id) {
    if (id == 'base') return SplitType.base;
    if (id.contains('hdpi')) return SplitType.density;
    if (id.contains('v7a') || id.contains('v8a') || id.contains('x86')) {
      return SplitType.abi;
    }
    if (id.length == 2 || id.contains('config.') && id.length <= 5) {
      return SplitType.language;
    }
    return SplitType.unknown;
  }

  String getDisplayText(Translations t) {
    switch (this) {
      case SplitType.base:
        return t.install.split_type.base;
      case SplitType.language:
        return t.install.split_type.language;
      case SplitType.abi:
        return t.install.split_type.abi;
      case SplitType.density:
        return t.install.split_type.density;
      case SplitType.unknown:
        return t.install.split_type.unknown;
    }
  }
}
