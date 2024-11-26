import 'package:flutter/material.dart';

import 'package:apk_info_tool/config.dart';

class TitleValueLayout extends StatelessWidget {
  final String title;
  final String value;
  final Widget? end;
  final int? minLines;
  final int? maxLines;
  final double? titleWidth;
  final bool selectable;

  const TitleValueLayout({
    super.key,
    required this.title,
    required this.value,
    this.end,
    this.minLines,
    this.maxLines,
    this.titleWidth,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 标题部分
          SizedBox(
            width: titleWidth ?? Config.titleWidth,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // 内容部分
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
              minLines: minLines,
              maxLines: maxLines,
            ),
          ),
          if (end != null) ...[
            const SizedBox(width: 8),
            end!,
          ],
        ],
      ),
    );
  }
}
