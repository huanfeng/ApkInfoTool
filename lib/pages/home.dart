import 'dart:developer';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../apk_info.dart';
import '../config.dart';
import '../main.dart';
import 'widgets.dart';

class APKInfoPage extends StatefulWidget {
  const APKInfoPage({super.key});

  @override
  State<APKInfoPage> createState() => _APKInfoPageState();
}

class _APKInfoPageState extends State<APKInfoPage> {
  FilePickerResult? filePickerResult;
  String? selectedFilePath;
  int? fileSize;
  ApkInfo? apkInfo;

  void openFilePicker() async {
    var result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      dialogTitle: "请选择APK文件",
      allowedExtensions: ['apk'],
      lockParentWindow: true,
    );
    log('result=$result');
    var file = result?.files.single;
    // 打开文件选择
    if (file != null) {
      log('filePaths=$file');
      if (file.path != null) {
        openApk(file.path!, file.size);
      }
    }
  }

  void openApk(String path, int size) {
    setState(() {
      fileSize = size;
      selectedFilePath = path;
      if (selectedFilePath != null) {
        loadApkInfo();
      }
    });
  }

  void loadApkInfo() {
    if (selectedFilePath != null) {
      if (Config.aapt2Path.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("请先设置 aapt2 路径")));
        return;
      }
      getApkInfo(selectedFilePath!).then((value) {
        if (value == null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text("解析APK信息失败!")));
        } else {
          setState(() {
            apkInfo = value;
          });
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    log("initState apkByArgs=$apkByArgs", level: 2);
    if (apkByArgs.isNotEmpty) {
      final file = File(apkByArgs);
      if (file.existsSync()) {
        openApk(file.path, file.lengthSync());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(appTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
              icon: const Icon(Icons.folder),
              tooltip: "打开APK",
              onPressed: () async {
                openFilePicker();
              }),
          IconButton(
              icon: const Icon(Icons.search),
              tooltip: "解析APK信息",
              onPressed: () {
                loadApkInfo();
              }),
          IconButton(
              icon: const Icon(Icons.settings),
              tooltip: "设置",
              onPressed: () {
                Navigator.pushNamed(context, 'setting');
              }),
          // 最右的空间
          const SizedBox(width: 50),
        ],
      ),
      // drawer: Drawer(
      //     child: ListView(
      //   children: [
      //     ListTile(
      //       title: Text('Home'),
      //       onTap: () {
      //         // 切换到首页
      //         Navigator.pushNamed(context, '/');
      //       },
      //     ),
      //     ListTile(
      //       title: Text('About'),
      //       onTap: () {
      //         // 切换到关于页面
      //         // Navigator.pop(context);
      //         Navigator.pushNamed(context, 'setting');
      //       },
      //     ),
      //   ],
      // )),
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
                Card(
                    child: TitleValueRow(
                        title: "包名", value: apkInfo?.packageName ?? "")),
                Card(
                    child: TitleValueRow(
                        title: "应用名称", value: apkInfo?.label ?? "")),
                Row(
                  children: [
                    Expanded(
                        child: Card(
                      child: TitleValueRow(
                          title: "最低SDK",
                          value: "${apkInfo?.sdkVersion ?? ""}",
                          titleFlex: 6),
                    )),
                    Expanded(
                        child: Card(
                            child: TitleValueRow(
                                title: "目标SDK",
                                value:
                                    apkInfo?.targetSdkVersion?.toString() ?? "",
                                titleFlex: 6))),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                        child: Card(
                            child: TitleValueRow(
                                title: "版本号",
                                value: "${apkInfo?.versionCode ?? ""}",
                                titleFlex: 6))),
                    Expanded(
                        child: Card(
                            child: TitleValueRow(
                                title: "版本名称",
                                value: apkInfo?.versionName ?? "",
                                titleFlex: 6))),
                  ],
                ),
                Card(
                    child: TitleValueRow(
                        title: "屏幕尺寸",
                        value: apkInfo?.supportsScreens.join(" ") ?? "")),
                Card(
                    child: TitleValueRow(
                        title: "屏幕密度",
                        value: apkInfo?.densities.join(" ") ?? "")),
                Card(
                    child: TitleValueRow(
                        title: "ABI",
                        value: apkInfo?.nativeCodes.join(" ") ?? "")),
                Card(
                    child: TitleValueRow(
                        title: "语言列表",
                        value: apkInfo?.locales.join(" ") ?? "")),
                Card(
                    child: TitleValueRow(
                        title: "权限列表",
                        value: apkInfo?.usesPermissions.join("\n") ?? "")),
              ],
            ),
          ))
        ],
      ),
    );
  }
}
