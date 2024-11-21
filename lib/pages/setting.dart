import 'dart:developer';
import 'dart:io';

import 'package:apk_info_tool/utils/local.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import 'widgets.dart';

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
      dialogTitle: context.loc.select_exe_file,
      allowedExtensions: getExecutableExtensions(),
      lockParentWindow: true,
    );
    log('result=$result');
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
      title: context.loc.environment,
      icon: Icons.computer,
      initiallyExpanded: true,
      children: [
        TitleValueRow(
          title: context.loc.aapt_path,
          value: Config.aapt2Path,
          end: TextButton(
            onPressed: () {
              openFilePicker((path) {
                setState(() {
                  Config.aapt2Path = path;
                });
              });
            },
            child: Text(context.loc.select),
          ),
        ),
        TitleValueRow(
          title: context.loc.adb_path,
          value: Config.adbPath,
          end: TextButton(
            onPressed: () {
              openFilePicker((path) {
                setState(() {
                  Config.adbPath = path;
                });
              });
            },
            child: Text(context.loc.select),
          ),
        ),
        TitleValueRow(
          title: context.loc.apksigner_path,
          value: Config.apksignerPath,
          end: TextButton(
            onPressed: () {
              openFilePicker((path) {
                setState(() {
                  Config.apksignerPath = path;
                });
              });
            },
            child: Text(context.loc.select),
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturesSection() {
    return _buildSettingCard(
      title: context.loc.features,
      icon: Icons.featured_play_list,
      children: [
        SwitchListTile(
          title: Text(context.loc.enable_signature),
          value: Config.enableSignature,
          onChanged: (bool value) {
            setState(() {
              Config.enableSignature = value;
            });
          },
        ),
      ],
    );
  }

  Widget _buildAppearanceSection() {
    return _buildSettingCard(
      title: context.loc.appearance,
      icon: Icons.palette,
      children: [
        ListTile(
          title: Text(context.loc.theme_color),
          trailing: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Config.themeColor,
              shape: BoxShape.circle,
            ),
          ),
          onTap: () {
            // TODO: Add color picker
          },
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: Text(context.loc.max_lines),
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
      ],
    );
  }

  Widget _buildAboutSection() {
    return _buildSettingCard(
      title: context.loc.about,
      icon: Icons.info,
      children: [
        ListTile(
          title: const Text('APK Info Tool'),
          subtitle: const Text('Version 1.0.0'),
        ),
        const ListTile(
          title: Text('Dependencies'),
          subtitle: Text('Flutter SDK\nDart SDK\naapt2\napksigner'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.loc.setting),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildEnvironmentSection(),
          _buildFeaturesSection(),
          _buildAppearanceSection(),
          _buildAboutSection(),
        ],
      ),
    );
  }
}
