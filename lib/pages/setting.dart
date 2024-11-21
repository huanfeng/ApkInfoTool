import 'dart:developer';
import 'dart:io';

import 'package:apk_info_tool/utils/local.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'widgets.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  final _maxLinesController = TextEditingController(text: '6');
  bool _enableSignatureCheck = true;
  Color _themeColor = Colors.blue;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _maxLinesController.text = prefs.getInt('maxLines')?.toString() ?? '6';
      _enableSignatureCheck = prefs.getBool('enableSignature') ?? true;
      _themeColor = Color(prefs.getInt('themeColor') ?? Colors.blue.value);
    });
  }

  void _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('maxLines', int.tryParse(_maxLinesController.text) ?? 6);
    await prefs.setBool('enableSignature', _enableSignatureCheck);
    await prefs.setInt('themeColor', _themeColor.value);
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

  Widget _buildEnvironmentSection() {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.computer),
        title: Text(context.loc.environment),
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
      ),
    );
  }

  Widget _buildFeaturesSection() {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.featured_play_list),
        title: Text(context.loc.features),
        children: [
          SwitchListTile(
            title: Text(context.loc.enable_signature),
            value: _enableSignatureCheck,
            onChanged: (bool value) {
              setState(() {
                _enableSignatureCheck = value;
                _saveSettings();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceSection() {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.palette),
        title: Text(context.loc.appearance),
        children: [
          ListTile(
            title: Text(context.loc.theme_color),
            trailing: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: _themeColor,
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
                    onChanged: (value) => _saveSettings(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection() {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.info),
        title: Text(context.loc.about),
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
      ),
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
