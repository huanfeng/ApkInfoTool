import 'dart:io';

import 'package:apk_info_tool/gen/strings.g.dart';
import 'package:apk_info_tool/widgets/title_value_layout.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../main.dart';
import '../theme/theme_manager.dart';
import '../utils/file_association.dart';
import '../utils/logger.dart';
import '../utils/platform.dart';
import '../widgets/title_width_setting.dart';

const githubUrl = 'https://github.com/huanfeng/ApkInfoTool';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  final _maxLinesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _maxLinesController.text = Config.maxLines.toString();
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
        return AlertDialog(
          title: Text(t.settings.theme_color),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: Config.themeColor,
              onColorChanged: (Color color) {
                Provider.of<ThemeManager>(context, listen: false)
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
    return _buildSettingCard(
      title: t.settings.environment,
      icon: Icons.computer,
      initiallyExpanded: true,
      children: [
        TitleValueLayout(
          title: t.settings.aapt_path,
          value: Config.aapt2Path,
          end: TextButton(
            onPressed: () {
              openFilePicker((path) {
                setState(() {
                  Config.aapt2Path = path;
                });
              });
            },
            child: Text(t.base.select),
          ),
        ),
        TitleValueLayout(
          title: t.settings.apksigner_path,
          value: Config.apksignerPath,
          end: TextButton(
            onPressed: () {
              openFilePicker((path) {
                setState(() {
                  Config.apksignerPath = path;
                });
              });
            },
            child: Text(t.base.select),
          ),
        ),
        TitleValueLayout(
          title: t.settings.adb_path,
          value: Config.adbPath,
          end: TextButton(
            onPressed: () {
              openFilePicker((path) {
                setState(() {
                  Config.adbPath = path;
                });
              });
            },
            child: Text(t.base.select),
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturesSection() {
    return _buildSettingCard(
      title: t.settings.features,
      icon: Icons.featured_play_list,
      children: [
        SwitchListTile(
          title: Text(t.settings.enable_signature),
          value: Config.enableSignature,
          onChanged: (bool value) {
            setState(() {
              Config.enableSignature = value;
            });
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
    return _buildSettingCard(
      title: t.settings.appearance,
      icon: Icons.palette,
      children: [
        ListTile(
          title: Text(t.settings.theme_color),
          trailing: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Config.themeColor,
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
                      Config.maxLines = lines;
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
    return _buildSettingCard(
      title: t.settings.debug,
      icon: Icons.bug_report,
      children: [
        SwitchListTile(
          title: Text(t.settings.enable_debug),
          value: Config.enableDebug,
          onChanged: (bool value) async {
            setState(() {
              Config.enableDebug = value;
            });
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
          enabled: Config.enableDebug,
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
          enabled: Config.enableDebug,
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
