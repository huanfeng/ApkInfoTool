import 'package:flutter/material.dart';

class TitleValueRow extends StatefulWidget {
  final String title;
  final String value;
  final Widget? end;
  final int titleFlex;
  final int textFlex;

  const TitleValueRow({
    super.key,
    required this.title,
    required this.value,
    this.end,
    this.titleFlex = 2,
    this.textFlex = 6,
  });

  @override
  _TitleValueRowState createState() => _TitleValueRowState();
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
        Expanded(
            flex: widget.titleFlex, child: ListTile(title: Text(widget.title))),
        Expanded(
          flex: widget.textFlex,
          child: SelectableText(widget.value),
        ),
        if (widget.end != null) widget.end!,
      ],
    );
  }
}
