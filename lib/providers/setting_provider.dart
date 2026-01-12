import 'package:apk_info_tool/config.dart';
import 'package:apk_info_tool/gen/strings.g.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'setting_provider.freezed.dart';
part 'setting_provider.g.dart';

@freezed
abstract class Settings with _$Settings {
  factory Settings({
    required String aapt2Path,
    required String apksignerPath,
    required String adbPath,
    required String aapt2Source,
    required String apksignerSource,
    required String adbSource,
    required String downloadDir,
    required bool enableSignature,
    required bool enableHash,
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
        aapt2Source: Config.aapt2Source.value,
        apksignerSource: Config.apksignerSource.value,
        adbSource: Config.adbSource.value,
        downloadDir: Config.downloadDir.value,
        enableSignature: Config.enableSignature.value,
        enableHash: Config.enableHash.value,
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

  void setAapt2Source(String value) {
    state = state.copyWith(aapt2Source: value);
    Config.aapt2Source.updateValue(value);
  }

  void setApksignerSource(String value) {
    state = state.copyWith(apksignerSource: value);
    Config.apksignerSource.updateValue(value);
  }

  void setAdbSource(String value) {
    state = state.copyWith(adbSource: value);
    Config.adbSource.updateValue(value);
  }

  void setDownloadDir(String value) {
    state = state.copyWith(downloadDir: value);
    Config.downloadDir.updateValue(value);
  }

  void setEnableSignature(bool value) {
    state = state.copyWith(enableSignature: value);
    Config.enableSignature.updateValue(value);
  }

  void setEnableHash(bool value) {
    state = state.copyWith(enableHash: value);
    Config.enableHash.updateValue(value);
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
