import 'dart:developer';

import 'package:apk_info_tool/pages/setting.dart';
import 'package:chinese_font_library/chinese_font_library.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'config.dart';
import 'pages/home.dart';

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
