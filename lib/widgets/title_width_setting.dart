import 'package:apk_info_tool/gen/strings.g.dart';
import 'package:apk_info_tool/providers/ui_config_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CurrentTitleWidth extends Notifier<double> {
  @override
  double build() {
    return ref.read(uiConfigStateProvider.select((value) => value.titleWidth));
  }

  void setWidth(double value) {
    state = value;
  }
}

final currentTitleWidthProvider =
    NotifierProvider<CurrentTitleWidth, double>(CurrentTitleWidth.new);

class TitleWidthSetting extends ConsumerStatefulWidget {
  const TitleWidthSetting({super.key});

  @override
  ConsumerState<TitleWidthSetting> createState() => _TitleWidthSettingState();
}

class _TitleWidthSettingState extends ConsumerState<TitleWidthSetting> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    double currentWidth = ref.watch(currentTitleWidthProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 滑块
        Row(
          children: [
            Text(t.settings.title_width),
            Expanded(
              child: Slider(
                value: currentWidth,
                min: 40,
                max: 200,
                divisions: 24,
                label: currentWidth.round().toString(),
                onChanged: (value) {
                  ref
                      .read(currentTitleWidthProvider.notifier)
                      .setWidth(value);
                },
                onChangeEnd: (value) {
                  ref
                      .read(uiConfigStateProvider.notifier)
                      .updateTitleWidth(value);
                },
              ),
            ),
            SizedBox(
              width: 50,
              child: Text('${currentWidth.round()}'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // 预览
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.settings.title_width_preview,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      alignment: Alignment.centerLeft,
                      width: currentWidth,
                      child: Text(
                        'Title',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: SelectableText(
                        'This is a sample content text that can be very long...',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
