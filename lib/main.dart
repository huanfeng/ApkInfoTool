import 'dart:io';

import 'package:apk_info_tool/apk_info.dart';
import 'package:apk_info_tool/setting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import "package:file_picker/file_picker.dart";
import 'package:chinese_font_library/chinese_font_library.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:developer';

import 'config.dart';

const appTitle = "APK Info Tool";

String apkByArgs = "";

bool get isDesktop {
  if (kIsWeb) return false;
  return [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ].contains(defaultTargetPlatform);
}

void main(List<String> arguments) async {
  await Config.init();
  Config.loadConfig();

  log("args=$arguments");
  if (arguments.isNotEmpty) {
    apkByArgs = arguments.first;
  }

  WidgetsFlutterBinding.ensureInitialized();

  if (isDesktop) {
    await windowManager.ensureInitialized();
    windowManager.waitUntilReadyToShow().then((_) async {
      await windowManager.setMinimumSize(const Size(400, 400));
      await windowManager.setSize(const Size(500, 600));
      await windowManager.setTitle(appTitle);
      await windowManager.show();
      // await windowManager.setPreventClose(true);
    });
  }
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
  ApkInfo? apkInfo;

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
      if (file.path != null) {
        openApk(file.path!, file.size);
      }
    }
  }

  void openApk(String path, int size) {
    setState(() {
      fileSize = size;
      selectedFilePath = path;
      if (selectedFilePath != null) {
        loadApkInfo();
      }
    });
  }

  void loadApkInfo() {
    if (selectedFilePath != null) {
      if (Config.aapt2Path.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("请先设置 aapt2 路径")));
        return;
      }
      getApkInfo(selectedFilePath!).then((value) {
        if (value == null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text("解析APK信息失败!")));
        } else {
          setState(() {
            apkInfo = value;
          });
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    log("initState apkByArgs=$apkByArgs", level: 2);
    if (apkByArgs.isNotEmpty) {
      final file = File(apkByArgs);
      if (file.existsSync()) {
        openApk(file.path, file.lengthSync());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(appTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
              icon: const Icon(Icons.folder),
              tooltip: "打开APK",
              onPressed: () async {
                openFilePicker();
              }),
          IconButton(
              icon: const Icon(Icons.search),
              tooltip: "解析APK信息",
              onPressed: () {
                loadApkInfo();
              }),
          IconButton(
              icon: const Icon(Icons.settings),
              tooltip: "设置",
              onPressed: () {
                Navigator.pushNamed(context, 'setting');
              }),
          // 最右的空间
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
                Card(
                    child: TitleValueRow(
                        title: "包名", value: apkInfo?.packageName ?? "")),
                Card(
                    child: TitleValueRow(
                        title: "应用名称", value: apkInfo?.label ?? "")),
                Row(
                  children: [
                    Expanded(
                        child: Card(
                      child: TitleValueRow(
                          title: "最低SDK",
                          value: "${apkInfo?.sdkVersion ?? ""}",
                          titleFlex: 6),
                    )),
                    Expanded(
                        child: Card(
                            child: TitleValueRow(
                                title: "目标SDK",
                                value:
                                    apkInfo?.targetSdkVersion?.toString() ?? "",
                                titleFlex: 6))),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                        child: Card(
                            child: TitleValueRow(
                                title: "版本号",
                                value: "${apkInfo?.versionCode ?? ""}",
                                titleFlex: 6))),
                    Expanded(
                        child: Card(
                            child: TitleValueRow(
                                title: "版本名称",
                                value: apkInfo?.versionName ?? "",
                                titleFlex: 6))),
                  ],
                ),
                Card(
                    child: TitleValueRow(
                        title: "屏幕尺寸",
                        value: apkInfo?.supportsScreens.join(" ") ?? "")),
                Card(
                    child: TitleValueRow(
                        title: "屏幕密度",
                        value: apkInfo?.densities.join(" ") ?? "")),
                Card(
                    child: TitleValueRow(
                        title: "ABI",
                        value: apkInfo?.nativeCodes.join(" ") ?? "")),
                Card(
                    child: TitleValueRow(
                        title: "语言列表",
                        value: apkInfo?.locales.join(" ") ?? "")),
                Card(
                    child: TitleValueRow(
                        title: "权限列表",
                        value: apkInfo?.usesPermissions.join("\n") ?? "")),
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
      title: appTitle,
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
