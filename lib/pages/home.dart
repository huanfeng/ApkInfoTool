import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/services.dart';

import '../apk_info.dart';
import '../config.dart';
import '../main.dart';
import '../utils/local.dart';
import '../utils/log.dart';
import '../utils/platform.dart';
import '../utils/android_version.dart';
import '../utils/format.dart';
import '../widgets/title_value_layout.dart';
import './install_dialog.dart';

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
  var titleWidth = Config.titleWidth;

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
        openApk(file.path!);
      }
    }
  }

  void openApk(String path) {
    setState(() {
      final file = File(path);
      selectedFilePath = path;
      if (file.existsSync()) {
        fileSize = file.lengthSync();
        if (selectedFilePath != null && selectedFilePath!.isNotEmpty) {
          loadApkInfo();
        }
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
    log("initState apkByArgs=$apkByArgs");
    if (apkByArgs.isNotEmpty) {
      openApk(apkByArgs);
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
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          value: 'open_directory',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_open, size: 16),
              const SizedBox(width: 8),
              Text(
                context.loc.open_file_directory,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          value: 'copy_path',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.content_copy, size: 16),
              const SizedBox(width: 8),
              Text(
                context.loc.copy_file_path,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          value: 'rename',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.drive_file_rename_outline, size: 16),
              const SizedBox(width: 8),
              Text(
                context.loc.rename_file,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
      onSelected: (value) async {
        if (selectedFilePath == null) return;

        switch (value) {
          case 'open_directory':
            openFileInExplorer(selectedFilePath!);
            break;
          case 'copy_path':
            await Clipboard.setData(ClipboardData(text: selectedFilePath!));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      Text(context.loc.copied_content(selectedFilePath ?? '')),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
            break;
          case 'rename':
            _showRenameDialog();
            break;
        }
      },
    );
  }

  // 构建复制按钮
  Widget _buildCopyButton(String? text, bool enable) {
    return Tooltip(
      message:
          enable ? context.loc.copy_content : context.loc.copy_content_disabled,
      waitDuration: const Duration(seconds: 1),
      textStyle: TextStyle(
        color: Colors.white,
        fontSize: 14,
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
        icon: Icon(
          Icons.content_copy,
          size: 16,
          color: enable ? null : Theme.of(context).disabledColor,
        ),
        onPressed: enable
            ? () async {
                await Clipboard.setData(ClipboardData(text: text ?? ''));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.loc.copied_content(text ?? '')),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }
            : null,
      ),
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
                openApk(selectedFilePath ?? '');
              }),
          IconButton(
              icon: const Icon(Icons.android),
              tooltip: context.loc.install_apk,
              onPressed: selectedFilePath == null
                  ? null
                  : () {
                      showDialog(
                        context: context,
                        builder: (context) => InstallDialog(
                          apkPath: selectedFilePath!,
                        ),
                      );
                    }),
          IconButton(
              icon: const Icon(Icons.settings),
              tooltip: context.loc.setting,
              onPressed: () {
                Navigator.pushNamed(context, 'setting').then((value) {
                  // 返回时刷新
                  setState(() {
                    titleWidth = Config.titleWidth;
                  });
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
                    openApk(file.path);
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
                                child: TitleValueLayout(
                                    title: context.loc.file,
                                    value: selectedFilePath ?? "",
                                    end: _buildFileActionMenu(),
                                    titleWidth: titleWidth)),
                            Card(
                                child: TitleValueLayout(
                                    title: context.loc.size,
                                    value: fileSize != null
                                        ? "${formatFileSize(fileSize)} ($fileSize Bytes)"
                                        : "",
                                    titleWidth: titleWidth)),
                            Card(
                                child: TitleValueLayout(
                                    title: context.loc.app_name,
                                    value: apkInfo?.label ?? "",
                                    end: _buildCopyButton(
                                        apkInfo?.label, apkInfo?.label != null),
                                    titleWidth: titleWidth)),
                            Card(
                                child: TitleValueLayout(
                                    title: context.loc.package_name,
                                    value: apkInfo?.packageName ?? "",
                                    end: _buildCopyButton(apkInfo?.packageName,
                                        apkInfo?.packageName != null),
                                    titleWidth: titleWidth)),
                            Row(children: [
                              Expanded(
                                  child: Column(
                                children: [
                                  Card(
                                      child: TitleValueLayout(
                                    title: context.loc.version_code,
                                    value: "${apkInfo?.versionCode ?? ""}",
                                    titleWidth: titleWidth,
                                  )),
                                  Card(
                                      child: TitleValueLayout(
                                    title: context.loc.version_name,
                                    value: apkInfo?.versionName ?? "",
                                    titleWidth: titleWidth,
                                  )),
                                ],
                              )),
                              Card(
                                  child: Container(
                                margin: const EdgeInsets.all(4),
                                width: 72,
                                height: 72,
                                child: RawImage(
                                  image: apkInfo?.mainIconImage,
                                  fit: BoxFit.contain,
                                ),
                              )),
                            ]),
                            Card(
                              child: TitleValueLayout(
                                  title: context.loc.min_sdk,
                                  value: getSdkVersionText(apkInfo?.sdkVersion),
                                  titleWidth: titleWidth),
                            ),
                            Card(
                                child: TitleValueLayout(
                                    title: context.loc.target_sdk,
                                    value: getSdkVersionText(
                                        apkInfo?.targetSdkVersion),
                                    titleWidth: titleWidth)),
                            Card(
                                child: TitleValueLayout(
                                    title: context.loc.screen_size,
                                    value: apkInfo?.supportsScreens.join(" ") ??
                                        "",
                                    titleWidth: titleWidth)),
                            Card(
                                child: TitleValueLayout(
                                    title: context.loc.screen_density,
                                    value: apkInfo?.densities.join(" ") ?? "",
                                    titleWidth: titleWidth)),
                            Card(
                                child: TitleValueLayout(
                                    title: context.loc.abi,
                                    value: apkInfo?.nativeCodes.join(" ") ?? "",
                                    titleWidth: titleWidth)),
                            Card(
                                child: TitleValueLayout(
                                    title: context.loc.language_list,
                                    value: apkInfo?.locales.join(" ") ?? "",
                                    titleWidth: titleWidth)),
                            Card(
                                child: TitleValueLayout(
                              title: context.loc.perm_list,
                              value: apkInfo?.usesPermissions.join("\n") ?? "",
                              minLines: 1,
                              maxLines: Config.maxLines,
                              titleWidth: titleWidth,
                              selectable: true,
                            )),
                            if (Config.enableSignature)
                              Card(
                                  child: TitleValueLayout(
                                title: context.loc.signature_info,
                                value: apkInfo?.signatureInfo ?? "",
                                minLines: 1,
                                maxLines: Config.maxLines,
                                titleWidth: titleWidth,
                                selectable: true,
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

  // 显示重命名对话框
  void _showRenameDialog() {
    if (selectedFilePath == null || apkInfo == null) return;

    final fileName = apkInfo!.label ?? '';
    final versionName = apkInfo!.versionName ?? '';
    final defaultName = '$fileName-$versionName.apk';

    final controller = TextEditingController(text: defaultName);
    final formKey = GlobalKey<FormFieldState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.loc.rename_file),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: controller,
              decoration: InputDecoration(
                labelText: context.loc.new_file_name,
                suffixText: '',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return context.loc.file_name_cannot_be_empty;
                }
                if (!value.toLowerCase().endsWith('.apk')) {
                  return context.loc.file_must_end_with_apk;
                }
                return null;
              },
              key: formKey,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () {
                    controller.text = defaultName;
                  },
                  child: Text(context.loc.default_name),
                ),
                OutlinedButton(
                  onPressed: () {
                    controller.text = '$fileName.apk';
                  },
                  child: Text(context.loc.app_name_only),
                ),
                OutlinedButton(
                  onPressed: () {
                    controller.text = '$fileName-v$versionName.apk';
                  },
                  child: Text(context.loc.name_with_version),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.loc.cancel),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                final newName = controller.text;
                final oldFile = File(selectedFilePath!);
                final directory = oldFile.parent;
                final newPath =
                    '${directory.path}${Platform.pathSeparator}$newName';

                try {
                  oldFile.renameSync(newPath);
                  // 更新当前文件路径
                  openApk(newPath);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.loc.rename_success)),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${context.loc.rename_failed}: $e')),
                  );
                }
              }
            },
            child: Text(context.loc.confirm),
          ),
        ],
      ),
    );
  }
}
