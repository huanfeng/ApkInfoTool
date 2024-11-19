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
  String getExecutableExtension() {
    if (Platform.isWindows) {
      return 'exe';
    } else if (Platform.isMacOS || Platform.isLinux) {
      return '*';
    }
    return '';
  }

  void openFilePicker(ValueChanged<String> cb) async {
    var result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      dialogTitle: context.loc.select_exe_file,
      allowedExtensions: [getExecutableExtension()],
      lockParentWindow: true,
    );
    log('result=$result');
    var file = result?.files.single;
    // 打开文件选择
    if (file != null) {
      log('filePaths=$file');
      if (file.path != null) {
        cb(file.path!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.loc.select),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
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
                          child: Text(context.loc.select))),
                ),
                Card(
                    child: TitleValueRow(
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
                            child: Text(context.loc.select)))),
              ],
            ),
          ))
        ],
      ),
    );
  }
}
