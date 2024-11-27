import 'package:apk_info_tool/gen/strings.g.dart';
import 'package:apk_info_tool/pages/setting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'config.dart';
import 'pages/home.dart';
import 'theme/theme_manager.dart';
import 'utils/logger.dart';

late PackageInfo packageInfo;

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
  await Config.loadConfig();

  packageInfo = await PackageInfo.fromPlatform();

  await LoggerInit.instance.init();

  log.info("main: args=$arguments");
  if (arguments.isNotEmpty) {
    apkByArgs = arguments.first;
  }

  WidgetsFlutterBinding.ensureInitialized();

  if (isDesktop) {
    await windowManager.ensureInitialized();
    windowManager.waitUntilReadyToShow().then((_) async {
      await windowManager.setMinimumSize(const Size(400, 400));
      await windowManager.setSize(const Size(500, 600));
      await windowManager.setTitle('${t.title} v${packageInfo.version}');
      await windowManager.show();
      // await windowManager.setPreventClose(true);
    });
  }
  LocaleSettings.useDeviceLocale();
  runApp(TranslationProvider(child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeManager(),
      child: Consumer<ThemeManager>(
        builder: (context, themeManager, _) => MaterialApp(
          locale: TranslationProvider.of(context).flutterLocale,
          supportedLocales: AppLocaleUtils.supportedLocales,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          title: t.title,
          initialRoute: "/",
          theme: themeManager.themeData,
          routes: {
            "/": (context) => const APKInfoPage(),
            "setting": (context) => const SettingPage(),
          },
        ),
      ),
    );
  }
}
