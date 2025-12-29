import 'dart:io';

import 'package:apk_info_tool/apkparser/apk_info.dart';
import 'package:apk_info_tool/gen/strings.g.dart';
import 'package:apk_info_tool/main.dart';
import 'package:apk_info_tool/pages/install_dialog.dart';
import 'package:apk_info_tool/pages/pages.dart';
import 'package:apk_info_tool/pages/text_info.dart';
import 'package:apk_info_tool/providers/home_page_provider.dart';
import 'package:apk_info_tool/providers/info_page_provider.dart';
import 'package:apk_info_tool/providers/setting_provider.dart';
import 'package:apk_info_tool/providers/ui_config_provider.dart';
import 'package:apk_info_tool/utils/android_version.dart';
import 'package:apk_info_tool/utils/format.dart';
import 'package:apk_info_tool/utils/logger.dart';
import 'package:apk_info_tool/utils/platform.dart';
import 'package:apk_info_tool/widgets/title_value_layout.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

class APKInfoPage extends ConsumerStatefulWidget implements PageBase {
  const APKInfoPage({super.key});

  @override
  ConsumerState<APKInfoPage> createState() => _APKInfoPageState();

  @override
  Pages get page => Pages.info;
}

class _APKInfoPageState extends ConsumerState<APKInfoPage> {
  void openFilePicker() async {
    var result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      dialogTitle: t.open.select_apk_file,
      allowedExtensions: ['apk', 'xapk', 'apkm', 'apks'],
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
    final file = File(path);
    final state = ref.read(currentFileStateProvider.notifier);
    if (file.existsSync()) {
      final fileSize = file.lengthSync();
      state.update(FileState(filePath: path, fileSize: fileSize));
      if (path.isNotEmpty) {
        loadApkInfo(path);
      }
    } else {
      state.update(FileState(filePath: path));
    }
  }

  void closeApk() {
    ref.read(currentFileStateProvider.notifier).update(FileState());
    ref.read(currentApkInfoProvider.notifier).reset();
  }

  String getSdkVersionText(int? sdkVersion) {
    if (sdkVersion == null) return "";
    return "$sdkVersion (${AndroidVersion.getAndroidVersion(sdkVersion)})";
  }

