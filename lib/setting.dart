import 'dart:developer';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'config.dart';
import 'main.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  _SettingPageState createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  void openFilePicker(ValueChanged<String> cb) async {
    var result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['exe'],
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
        title: const Text("设置"),
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
                      title: "AAPT路径:",
                      value: Config.aapt2Path,
                      end: TextButton(
                          onPressed: () {
                            openFilePicker((path) {
                              setState(() {
                                Config.aapt2Path = path;
                              });
                            });
                          },
                          child: const Text("选择"))),
                ),
                Card(
                    child: TitleValueRow(
                        title: "ADB路径:",
                        value: Config.adbPath,
                        end: TextButton(
                            onPressed: () {
                              openFilePicker((path) {
                                setState(() {
                                  Config.adbPath = path;
                                });
                              });
                            },
                            child: const Text("选择")))),
              ],
            ),
          ))
        ],
      ),
    );
  }
}
