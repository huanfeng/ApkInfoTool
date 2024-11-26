import 'package:apk_info_tool/gen/strings.g.dart';
import 'package:flutter/material.dart';
import '../config.dart';

class TitleWidthSetting extends StatefulWidget {
  const TitleWidthSetting({super.key});

  @override
  State<TitleWidthSetting> createState() => _TitleWidthSettingState();
}

class _TitleWidthSettingState extends State<TitleWidthSetting> {
  late double _currentWidth;

  @override
  void initState() {
    super.initState();
    _currentWidth = Config.titleWidth;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 滑块
        Row(
          children: [
            Text(t.settings.title_width),
            Expanded(
              child: Slider(
                value: _currentWidth,
                min: 40,
                max: 200,
                divisions: 24,
                label: _currentWidth.round().toString(),
                onChanged: (value) {
                  setState(() {
                    _currentWidth = value;
                    Config.titleWidth = value;
                  });
                },
              ),
            ),
            SizedBox(
              width: 50,
              child: Text('${_currentWidth.round()}'),
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
                      width: _currentWidth,
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
