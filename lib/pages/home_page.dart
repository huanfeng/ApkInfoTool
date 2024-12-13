import 'package:apk_info_tool/gen/strings.g.dart';
import 'package:apk_info_tool/pages/info_page.dart';
import 'package:apk_info_tool/pages/install_page.dart';
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
                    ref.read(currentPageProvider.notifier).setIndex(0),
                  }),
          IconButton(
              icon: Icon(Icons.android_outlined),
              tooltip: t.home.install_page,
              onPressed: () => {
                    ref.read(currentPageProvider.notifier).setIndex(1),
                  }),
        ]),
        actions: actions,
      ),
      body: IndexedStack(
        index: ref.watch(currentPageProvider),
        children: const [
          APKInfoPage(0),
          APKInstallPage(1),
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
