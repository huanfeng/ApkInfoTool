import 'package:apk_info_tool/config.dart';
import 'package:apk_info_tool/gen/strings.g.dart';
import 'package:apk_info_tool/pages/home_page.dart';
import 'package:apk_info_tool/pages/setting_page.dart';
import 'package:apk_info_tool/theme/theme_manager.dart';
import 'package:apk_info_tool/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';

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
  WidgetsFlutterBinding.ensureInitialized();

  await Config.init();
  await Config.loadConfig();

  packageInfo = await PackageInfo.fromPlatform();

  await LoggerInit.instance.init();

  log.info("main: arguments=$arguments");
  if (arguments.isNotEmpty) {
    apkByArgs = arguments.first;
  }

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
  final lang = Config.language.value;
  if (lang.isEmpty || lang == Config.kLanguageAuto) {
    LocaleSettings.useDeviceLocale();
  } else {
    LocaleSettings.setLocaleRaw(lang);
  }
  runApp(ProviderScope(child: TranslationProvider(child: const MyApp())));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeManager = ref.watch(themeManagerProvider);
    return MaterialApp(
      locale: TranslationProvider.of(context).flutterLocale,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      title: t.title,
      initialRoute: "/",
      theme: themeManager.themeData,
      routes: {
        "/": (context) => const HomePage(),
        "setting": (context) => const SettingPage(),
      },
    );
  }
}
