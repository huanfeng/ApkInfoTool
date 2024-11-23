import 'package:apk_info_tool/pages/setting.dart';
import 'package:chinese_font_library/chinese_font_library.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'config.dart';
import 'pages/home.dart';
import 'theme/theme_manager.dart';
import 'utils/log.dart';
import 'utils/logger.dart';

late PackageInfo packageInfo;
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

  packageInfo = await PackageInfo.fromPlatform();

  await Logger.instance.init();

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
      await windowManager.setTitle('$appTitle v${packageInfo.version}');
      await windowManager.show();
      // await windowManager.setPreventClose(true);
    });
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeManager(),
      child: Consumer<ThemeManager>(
        builder: (context, themeManager, _) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          title: appTitle,
          initialRoute: "/",
          theme: themeManager.themeData.useSystemChineseFont(Brightness.light),
          routes: {
            "/": (context) => const APKInfoPage(),
            "setting": (context) => const SettingPage(),
          },
        ),
      ),
    );
  }
}
