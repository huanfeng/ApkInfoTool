import 'package:apk_info_tool/gen/strings.g.dart';
import 'package:apk_info_tool/providers/home_page_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class APKInstallPage extends ConsumerStatefulWidget {
  final int pageIndex;

  const APKInstallPage(this.pageIndex, {super.key});

  @override
  ConsumerState<APKInstallPage> createState() => _APKInstallPageState();
}

class _APKInstallPageState extends ConsumerState<APKInstallPage> {
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero).then((value) {
      updateActions();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentPageProvider, ((previous, next) {
      if (next == widget.pageIndex) {
        ref.read(pageActionsProvider.notifier).setActions(_buildActions());
      }
    }));

    return Center(
      child: Text(t.home.page_in_development,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
    );
  }

  List<Widget> _buildActions() {
    return [];
  }

  void updateActions() {
    final page = ref.read(currentPageProvider);
    if (page == widget.pageIndex) {
      ref.read(pageActionsProvider.notifier).setActions(_buildActions());
    }
  }
}
