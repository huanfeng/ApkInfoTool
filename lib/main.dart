import 'package:apk_info_tool/apk_info.dart';
import 'package:apk_info_tool/setting.dart';
import 'package:flutter/material.dart';
import "package:file_picker/file_picker.dart";
import 'package:chinese_font_library/chinese_font_library.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer';

import 'config.dart';

void main() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  Config.loadConfig(prefs);

  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // WindowOptions windowOptions = WindowOptions(
  //   size: Size(800, 600),
  //   center: true,
  //   backgroundColor: Colors.transparent,
  //   skipTaskbar: false,
  //   titleBarStyle: TitleBarStyle.hidden,
  // );
  // windowManager.waitUntilReadyToShow(windowOptions, () async {
  //   await windowManager.show();
  //   await windowManager.focus();
  // });

  runApp(const MyApp());
}

class APKInfoPage extends StatefulWidget {
  const APKInfoPage({super.key});

  @override
  _APKInfoPageState createState() => _APKInfoPageState();
}

class _APKInfoPageState extends State<APKInfoPage> {
  FilePickerResult? filePickerResult;
  String? selectedFilePath;
  int? fileSize;

  TextEditingController packageNameController = TextEditingController(text: '');

  void openFilePicker() async {
    var result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['apk'],
    );
    log('result=$result');
    var file = result?.files.single;
    // 打开文件选择
    if (file != null) {
      log('filePaths=$file');
      setState(() {
        fileSize = file.size;
        selectedFilePath = file.path;
        WindowManager.instance.setTitle(file.name);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("APK Info"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
              icon: const Icon(Icons.folder),
              onPressed: () async {
                openFilePicker();
              }),
          IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                getApkInfo();
              }),
          IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.pushNamed(context, 'setting');
              }),
          const SizedBox(width: 50),
        ],
      ),
      // drawer: Drawer(
      //     child: ListView(
      //   children: [
      //     ListTile(
      //       title: Text('Home'),
      //       onTap: () {
      //         // 切换到首页
      //         Navigator.pushNamed(context, '/');
      //       },
      //     ),
      //     ListTile(
      //       title: Text('About'),
      //       onTap: () {
      //         // 切换到关于页面
      //         // Navigator.pop(context);
      //         Navigator.pushNamed(context, 'setting');
      //       },
      //     ),
      //   ],
      // )),
      body: Column(
        children: [
          // 信息显示区
          Expanded(
              child: Padding(
            // 指定上下左右的内边距为 10 像素
            padding: const EdgeInsets.only(left: 10, right: 10),
            child: ListView(
              children: [
                Card(
                    child: TitleValueRow(
                        title: "文件", value: selectedFilePath ?? "")),
                Card(
                    child: TitleValueRow(
                        title: "大小", value: "${fileSize ?? 0} bytes")),
                Card(child: TitleValueRow(title: "包名", value: "")),
                Card(child: TitleValueRow(title: "版本", value: "")),
                const Card(child: ListTile(title: Text("Permissions"))),
              ],
            ),
          ))
        ],
      ),
    );
  }
}

class TitleValueRow extends StatefulWidget {
  final String title;
  final String value;

  TitleValueRow({
    required this.title,
    required this.value,
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
        Expanded(child: ListTile(title: Text(widget.title))),
        Expanded(
          flex: 4,
          child: SelectableText(widget.value),
        ),
      ],
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: const [
        // 本地化的代理类
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', 'US'), // 美国英语
        Locale('zh', 'CN'), // 中文简体
        //其他Locales
      ],
      title: 'Flutter Demo',
      initialRoute: "/",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurpleAccent),
        useMaterial3: true,
      ).useSystemChineseFont(Brightness.light),
      routes: {
        "/": (context) => const APKInfoPage(), //注册首页路由
        "setting": (context) => const SettingPage(),
      },
      // home: const APKInfoPage(),
    );
  }
}
