import 'dart:developer';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../apk_info.dart';
import '../config.dart';
import '../main.dart';
import '../utils/local.dart';
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
      dialogTitle: context.loc.select_apk_file,
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
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.loc.tint_set_aapt2_path)));
        return;
      }
      getApkInfo(selectedFilePath!).then((value) {
        if (value == null) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.loc.warn_parse_apk_info_fail)));
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
              tooltip: context.loc.open_apk,
              onPressed: () async {
                openFilePicker();
              }),
          IconButton(
              icon: const Icon(Icons.search),
              tooltip: context.loc.parse_apk,
              onPressed: () {
                loadApkInfo();
              }),
          IconButton(
              icon: const Icon(Icons.settings),
              tooltip: context.loc.setting,
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
                        title: context.loc.file,
                        value: selectedFilePath ?? "")),
                Card(
                    child: TitleValueRow(
                        title: context.loc.size,
                        value: "${fileSize ?? 0} bytes")),
                Card(
                    child: TitleValueRow(
                        title: context.loc.package_name,
                        value: apkInfo?.packageName ?? "")),
                Card(
                    child: TitleValueRow(
                        title: context.loc.app_name,
                        value: apkInfo?.label ?? "")),
                Row(
                  children: [
                    Expanded(
                        child: Card(
                      child: TitleValueRow(
                          title: context.loc.min_sdk,
                          value: "${apkInfo?.sdkVersion ?? ""}",
                          titleFlex: 6),
                    )),
                    Expanded(
                        child: Card(
                            child: TitleValueRow(
                                title: context.loc.target_sdk,
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
                                title: context.loc.version_code,
                                value: "${apkInfo?.versionCode ?? ""}",
                                titleFlex: 6))),
                    Expanded(
                        child: Card(
                            child: TitleValueRow(
                                title: context.loc.version_name,
                                value: apkInfo?.versionName ?? "",
                                titleFlex: 6))),
                  ],
                ),
                Card(
                    child: TitleValueRow(
                        title: context.loc.screen_size,
                        value: apkInfo?.supportsScreens.join(" ") ?? "")),
                Card(
                    child: TitleValueRow(
                        title: context.loc.screen_density,
                        value: apkInfo?.densities.join(" ") ?? "")),
                Card(
                    child: TitleValueRow(
                        title: context.loc.abi,
                        value: apkInfo?.nativeCodes.join(" ") ?? "")),
                Card(
                    child: TitleValueRow(
                        title: context.loc.language_list,
                        value: apkInfo?.locales.join(" ") ?? "")),
                Card(
                    child: TitleValueRow(
                        title: context.loc.perm_list,
                        value: apkInfo?.usesPermissions.join("\n") ?? "")),
              ],
            ),
          ))
        ],
      ),
    );
  }
}
