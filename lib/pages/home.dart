import 'dart:developer';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';

import '../apk_info.dart';
import '../config.dart';
import '../main.dart';
import '../utils/local.dart';
import '../utils/platform.dart';
import 'widgets.dart';
import '../utils/android_version.dart';
import '../utils/format.dart';

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
  bool _isParsing = false;

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

  String getSdkVersionText(int? sdkVersion) {
    if (sdkVersion == null) return "";
    return "$sdkVersion (${AndroidVersion.getAndroidVersion(sdkVersion)})";
  }

  Future<void> loadApkInfo() async {
    if (selectedFilePath == null) return;

    if (Config.aapt2Path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.loc.tint_set_aapt2_path)));
      return;
    }

    setState(() {
      apkInfo?.reset();
      _isParsing = true;
    });

    try {
      final apkInfo = await getApkInfo(selectedFilePath!);
      if (apkInfo != null && Config.enableSignature) {
        // 获取签名信息
        try {
          final signatureInfo = await getSignatureInfo(selectedFilePath!);
          apkInfo.signatureInfo = signatureInfo;
        } catch (e) {
          // 显示签名验证失败提示
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.loc.signature_verify_failed)));
          }
        }
      }
      if (!mounted) return;

      setState(() {
        this.apkInfo = apkInfo;
        _isParsing = false;
      });

      if (apkInfo == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.loc.warn_parse_apk_info_fail)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isParsing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.loc.warn_parse_apk_info_fail)),
      );
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

  // 构建文件操作菜单
  Widget _buildFileActionMenu() {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_vert, size: 18),
      enabled: selectedFilePath != null,
      // 设置菜单位置在按钮下方
      offset: const Offset(0, 0),
      position: PopupMenuPosition.under,
      // 设置菜单项更紧凑
      itemBuilder: (context) => [
        PopupMenuItem(
          height: 32, // 减小高度
          padding: const EdgeInsets.symmetric(horizontal: 8), // 减小水平内边距
          value: 'open_directory',
          child: Row(
            mainAxisSize: MainAxisSize.min, // 使Row更紧凑
            children: [
              const Icon(Icons.folder_open, size: 16), // 减小图标大小
              const SizedBox(width: 8),
              Text(
                context.loc.open_file_directory,
                style: const TextStyle(fontSize: 12), // 减小字体大小
              ),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        if (value == 'open_directory' && selectedFilePath != null) {
          openFileInExplorer(selectedFilePath!);
        }
      },
    );
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
                Navigator.pushNamed(context, 'setting').then((value) {
                  // 返回时刷新
                  setState(() {});
                });
              }),
          // 最右的空间
          const SizedBox(width: 50),
        ],
      ),
      body: Stack(
        children: [
          DropTarget(
            onDragDone: (details) {
              // 只处理第一个文件
              if (details.files.isNotEmpty) {
                final file = details.files.first;
                if (file.path.toLowerCase().endsWith('.apk')) {
                  setState(() {
                    selectedFilePath = file.path;
                    loadApkInfo();
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.loc.select_apk_file),
                    ),
                  );
                }
              }
            },
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Padding(
                        // 指定上下左右的内边距为 10 像素
                        padding: const EdgeInsets.only(left: 10, right: 10),
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            Card(
                                child: TitleValueRow(
                                    title: context.loc.file,
                                    value: selectedFilePath ?? "",
                                    end: _buildFileActionMenu())),
                            Card(
                                child: TitleValueRow(
                                    title: context.loc.size,
                                    value: fileSize != null
                                        ? "${formatFileSize(fileSize)} ($fileSize Bytes)"
                                        : "")),
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
                                      value: getSdkVersionText(
                                          apkInfo?.sdkVersion),
                                      titleFlex: 6),
                                )),
                                Expanded(
                                    child: Card(
                                        child: TitleValueRow(
                                            title: context.loc.target_sdk,
                                            value: getSdkVersionText(
                                                apkInfo?.targetSdkVersion),
                                            titleFlex: 6))),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                    child: Card(
                                        child: TitleValueRow(
                                            title: context.loc.version_code,
                                            value:
                                                "${apkInfo?.versionCode ?? ""}",
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
                                    value: apkInfo?.supportsScreens.join(" ") ??
                                        "")),
                            Card(
                                child: TitleValueRow(
                                    title: context.loc.screen_density,
                                    value: apkInfo?.densities.join(" ") ?? "")),
                            Card(
                                child: TitleValueRow(
                                    title: context.loc.abi,
                                    value:
                                        apkInfo?.nativeCodes.join(" ") ?? "")),
                            Card(
                                child: TitleValueRow(
                                    title: context.loc.language_list,
                                    value: apkInfo?.locales.join(" ") ?? "")),
                            Card(
                                child: TitleValueRow(
                              title: context.loc.perm_list,
                              value: apkInfo?.usesPermissions.join("\n") ?? "",
                              minLines: 1,
                              maxLines: Config.maxLines,
                            )),
                            if (Config.enableSignature)
                              Card(
                                  child: TitleValueRow(
                                title: context.loc.signature_info,
                                value: apkInfo?.signatureInfo ?? "",
                                minLines: 1,
                                maxLines: Config.maxLines,
                              )),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 解析状态指示器
          if (_isParsing)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(context.loc.parsing),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
