import 'package:apk_info_tool/config.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ui_config_provider.freezed.dart';
part 'ui_config_provider.g.dart';

@freezed
abstract class UiConfig with _$UiConfig {
  const factory UiConfig({
    required int textMaxLines,
    required double titleWidth,
  }) = _UiConfig;
}

@riverpod
class UiConfigState extends _$UiConfigState {
  @override
  UiConfig build() {
    return UiConfig(
      textMaxLines: Config.maxLines.value,
      titleWidth: Config.titleWidth.value,
    );
  }

  void updateTitleWidth(double value) {
    state = state.copyWith(titleWidth: value);
    Config.titleWidth.updateValue(value);
  }

  void updateTextMaxLines(int value) {
    state = state.copyWith(textMaxLines: value);
    Config.maxLines.updateValue(value);
  }
}