  Future<void> loadApkInfo(String filePath) async {
    final apkInfoState = ref.read(currentApkInfoProvider.notifier);
    final isParsingState = ref.read(isParsingProvider.notifier);
    final fileState = ref.read(currentFileStateProvider.notifier);
    final enableSignature =
        ref.read(settingStateProvider.select((value) => value.enableSignature));
    apkInfoState.reset();
    isParsingState.update(true);
    try {
      final apkInfo = await getApkInfo(filePath);
      if (apkInfo != null) {
        if (enableSignature &&
            !apkInfo.isXapk &&
            apkInfo.signatureInfo.isEmpty) {
          // 获取签名信息
          try {
            final signatureInfo = await getSignatureInfo(filePath);
            apkInfo.signatureInfo = signatureInfo;
          } catch (e) {
            // 显示签名验证失败提示
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(t.parse.signature_verify_failed)));
            }
          }
        }
        apkInfoState.update(apkInfo);
        // 更新 FileState 中的 apkInfo
        fileState.update(FileState(
          filePath: filePath,
          fileSize: File(filePath).lengthSync(),
          apkInfo: apkInfo,
        ));
      }
    } catch (e) {
      log.warning('loadApkInfo: $e');
      if (mounted) {
        final message = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      isParsingState.update(false);
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
    // 延时以保证初始化一次
    Future.delayed(Duration.zero).then((value) {
      updateActions();
    });
    log.info("initState apkByArgs=$apkByArgs");
    if (Platform.isMacOS) {
      _initPlatformState();
      _setupFileAssociationHandler();
    } else if (apkByArgs.isNotEmpty) {
      openApk(apkByArgs);
    }
  }

  List<Widget> _buildActions(FileState fileState) {
    return [
      IconButton(
          icon: const Icon(Icons.file_open),
          tooltip: t.open.open_apk,
          onPressed: () async {
            openFilePicker();
          }),
      IconButton(
          icon: const Icon(Icons.search),
          tooltip: t.parse.parse_apk,
          onPressed: fileState.filePath == null
              ? null
              : () {
                  openApk(fileState.filePath ?? '');
                }),
      IconButton(
          icon: const Icon(Icons.install_mobile),
          tooltip: t.install.apk,
          onPressed: fileState.filePath == null
              ? null
              : () {
                  showDialog(
                    context: context,
                    builder: (context) => InstallDialog(
                      apkPath: fileState.filePath!,
                      isXapk: fileState.apkInfo?.isXapk ?? false,
                    ),
                  );
                }),
      _buildMoreMenuButton(context),
      IconButton(
          icon: const Icon(Icons.settings),
          tooltip: t.settings.open_settings,
          onPressed: () {
            Navigator.pushNamed(context, 'setting');
          }),
    ];
  }

  PopupMenuItem<String> _buildMenuItem(
      String value, IconData icon, String title,
      {bool enabled = true}) {
    return PopupMenuItem(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        value: value,
        enabled: enabled,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ));
  }

  // 构建文件操作菜单
  Widget _buildFileActionMenu() {
    final fileState = ref.watch(currentFileStateProvider);
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_vert, size: 18),
      enabled: fileState.filePath != null,
      // 设置菜单位置在按钮下方
      offset: const Offset(0, 0),
      position: PopupMenuPosition.under,
      // 设置菜单项更紧凑
      itemBuilder: (context) => [
        _buildMenuItem(
            'open_directory', Icons.folder_open, t.open.open_file_directory),
        _buildMenuItem('copy_path', Icons.content_copy, t.home.copy_file_path),
      ],
      onSelected: onMenuActionSelected,
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
    // 在当前页/文件/APK信息变化时需要更新Actions, 因为Actions的变化会修改按钮的使能状态
    ref.listen(currentPageProvider, (_, __) => updateActions());
    ref.listen(currentFileStateProvider, (_, __) => updateActions());
    ref.listen(currentApkInfoProvider, (_, __) => updateActions());
    final apkInfo = ref.watch(currentApkInfoProvider);
    final fileState = ref.watch(currentFileStateProvider);
    final isParsing = ref.watch(isParsingProvider);
    final enableSignature = ref
        .watch(settingStateProvider.select((value) => value.enableSignature));
    final textMaxLines =
        ref.watch(uiConfigStateProvider.select((value) => value.textMaxLines));

    return Stack(
      children: [
        DropTarget(
          onDragDone: (details) {
            // 只处理第一个文件
            if (details.files.isNotEmpty) {
              final file = details.files.first;
              final extension = file.path.toLowerCase();
              if (extension.endsWith('.apk') ||
                  extension.endsWith('.xapk') ||
                  extension.endsWith('.apkm') ||
                  extension.endsWith('.apks')) {
                openApk(file.path);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(t.open.invalid_file_type),
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
                                  value: fileState.filePath ?? "",
                                  end: _buildFileActionMenu())),
                          Card(
                              child: TitleValueLayout(
                            title: t.file_info.size,
                            value: fileState.fileSize != null
                                ? "${formatFileSize(fileState.fileSize)} (${fileState.fileSize} Bytes)"
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
                                if (apkInfo?.isXapk ?? false)
                                  Card(
                                      child: TitleValueLayout(
                                    title: t.apk_info.archive_type,
                                    value: apkInfo?.archiveType ?? "",
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
                            value: getSdkVersionText(apkInfo?.targetSdkVersion),
                          )),
                          if (apkInfo?.isXapk ?? false)
                            Card(
                                child: TitleValueLayout(
                              title: t.apk_info.split_apks,
                              value: apkInfo?.splitApks.join("\n") ?? "",
                              minLines: 1,
                              maxLines: textMaxLines,
                              selectable: true,
                            )),
                          if ((apkInfo?.obbFiles.isNotEmpty ?? false))
                            Card(
                                child: TitleValueLayout(
                              title: t.apk_info.obb_files,
                              value: apkInfo?.obbFiles.join("\n") ?? "",
                              minLines: 1,
                              maxLines: textMaxLines,
                              selectable: true,
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
                            maxLines: textMaxLines,
                            selectable: true,
                          )),
                          if (enableSignature && !(apkInfo?.isXapk ?? false))
                            Card(
                                child: TitleValueLayout(
                              title: t.apk_info.signature_info,
                              value: apkInfo?.signatureInfo ?? "",
                              minLines: 1,
                              maxLines: textMaxLines,
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
        if (isParsing)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
    );
  }

  PopupMenuButton<String> _buildMoreMenuButton(BuildContext context) {
    final apkInfo = ref.watch(currentApkInfoProvider);
    final state = ref.watch(currentFileStateProvider);
    log.info(
        "_buildMoreMenuButton: state.filePath=${state.filePath}, apkInfo=$apkInfo");
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz),
      tooltip: t.home.more_actions,
      enabled: state.filePath != null,
      offset: const Offset(0, 0),
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        _buildMenuItem(
            'rename', Icons.drive_file_rename_outline, t.rename.rename_file,
            enabled: state.filePath != null),
        _buildMenuItem('text_info', Icons.text_snippet, t.apk_info.text_info,
            enabled: state.filePath != null && apkInfo != null),
        _buildMenuItem('close_file', Icons.close, t.open.close_file,
            enabled: state.filePath != null),
      ],
      onSelected: onMenuActionSelected,
    );
  }

  // 显示重命名对话框
  void _showRenameDialog() {
    final apkInfo = ref.read(currentApkInfoProvider);
    final state = ref.read(currentFileStateProvider);
    if (state.filePath == null || apkInfo == null) return;

    final fileName = apkInfo.label ?? '';
    final versionName = apkInfo.versionName ?? '';
    final extension = path.extension(state.filePath!).toLowerCase();
    final targetExtension = extension.isNotEmpty ? extension : '.apk';
    final defaultName = '$fileName-$versionName$targetExtension';

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
                if (!(value.toLowerCase().endsWith('.apk') ||
                    value.toLowerCase().endsWith('.xapk') ||
                    value.toLowerCase().endsWith('.apkm') ||
                    value.toLowerCase().endsWith('.apks'))) {
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
                    controller.text = '$fileName$targetExtension';
                  },
                  child: Text(t.rename.app_name_only),
                ),
                OutlinedButton(
                  onPressed: () {
                    controller.text = '$fileName-v$versionName$targetExtension';
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
                final oldFile = File(state.filePath!);
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

  void updateActions() {
    final page = ref.read(currentPageProvider);
    final fileState = ref.read(currentFileStateProvider);
    if (page == widget.page) {
      ref
          .read(pageActionsProvider.notifier)
          .setActions(_buildActions(fileState));
    }
  }

  void onMenuActionSelected(String value) async {
    switch (value) {
      case 'close_file':
        closeApk();
        break;
      case 'rename':
        _showRenameDialog();
        break;
      case 'text_info':
        final apkInfo = ref.read(currentApkInfoProvider);
        if (apkInfo != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TextInfoPage(
                text: apkInfo.originalText,
              ),
            ),
          );
        }
        break;
      case 'open_directory':
        final fileState = ref.read(currentFileStateProvider);
        openFileInExplorer(fileState.filePath!);
        break;
      case 'copy_path':
        final fileState = ref.read(currentFileStateProvider);
        await Clipboard.setData(ClipboardData(text: fileState.filePath!));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  t.home.copied_content(content: fileState.filePath ?? '')),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        break;
    }
  }
}
