import 'package:apk_info_tool/config.dart';
import 'package:apk_info_tool/gen/strings.g.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'setting_provider.freezed.dart';
part 'setting_provider.g.dart';

@freezed
class Settings with _$Settings {
  factory Settings({
    required String aapt2Path,
    required String apksignerPath,
    required String adbPath,
    required bool enableSignature,
    required bool enableDebug,
    required String language,
  }) = _Settings;
}

@Riverpod(keepAlive: true)
class SettingState extends _$SettingState {
  @override
  Settings build() => Settings(
        aapt2Path: Config.aapt2Path.value,
        apksignerPath: Config.apksignerPath.value,
        adbPath: Config.adbPath.value,
        enableSignature: Config.enableSignature.value,
        enableDebug: Config.enableDebug.value,
        language: Config.language.value,
      );

  void setAapt2Path(String value) {
    state = state.copyWith(aapt2Path: value);
    Config.aapt2Path.updateValue(value);
  }

  void setApksignerPath(String value) {
    state = state.copyWith(apksignerPath: value);
    Config.apksignerPath.updateValue(value);
  }

  void setAdbPath(String value) {
    state = state.copyWith(adbPath: value);
    Config.adbPath.updateValue(value);
  }

  void setEnableSignature(bool value) {
    state = state.copyWith(enableSignature: value);
    Config.enableSignature.updateValue(value);
  }

  void setEnableDebug(bool value) {
    state = state.copyWith(enableDebug: value);
    Config.enableDebug.updateValue(value);
  }

  void setLanguage(String value) {
    state = state.copyWith(language: value);
    Config.language.updateValue(value);
    if (value.isEmpty || value == Config.kLanguageAuto) {
      LocaleSettings.useDeviceLocale();
    } else {
      LocaleSettings.setLocaleRaw(value);
    }
  }
}
