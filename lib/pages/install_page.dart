import 'package:apk_info_tool/gen/strings.g.dart';
import 'package:apk_info_tool/pages/pages.dart';
import 'package:apk_info_tool/providers/home_page_provider.dart';
import 'package:apk_info_tool/providers/setting_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class APKInstallPage extends ConsumerStatefulWidget implements PageBase {
  const APKInstallPage({super.key});

  @override
  ConsumerState<APKInstallPage> createState() => _APKInstallPageState();

  @override
  Pages get page => Pages.install;
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
      updateActions();
    }));

    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(t.home.install_page,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        Text(t.home.page_in_development,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  List<Widget> _buildActions() {
    return [];
  }

  void updateActions() {
    final page = ref.read(currentPageProvider);
    if (page == widget.page) {
      ref.read(pageActionsProvider.notifier).setActions(_buildActions());
    }
  }
}
