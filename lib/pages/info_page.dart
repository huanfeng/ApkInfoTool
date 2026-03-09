import 'dart:io';
import 'dart:ui' as ui;

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
import 'package:apk_info_tool/utils/file_hash.dart';
import 'package:apk_info_tool/utils/format.dart';
import 'package:apk_info_tool/utils/logger.dart';
import 'package:apk_info_tool/utils/platform.dart';
import 'package:apk_info_tool/utils/zip_helper.dart';
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
      allowedExtensions: ['apk', 'xapk', 'apkm', 'apks', 'apk.1', 'apk.1.1'],
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
    ref.read(selectedIconIndexProvider.notifier).reset();
    ref.read(selectedLabelLocaleProvider.notifier).reset();
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
    final enableHash =
        ref.read(settingStateProvider.select((value) => value.enableHash));
    apkInfoState.reset();
    ref.read(selectedIconIndexProvider.notifier).reset();
    ref.read(selectedLabelLocaleProvider.notifier).reset();
    isParsingState.update(true);

    // 初始化文件状态
    final isXapk = filePath.toLowerCase().endsWith('.xapk');
    fileState.update(FileState(
      filePath: filePath,
      fileSize: File(filePath).lengthSync(),
      isComputingHash: enableHash,
      isComputingSignature: enableSignature && !isXapk,
    ));

    // 如果启用哈希计算，异步计算哈希值（与 APK 解析并行）
    if (enableHash) {
      computeFileHashes(filePath).then((hashes) {
        if (mounted) {
          final currentState = ref.read(currentFileStateProvider);
          fileState.update(currentState.copyWith(
            md5Hash: hashes.$1,
            sha1Hash: hashes.$2,
            isComputingHash: false,
          ));
        }
      }).catchError((e) {
        log.warning('loadApkInfo: failed to compute hashes: $e');
        if (mounted) {
          final currentState = ref.read(currentFileStateProvider);
          fileState.update(currentState.copyWith(
            isComputingHash: false,
          ));
        }
      });
    }

    // 如果启用签名检查，异步获取签名信息（与 APK 解析并行）
    if (enableSignature && !isXapk) {
      getSignatureInfo(filePath).then((signatureInfo) {
        if (mounted) {
          final currentState = ref.read(currentFileStateProvider);
          fileState.update(currentState.copyWith(
            signatureInfo: signatureInfo,
            isComputingSignature: false,
          ));
        }
      }).catchError((e) {
        log.warning('loadApkInfo: failed to get signature: $e');
        if (mounted) {
          final currentState = ref.read(currentFileStateProvider);
          fileState.update(currentState.copyWith(
            signatureInfo: "${t.parse.signature_verify_failed}: $e",
            isComputingSignature: false,
          ));
        }
      });
    }

    try {
      final apkInfo = await getApkInfo(filePath);
      if (apkInfo == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.parse.parse_apk_info_fail)),
          );
        }
      } else {
        apkInfoState.update(apkInfo);
        // 更新 FileState 中的 apkInfo（保留哈希值）
        final currentState = ref.read(currentFileStateProvider);
        fileState.update(currentState.copyWith(
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

  /// 获取当前显示的应用名称（根据用户选择的语言）
  String _getDisplayLabel(ApkInfo? apkInfo) {
    if (apkInfo == null) return "";
    final selectedLocale = ref.read(selectedLabelLocaleProvider);
    if (selectedLocale != null && apkInfo.labels.containsKey(selectedLocale)) {
      return apkInfo.labels[selectedLocale]!;
    }
    return apkInfo.label ?? "";
  }

  static const _kDefaultLocale = '__default__';

  /// 构建应用名称语言切换菜单按钮
  Widget _buildLabelLocaleMenu(ApkInfo? apkInfo) {
    final hasLabels = apkInfo != null && apkInfo.labels.isNotEmpty;
    final selectedLocale = ref.watch(selectedLabelLocaleProvider);
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.translate,
        size: 16,
        color: hasLabels
            ? (selectedLocale != null
                ? Theme.of(context).colorScheme.primary
                : null)
            : Theme.of(context).disabledColor,
      ),
      tooltip: t.apk_info.switch_label_language,
      enabled: hasLabels,
      offset: const Offset(0, 0),
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(maxHeight: 400, maxWidth: 300),
      itemBuilder: (context) {
        if (apkInfo == null) return [];
        final colorScheme = Theme.of(context).colorScheme;
        final items = <PopupMenuEntry<String>>[];
        // 默认名称选项
        items.add(PopupMenuItem<String>(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          value: _kDefaultLocale,
          child: Row(
            children: [
              if (selectedLocale == null)
                Icon(Icons.check, size: 14, color: colorScheme.primary)
              else
                const SizedBox(width: 14),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('default',
                    style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onPrimaryContainer)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(apkInfo.label ?? '',
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ));
        items.add(const PopupMenuDivider(height: 1));
        // 各语言选项
        final sortedEntries = apkInfo.labels.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        for (final entry in sortedEntries) {
          // 跳过与默认名称相同的条目
          if (entry.value == apkInfo.label) continue;
          items.add(PopupMenuItem<String>(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            value: entry.key,
            child: Row(
              children: [
                if (selectedLocale == entry.key)
                  Icon(Icons.check, size: 14, color: colorScheme.primary)
                else
                  const SizedBox(width: 14),
                const SizedBox(width: 8),
                Container(
                  width: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(entry.key,
                      style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(entry.value,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ));
        }
        return items;
      },
      onSelected: (locale) {
        ref.read(selectedLabelLocaleProvider.notifier).select(
            locale == _kDefaultLocale ? null : locale);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 在当前页/文件/APK信息变化时需要更新Actions, 因为Actions的变化会修改按钮的使能状态
    // 使用微任务合并连续变化，避免同一帧内多次重建 actions
    ref.listen(currentPageProvider, (_, __) => _scheduleUpdateActions());
    ref.listen(currentFileStateProvider, (_, __) => _scheduleUpdateActions());
    ref.listen(currentApkInfoProvider, (_, __) => _scheduleUpdateActions());
    final apkInfo = ref.watch(currentApkInfoProvider);
    final fileState = ref.watch(currentFileStateProvider);
    final isParsing = ref.watch(isParsingProvider);
    final enableSignature = ref
        .watch(settingStateProvider.select((value) => value.enableSignature));
    final enableHash = ref
        .watch(settingStateProvider.select((value) => value.enableHash));
    final textMaxLines =
        ref.watch(uiConfigStateProvider.select((value) => value.textMaxLines));
    final iconRowSpan =
        ref.watch(uiConfigStateProvider.select((value) => value.iconRowSpan));

    return Stack(
      children: [
        DropTarget(
          onDragDone: (details) {
            // 只处理第一个文件
            if (details.files.isNotEmpty) {
              final file = details.files.first;
              final lowered = file.path.toLowerCase();
              if (lowered.endsWith('.apk') ||
                  lowered.endsWith('.xapk') ||
                  lowered.endsWith('.apkm') ||
                  lowered.endsWith('.apks') ||
                  lowered.endsWith('.zip') ||
                  RegExp(r'\.(apk|xapk|apkm|apks)(\.\d+)+$')
                      .hasMatch(lowered)) {
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
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
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
                            value: _getDisplayLabel(apkInfo),
                            end: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildLabelLocaleMenu(apkInfo),
                                _buildCopyButton(
                                    _getDisplayLabel(apkInfo),
                                    apkInfo?.label != null),
                              ],
                            ),
                          )),
                          Card(
                              child: TitleValueLayout(
                            title: t.apk_info.package_name,
                            value: apkInfo?.packageName ?? "",
                            end: _buildCopyButton(apkInfo?.packageName,
                                apkInfo?.packageName != null),
                          )),
                          Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                  child: Column(
                                children: [
                                  Card(
                                      child: TitleValueLayout(
                                    title: t.apk_info.version_code,
                                    value:
                                        "${apkInfo?.versionCode ?? ""}",
                                  )),
                                  Card(
                                      child: TitleValueLayout(
                                    title: t.apk_info.version_name,
                                    value: apkInfo?.versionName ?? "",
                                  )),
                                  if (iconRowSpan >= 3)
                                    Card(
                                      child: TitleValueLayout(
                                        title: t.apk_info.min_sdk,
                                        value: getSdkVersionText(
                                            apkInfo?.sdkVersion),
                                      ),
                                    ),
                                  if (apkInfo?.isXapk ?? false)
                                    Card(
                                        child: TitleValueLayout(
                                      title: t.apk_info.archive_type,
                                      value:
                                          apkInfo?.archiveType ?? "",
                                    )),
                                ],
                              )),
                              _buildIconWidget(apkInfo, iconRowSpan),
                            ],
                          ),
                          if (iconRowSpan < 3)
                            Card(
                              child: TitleValueLayout(
                                title: t.apk_info.min_sdk,
                                value: getSdkVersionText(
                                    apkInfo?.sdkVersion),
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
                          // MD5 哈希值
                          if (enableHash)
                            Card(
                                child: TitleValueLayout(
                              title: t.file_info.md5,
                              value: fileState.isComputingHash
                                  ? t.file_info.computing_hash
                                  : (fileState.md5Hash ?? ""),
                              end: _buildCopyButton(
                                  fileState.md5Hash,
                                  fileState.md5Hash != null &&
                                      !fileState.isComputingHash),
                            )),
                          // SHA1 哈希值
                          if (enableHash)
                            Card(
                                child: TitleValueLayout(
                              title: t.file_info.sha1,
                              value: fileState.isComputingHash
                                  ? t.file_info.computing_hash
                                  : (fileState.sha1Hash ?? ""),
                              end: _buildCopyButton(
                                  fileState.sha1Hash,
                                  fileState.sha1Hash != null &&
                                      !fileState.isComputingHash),
                            )),
                          if (enableSignature && !(apkInfo?.isXapk ?? false))
                            Card(
                                child: TitleValueLayout(
                              title: t.apk_info.signature_info,
                              value: fileState.isComputingSignature
                                  ? t.file_info.computing_hash
                                  : (fileState.signatureInfo ?? ""),
                              minLines: 1,
                              maxLines: textMaxLines,
                              selectable: !fileState.isComputingSignature,
                            )),
                    ],
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
    log.fine(
        "_buildMoreMenuButton: state.filePath=${state.filePath}");
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

    final fileName = _getDisplayLabel(apkInfo);
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

  bool _updateActionsPending = false;

  void _scheduleUpdateActions() {
    if (_updateActionsPending) return;
    _updateActionsPending = true;
    Future.microtask(() {
      _updateActionsPending = false;
      if (mounted) updateActions();
    });
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

  Widget _buildIconWidget(ApkInfo? apkInfo, int iconRowSpan) {
    final iconSize = iconRowSpan * 44.0;
    final radius = iconSize * 0.22;
    return GestureDetector(
      onSecondaryTapUp: (details) {
        if (apkInfo != null) {
          _showIconContextMenu(context, details.globalPosition, apkInfo);
        }
      },
      child: SizedBox(
        width: iconSize,
        height: iconSize,
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          clipBehavior: Clip.antiAlias,
          child: RawImage(
            image: apkInfo?.mainIconImage,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  void _showIconContextMenu(
      BuildContext context, Offset position, ApkInfo apkInfo) {
    final candidates = apkInfo.iconCandidates;
    final selectedIndex = ref.read(selectedIconIndexProvider);

    final items = <PopupMenuEntry<String>>[];

    // 切换图标分组（仅多候选时显示）
    if (candidates.length > 1) {
      for (int i = 0; i < candidates.length; i++) {
        items.add(PopupMenuItem(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          value: 'select_$i',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                i == selectedIndex
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                candidates[i].displayLabel,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ));
      }
      items.add(const PopupMenuDivider());
    }

    // 导出分组
    items.add(_buildMenuItem(
        'export_png', Icons.image, t.icon.export_as_png,
        enabled: apkInfo.mainIconImage != null));

    // SVG 导出（仅 XML 矢量图候选可用）
    final isXmlVector = selectedIndex >= 0 &&
        selectedIndex < candidates.length &&
        candidates[selectedIndex].type == IconCandidateType.xmlVector;
    items.add(_buildMenuItem(
        'export_svg', Icons.code, t.icon.export_as_svg,
        enabled: apkInfo.mainIconImage != null && isXmlVector));

    items.add(_buildMenuItem(
        'export_original', Icons.file_download, t.icon.export_original,
        enabled: apkInfo.mainIconImage != null));

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      popUpAnimationStyle: AnimationStyle.noAnimation,
      items: items,
    ).then((value) {
      if (value != null) {
        _handleIconMenuAction(value, apkInfo);
      }
    });
  }

  Future<void> _handleIconMenuAction(String value, ApkInfo apkInfo) async {
    if (value.startsWith('select_')) {
      final index = int.parse(value.substring(7));
      await _switchIcon(apkInfo, index);
    } else if (value == 'export_png') {
      await _exportAsPng(apkInfo);
    } else if (value == 'export_svg') {
      await _exportAsSvg(apkInfo);
    } else if (value == 'export_original') {
      await _exportOriginal(apkInfo);
    }
  }

  Future<void> _switchIcon(ApkInfo apkInfo, int index) async {
    if (index < 0 || index >= apkInfo.iconCandidates.length) return;
    final candidate = apkInfo.iconCandidates[index];

    if (candidate.renderedImage != null) {
      apkInfo.mainIconImage = candidate.renderedImage;
      ref.read(selectedIconIndexProvider.notifier).select(index);
      setState(() {});
    } else {
      // 异步渲染
      final image = await apkInfo.renderIcon(index);
      if (image != null && mounted) {
        apkInfo.mainIconImage = image;
        ref.read(selectedIconIndexProvider.notifier).select(index);
        setState(() {});
      }
    }
  }

  Future<void> _exportAsPng(ApkInfo apkInfo) async {
    final selectedIndex = ref.read(selectedIconIndexProvider);

    try {
      // 使用高清渲染导出（XML 矢量图 1024x1024 + 透明背景）
      ui.Image? exportImage;
      bool needDisposeExport = false;
      if (selectedIndex >= 0 &&
          selectedIndex < apkInfo.iconCandidates.length) {
        exportImage = await apkInfo.renderIconForExport(selectedIndex);
        if (exportImage != null) {
          needDisposeExport = true;
        }
      }
      // 回退到当前显示图标
      exportImage ??= apkInfo.mainIconImage;
      if (exportImage == null) return;

      final byteData =
          await exportImage.toByteData(format: ui.ImageByteFormat.png);
      // 如果是新渲染的导出图，释放它
      if (needDisposeExport) {
        exportImage.dispose();
      }
      if (byteData == null) return;

      final fileName = '${apkInfo.label ?? "icon"}_icon.png';
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: t.icon.export_icon,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['png'],
        lockParentWindow: true,
      );
      if (savePath == null) return;

      await File(savePath).writeAsBytes(byteData.buffer.asUint8List());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.icon.export_success)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.icon.export_failed(error: e.toString()))),
        );
      }
    }
  }

  Future<void> _exportAsSvg(ApkInfo apkInfo) async {
    final selectedIndex = ref.read(selectedIconIndexProvider);

    try {
      final svgString = await apkInfo.exportSvgString(selectedIndex);
      if (svgString == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text(t.icon.export_failed(error: 'SVG conversion failed'))),
          );
        }
        return;
      }

      final fileName = '${apkInfo.label ?? "icon"}_icon.svg';
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: t.icon.export_icon,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['svg'],
        lockParentWindow: true,
      );
      if (savePath == null) return;

      await File(savePath).writeAsString(svgString);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.icon.export_success)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.icon.export_failed(error: e.toString()))),
        );
      }
    }
  }

  Future<void> _exportOriginal(ApkInfo apkInfo) async {
    final selectedIndex = ref.read(selectedIconIndexProvider);

    try {
      Uint8List? bytes;
      String ext = '.png';

      // 尝试从 APK 中读取原始文件字节
      if (selectedIndex >= 0 &&
          selectedIndex < apkInfo.iconCandidates.length) {
        final candidate = apkInfo.iconCandidates[selectedIndex];
        if (candidate.rawBytes == null) {
          final zip = ZipHelper();
          try {
            await zip.open(apkInfo.apkPath);
            candidate.rawBytes = await zip.readFileContent(candidate.path);
          } finally {
            zip.close();
          }
        }
        if (candidate.rawBytes != null) {
          bytes = candidate.rawBytes;
          ext = path.extension(candidate.path);
        }
      }

      // 回退：无法获取原始字节（如 XAPK/APKM），导出渲染后的 PNG
      if (bytes == null) {
        final image = apkInfo.mainIconImage;
        if (image == null) return;
        final byteData =
            await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) return;
        bytes = byteData.buffer.asUint8List();
        ext = '.png';
      }

      final fileName = '${apkInfo.label ?? "icon"}_icon$ext';
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: t.icon.export_icon,
        fileName: fileName,
        lockParentWindow: true,
      );
      if (savePath == null) return;

      await File(savePath).writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.icon.export_success)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.icon.export_failed(error: e.toString()))),
        );
      }
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
