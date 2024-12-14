import 'package:apk_info_tool/gen/strings.g.dart';
import 'package:apk_info_tool/pages/info_page.dart';
import 'package:apk_info_tool/pages/install_page.dart';
import 'package:apk_info_tool/pages/pages.dart';
import 'package:apk_info_tool/providers/home_page_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WindowListener, TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actions = ref.watch(pageActionsProvider);
    final pages = [Pages.info, Pages.install];
    final currPage = ref.watch(currentPageProvider);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Row(children: [
          Text(t.title),
          SizedBox(
            width: 12,
          ),
          IconButton(
              icon: Icon(Icons.info_outline),
              tooltip: t.home.info_page,
              onPressed: () => {
                    ref.read(currentPageProvider.notifier).setPage(Pages.info),
                  }),
          IconButton(
              icon: Icon(Icons.android_outlined),
              tooltip: t.home.install_page,
              onPressed: () => {
                    ref
                        .read(currentPageProvider.notifier)
                        .setPage(Pages.install),
                  }),
        ]),
        actions: actions,
      ),
      body: IndexedStack(
        key: ObjectKey(currPage), // 这里是为了解决 IndexedStack 的子页语言不正确的问题
        index: pages.indexOf(currPage),
        children: const [
          APKInfoPage(),
          APKInstallPage(),
        ],
      ),
    );
  }

  @override
  void onWindowMaximize() => setState(() {});
  @override
  void onWindowUnmaximize() => setState(() {});
  @override
  void onWindowMinimize() => setState(() {});
  @override
  void onWindowRestore() => setState(() {});
  @override
  void onWindowResize() => setState(() {});
  @override
  void onWindowFocus() => setState(() {});
}
