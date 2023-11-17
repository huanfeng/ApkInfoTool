import 'dart:developer';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'main.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  _SettingPageState createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  FilePickerResult? filePickerResult;
  String? selectedFilePath;
  int? fileSize;

  TextEditingController packageNameController = TextEditingController(text: '');

  void openFilePicker() async {
    var result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['apk'],
    );
    log('result=$result');
    var file = result?.files.single;
    // 打开文件选择
    if (file != null) {
      log('filePaths=$file');
      setState(() {
        fileSize = file.size;
        selectedFilePath = file.path;
        WindowManager.instance.setTitle(file.name);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Setting"),
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
                        title: "文件", value: selectedFilePath ?? "")),
                Card(
                    child: TitleValueRow(
                        title: "大小", value: "${fileSize ?? 0} bytes")),
              ],
            ),
          ))
        ],
      ),
    );
  }
}
