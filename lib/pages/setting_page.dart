import 'dart:io';

import 'package:apk_info_tool/config.dart';
import 'package:apk_info_tool/gen/strings.g.dart';
import 'package:apk_info_tool/main.dart';
import 'package:apk_info_tool/providers/setting_provider.dart';
import 'package:apk_info_tool/providers/ui_config_provider.dart';
import 'package:apk_info_tool/theme/theme_manager.dart';
import 'package:apk_info_tool/utils/file_association.dart';
import 'package:apk_info_tool/utils/logger.dart';
import 'package:apk_info_tool/utils/platform.dart';
import 'package:apk_info_tool/widgets/title_value_layout.dart';
import 'package:apk_info_tool/widgets/title_width_setting.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

const githubUrl = 'https://github.com/huanfeng/ApkInfoTool';

class SettingPage extends ConsumerStatefulWidget {
  const SettingPage({super.key});

  @override
  ConsumerState<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends ConsumerState<SettingPage> {
  final _maxLinesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _maxLinesController.text = ref.read(
        uiConfigStateProvider.select((value) => value.textMaxLines.toString()));
  }

  void openFilePicker(ValueChanged<String> cb) async {
    var result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      dialogTitle: t.settings.select_exe_path,
      allowedExtensions: getExecutableExtensions(),
      lockParentWindow: true,
    );
    log.info('openFilePicker: result=$result');
    var file = result?.files.single;
    if (file != null && file.path != null) {
      cb(file.path!);
    }
  }

  void resetToDefaultPath(String toolType) async {
    switch (toolType) {
      case 'aapt2':
        ref.read(settingStateProvider.notifier).setAapt2Path('');
        break;
      case 'adb':
        ref.read(settingStateProvider.notifier).setAdbPath('');
        break;
      case 'apksigner':
        ref.read(settingStateProvider.notifier).setApksignerPath('');
        break;
    }
  }

  List<String> getExecutableExtensions() {
    if (Platform.isWindows) {
      return ['exe', 'bat'];
    } else if (Platform.isMacOS || Platform.isLinux) {
      return ['*'];
    }
    return [''];
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Consumer(builder: (context, ref, child) {
          final themeColor = ref
              .watch(themeManagerProvider.select((value) => value.themeColor));
          return AlertDialog(
            title: Text(t.settings.theme_color),
            content: SingleChildScrollView(
              child: ColorPicker(
                pickerColor: Color(themeColor),
                onColorChanged: (Color color) {
                  ref
                      .read(themeManagerProvider.notifier)
                      .updateThemeColor(color);
                },
                pickerAreaHeightPercent: 0.8,
                enableAlpha: false,
                displayThumbColor: true,
                paletteType: PaletteType.hsvWithHue,
                pickerAreaBorderRadius:
                    const BorderRadius.all(Radius.circular(10)),
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text(t.base.ok),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        });
      },
    );
  }

  Widget _buildSettingCard({
    required String title,
    required List<Widget> children,
    required IconData icon,
    bool initiallyExpanded = false,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(icon),
          title: Text(title),
          initiallyExpanded: initiallyExpanded,
          children: children,
        ),
      ),
    );
  }

  Widget _buildEnvironmentSection() {
    final aapt2Path =
        ref.watch(settingStateProvider.select((value) => value.aapt2Path));
    final apksignerPath =
        ref.watch(settingStateProvider.select((value) => value.apksignerPath));
    final adbPath =
        ref.watch(settingStateProvider.select((value) => value.adbPath));

    return _buildSettingCard(
      title: t.settings.environment,
      icon: Icons.computer,
      initiallyExpanded: true,
      children: [
        TitleValueLayout(
            title: t.settings.aapt_path,
            value: aapt2Path,
            end: Row(children: [
              TextButton(
                onPressed: () {
                  openFilePicker((path) {
                    ref.read(settingStateProvider.notifier).setAapt2Path(path);
                  });
                },
                child: Text(t.base.select),
              ),
              TextButton(
                onPressed: () => resetToDefaultPath('aapt2'),
                child: Text(t.settings.reset),
              )
            ])),
        if (!Platform.isMacOS)
          TitleValueLayout(
              title: t.settings.apksigner_path,
              value: apksignerPath,
              end: Row(children: [
                TextButton(
                  onPressed: () {
                    openFilePicker((path) {
                      ref
                          .read(settingStateProvider.notifier)
                          .setApksignerPath(path);
                    });
                  },
                  child: Text(t.base.select),
                ),
                TextButton(
                  onPressed: () => resetToDefaultPath('apksigner'),
                  child: Text(t.settings.reset),
                )
              ])),
        TitleValueLayout(
          title: t.settings.adb_path,
          value: adbPath,
          end: Row(children: [
            TextButton(
              onPressed: () {
                openFilePicker((path) {
                  ref.read(settingStateProvider.notifier).setAdbPath(path);
                });
              },
              child: Text(t.base.select),
            ),
            TextButton(
              onPressed: () => resetToDefaultPath('adb'),
              child: Text(t.settings.reset),
            )
          ]),
        ),
      ],
    );
  }

  Widget _buildFeaturesSection() {
    final enableSignature = ref
        .watch(settingStateProvider.select((value) => value.enableSignature));
    return _buildSettingCard(
      title: t.settings.features,
      icon: Icons.featured_play_list,
      children: [
        if (!Platform.isMacOS)
          SwitchListTile(
            title: Text(t.settings.enable_signature),
            value: enableSignature,
            onChanged: (bool value) {
              ref.read(settingStateProvider.notifier).setEnableSignature(value);
            },
          ),
        if (FileAssociationManager.isSupported)
          ListTile(
            title: Text(t.settings.file_association),
            trailing: TextButton(
              onPressed: () async {
                try {
                  await FileAssociationManager.openDefaultAppsSettings();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(t.settings.cannot_open_settings),
                    ),
                  );
                }
              },
              child: Text(t.settings.open_settings),
            ),
          ),
      ],
    );
  }

  Widget _buildAppearanceSection() {
    final themeColor =
        ref.watch(themeManagerProvider.select((value) => value.themeColor));
    return _buildSettingCard(
      title: t.settings.appearance,
      icon: Icons.palette,
      children: [
        ListTile(
          title: Text(t.settings.language),
          trailing: DropdownButton<String>(
            value: ref
                .watch(settingStateProvider.select((value) => value.language)),
            items: [
              DropdownMenuItem(
                value: Config.kLanguageAuto,
                child: Text(t.settings.language_auto),
              ),
              DropdownMenuItem(
                value: AppLocale.en.languageCode,
                child: Text('English'),
              ),
              DropdownMenuItem(
                value: AppLocale.zhCn.languageCode,
                child: Text('简体中文'),
              ),
            ],
            onChanged: (String? value) {
              if (value != null) {
                ref.read(settingStateProvider.notifier).setLanguage(value);
              }
            },
          ),
        ),
        ListTile(
          title: Text(t.settings.theme_color),
          trailing: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Color(themeColor),
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).dividerColor.withOpacity(0.2),
                width: 1,
              ),
            ),
          ),
          onTap: _showColorPicker,
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: Text(t.settings.max_lines),
              ),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _maxLinesController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    final lines = int.tryParse(value);
                    if (lines != null) {
                      ref
                          .read(uiConfigStateProvider.notifier)
                          .updateTextMaxLines(lines);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: TitleWidthSetting(),
        ),
      ],
    );
  }

  Widget _buildDebugSection() {
    final enableDebug =
        ref.watch(settingStateProvider.select((value) => value.enableDebug));
    return _buildSettingCard(
      title: t.settings.debug,
      icon: Icons.bug_report,
      children: [
        SwitchListTile(
          title: Text(t.settings.enable_debug),
          value: enableDebug,
          onChanged: (bool value) async {
            ref.read(settingStateProvider.notifier).setEnableDebug(value);
            // 重新初始化日志系统
            if (!value) {
              await LoggerInit.instance.dispose();
            } else {
              await LoggerInit.instance.dispose();
              await LoggerInit.instance.init();
            }
          },
        ),
        ListTile(
          enabled: enableDebug,
          title: Text(t.settings.open_debug_log),
          leading: const Icon(Icons.description),
          onTap: () {
            final logPath = LoggerInit.instance.logFilePath;
            if (logPath != null) {
              openFileInExplorer(logPath);
            }
          },
        ),
        ListTile(
          enabled: enableDebug,
          title: Text(t.settings.open_debug_directory),
          leading: const Icon(Icons.folder),
          onTap: () {
            final logPath = LoggerInit.instance.logFilePath;
            if (logPath != null) {
              openFileInExplorer(logPath);
            }
          },
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ListTile(
          leading: const Icon(Icons.info),
          title: Text(t.settings.about),
          onTap: () {
            showAboutDialog(
              context: context,
              applicationName: t.title,
              applicationVersion: packageInfo.version,
              applicationIcon: Image.asset(
                'assets/image/icon.png',
                width: 64,
                height: 64,
              ),
              applicationLegalese: '2024 Fengware',
              children: [
                const SizedBox(height: 16),
                InkWell(
                  onTap: () {
                    launchUrl(Uri.parse(githubUrl));
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.link, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        githubUrl,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t.settings.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildEnvironmentSection(),
          _buildFeaturesSection(),
          _buildAppearanceSection(),
          _buildDebugSection(),
          _buildAboutSection(),
        ],
      ),
    );
  }
}
