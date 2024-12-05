import 'dart:io';

import 'package:apk_info_tool/gen/strings.g.dart';
import 'package:apk_info_tool/pages/text_info.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../apk_info.dart';
import '../config.dart';
import '../main.dart';
import '../utils/android_version.dart';
import '../utils/format.dart';
import '../utils/logger.dart';
import '../utils/platform.dart';
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
      dialogTitle: t.open.select_apk_file,
      allowedExtensions: ['apk'],
      lockParentWindow: true,
    );
    log.fine('openFilePicker: result=$result');
    var file = result?.files.single;
    // 打开文件选择
    if (file != null) {
      log.fine('openFilePicker: filePaths=$file');
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
                SnackBar(content: Text(t.parse.signature_verify_failed)));
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
          SnackBar(content: Text(t.parse.parse_apk_info_fail)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isParsing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.parse.parse_apk_info_fail)),
      );
    }
  }

  Future<void> _initPlatformState() async {
    log.info("_initPlatformState: start");
    String? initialFilePath;
    try {
      // 使用方法通道获取文件路径
      initialFilePath = await const MethodChannel('file_association')
          .invokeMethod('getInitialFilePath');
    } on PlatformException catch (e) {
      log.info("PlatformException: $e");
      initialFilePath = null;
    }

    log.info("_initPlatformState: initialFilePath=$initialFilePath");
    if (!mounted) return;

    if (initialFilePath != null && initialFilePath.isNotEmpty) {
      openApk(initialFilePath);
    }
  }

  void _setupFileAssociationHandler() {
    const MethodChannel('file_association').setMethodCallHandler((call) async {
      log.info("_setupFileAssociationHandler: call.method=${call.method}");
      if (call.method == 'fileOpened') {
        openApk(call.arguments);
      }
      return null;
    });
  }

  @override
  void initState() {
    super.initState();
    log.info("initState apkByArgs=$apkByArgs");
    if (Platform.isMacOS) {
      _initPlatformState();
      _setupFileAssociationHandler();
    } else if (apkByArgs.isNotEmpty) {
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
                t.open.open_file_directory,
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
                t.home.copy_file_path,
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
                  content: Text(
                      t.home.copied_content(content: selectedFilePath ?? '')),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
            break;
        }
      },
    );
  }

  // 构建复制按钮
  Widget _buildCopyButton(String? text, bool enable) {
    return Tooltip(
      message: t.home.copy_content,
      waitDuration: const Duration(seconds: 1),
      textStyle: TextStyle(
        color: Colors.white,
        fontSize: 12,
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
                      content: Text(t.home.copied_content(content: text ?? '')),
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
        title: Text(t.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
              icon: const Icon(Icons.folder),
              tooltip: t.open.open_apk,
              onPressed: () async {
                openFilePicker();
              }),
          IconButton(
              icon: const Icon(Icons.search),
              tooltip: t.parse.parse_apk,
              onPressed: selectedFilePath == null
                  ? null
                  : () {
                      openApk(selectedFilePath ?? '');
                    }),
          IconButton(
              icon: const Icon(Icons.android),
              tooltip: t.install.apk,
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
          _buildMoreMenuButton(context),
          IconButton(
              icon: const Icon(Icons.settings),
              tooltip: t.settings.open_settings,
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
                      content: Text(t.open.select_apk_file),
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
                                    title: t.file_info.file,
                                    value: selectedFilePath ?? "",
                                    end: _buildFileActionMenu())),
                            Card(
                                child: TitleValueLayout(
                              title: t.file_info.size,
                              value: fileSize != null
                                  ? "${formatFileSize(fileSize)} ($fileSize Bytes)"
                                  : "",
                            )),
                            Card(
                                child: TitleValueLayout(
                              title: t.apk_info.app_name,
                              value: apkInfo?.label ?? "",
                              end: _buildCopyButton(
                                  apkInfo?.label, apkInfo?.label != null),
                            )),
                            Card(
                                child: TitleValueLayout(
                              title: t.apk_info.package_name,
                              value: apkInfo?.packageName ?? "",
                              end: _buildCopyButton(apkInfo?.packageName,
                                  apkInfo?.packageName != null),
                            )),
                            Row(children: [
                              Expanded(
                                  child: Column(
                                children: [
                                  Card(
                                      child: TitleValueLayout(
                                    title: t.apk_info.version_code,
                                    value: "${apkInfo?.versionCode ?? ""}",
                                  )),
                                  Card(
                                      child: TitleValueLayout(
                                    title: t.apk_info.version_name,
                                    value: apkInfo?.versionName ?? "",
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
                                title: t.apk_info.min_sdk,
                                value: getSdkVersionText(apkInfo?.sdkVersion),
                              ),
                            ),
                            Card(
                                child: TitleValueLayout(
                              title: t.apk_info.target_sdk,
                              value:
                                  getSdkVersionText(apkInfo?.targetSdkVersion),
                            )),
                            Card(
                                child: TitleValueLayout(
                              title: t.apk_info.screen_size,
                              value: apkInfo?.supportsScreens.join(" ") ?? "",
                            )),
                            Card(
                                child: TitleValueLayout(
                              title: t.apk_info.screen_density,
                              value: apkInfo?.densities.join(" ") ?? "",
                            )),
                            Card(
                                child: TitleValueLayout(
                              title: t.apk_info.abi,
                              value: apkInfo?.nativeCodes.join(" ") ?? "",
                            )),
                            Card(
                                child: TitleValueLayout(
                              title: t.apk_info.languages,
                              value: apkInfo?.locales.join(" ") ?? "",
                            )),
                            Card(
                                child: TitleValueLayout(
                              title: t.apk_info.permissions,
                              value: apkInfo?.usesPermissions.join("\n") ?? "",
                              minLines: 1,
                              maxLines: Config.maxLines,
                              selectable: true,
                            )),
                            if (Config.enableSignature)
                              Card(
                                  child: TitleValueLayout(
                                title: t.apk_info.signature_info,
                                value: apkInfo?.signatureInfo ?? "",
                                minLines: 1,
                                maxLines: Config.maxLines,
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
                    Text(t.parse.parsing),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  PopupMenuButton<String> _buildMoreMenuButton(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz),
      tooltip: t.home.more_actions,
      enabled: selectedFilePath != null,
      offset: const Offset(0, 0),
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        PopupMenuItem(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          value: 'rename',
          enabled: selectedFilePath != null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.drive_file_rename_outline, size: 16),
              const SizedBox(width: 8),
              Text(
                t.rename.rename_file,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          value: 'text_info',
          enabled: selectedFilePath != null && apkInfo != null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.text_snippet, size: 16),
              const SizedBox(width: 8),
              Text(
                t.apk_info.text_info,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'rename':
            _showRenameDialog();
            break;
          case 'text_info':
            if (apkInfo != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TextInfoPage(
                    text: apkInfo!.originalText,
                  ),
                ),
              );
            }
            break;
        }
      },
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
        title: Text(t.rename.rename_file),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: controller,
              decoration: InputDecoration(
                labelText: t.rename.new_file_name,
                suffixText: '',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return t.rename.name_cannot_be_empty;
                }
                if (!value.toLowerCase().endsWith('.apk')) {
                  return t.rename.must_end_with_apk;
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
                  child: Text(t.rename.default_name),
                ),
                OutlinedButton(
                  onPressed: () {
                    controller.text = '$fileName.apk';
                  },
                  child: Text(t.rename.app_name_only),
                ),
                OutlinedButton(
                  onPressed: () {
                    controller.text = '$fileName-v$versionName.apk';
                  },
                  child: Text(t.rename.name_with_version),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.base.cancel),
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
                    SnackBar(content: Text(t.rename.success)),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${t.rename.failed}: $e')),
                  );
                }
              }
            },
            child: Text(t.base.confirm),
          ),
        ],
      ),
    );
  }
}
