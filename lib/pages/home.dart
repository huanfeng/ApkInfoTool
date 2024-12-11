import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:apk_info_tool/gen/strings.g.dart';
import './info_page.dart';
import './install_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with WindowListener, TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              // text: '信息',
              onPressed: () => {_tabController.animateTo(0)}),
          IconButton(
              icon: Icon(Icons.android_outlined),
              // text: '安装',
              onPressed: () => {_tabController.animateTo(1)}),
        ]),
        actions: [],
      ),
      body: Row(children: [
        Expanded(
            child: TabBarView(
          controller: _tabController,
          children: const [
            APKInfoPage(),
            APKInstallPage(),
          ],
        ))
      ]),
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
