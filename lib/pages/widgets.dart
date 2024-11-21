import 'package:flutter/material.dart';

class TitleValueRow extends StatefulWidget {
  final String title;
  final String value;
  final Widget? end;
  final int titleFlex;
  final int textFlex;
  final int? maxLines;
  final int? minLines;
  final Widget? prefix;

  const TitleValueRow({
    super.key,
    required this.title,
    required this.value,
    this.end,
    this.titleFlex = 2,
    this.textFlex = 6,
    this.maxLines,
    this.minLines,
    this.prefix,
  });

  @override
  State<TitleValueRow> createState() => _TitleValueRowState();
}

class _TitleValueRowState extends State<TitleValueRow> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (widget.prefix != null) widget.prefix!,
        Expanded(
            flex: widget.titleFlex, child: ListTile(title: Text(widget.title))),
        Expanded(
          flex: widget.textFlex,
          child: SelectableText(widget.value,
              minLines: widget.minLines, maxLines: widget.maxLines),
        ),
        if (widget.end != null) widget.end!,
      ],
    );
  }
}
