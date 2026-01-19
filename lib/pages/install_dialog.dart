import 'dart:io';

import 'package:apk_info_tool/gen/strings.g.dart';
import 'package:apk_info_tool/models/split_type.dart';
import 'package:apk_info_tool/utils/command_tools.dart';
import 'package:apk_info_tool/utils/logger.dart';
import 'package:apk_info_tool/utils/xapk_installer.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

class InstallOptions {
  bool allowDowngrade = false;
  bool forceInstall = false;
  bool allowTest = false;
  Map<String, bool> selectedSplits = {};  // 新增：选中的分包
}

class AdbDevice {
  final String id;
  final String status;
  final String? product;
  final String? model;
  final String? device;
  bool selected;
  String? installStatus;
  String? errorMessage;

  AdbDevice({
    required this.id,
    required this.status,
    this.product,
    this.model,
    this.device,
    this.selected = false,
  }) {
    selected = !isOffline;
  }

  bool get isOffline => status == 'offline';
  bool get isWireless => id.contains(':');

  String get displayName {
    if (isWireless) {
      return 'IP: $id';
    }
    final parts = <String>[];
    if (model != null) parts.add('$model');
    if (device != null) parts.add('$device');
    return parts.isEmpty ? id : parts.join(' ');
  }
}

class InstallDialog extends StatefulWidget {
  final String apkPath;
  final bool isXapk;

  const InstallDialog({
    super.key,
    required this.apkPath,
    this.isXapk = false,
  });

  @override
  State<InstallDialog> createState() => _InstallDialogState();
}

class _InstallDialogState extends State<InstallDialog> {
  List<AdbDevice> devices = [];
  bool isLoading = true;
  bool isInstalling = false;
  bool _isCancelled = false;  // 是否已取消安装
  Process? _currentProcess;  // 当前正在执行的进程
  XapkInstaller? _currentInstaller;  // 当前正在执行的XAPK安装器
  bool showAdvancedOptions = false;
  bool showSplitOptions = false;  // 新增：是否显示分包选择
  final InstallOptions options = InstallOptions();
  List<String>? splitApks;  // 新增：分包列表

  @override
  void initState() {
    super.initState();
    _loadDevices();
    if (widget.isXapk) {
      _loadSplitApks();
    }
  }

  Future<void> _loadDevices() async {
    setState(() {
      isLoading = true;
    });

    try {
      final exePath = CommandTools.getAdbPath();
      final result = await Process.run(exePath, ['devices', '-l']);
      final lines = result.stdout.toString().split('\n');

      List<AdbDevice> newDevices = [];
      for (var line in lines.skip(1)) {
        if (line.trim().isEmpty) continue;

        // 解析设备信息
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          final id = parts[0];
          final status = parts[1];

          // 解析额外信息
          String? product, model, device;
          if (parts.length > 2) {
            for (var info in parts.skip(2)) {
              if (info.startsWith('product:')) {
                product = info.substring(8);
              } else if (info.startsWith('model:')) {
                model = info.substring(6);
              } else if (info.startsWith('device:')) {
                device = info.substring(7);
              }
            }
          }

          newDevices.add(AdbDevice(
            id: id,
            status: status,
            product: product,
            model: model,
            device: device,
          ));
        }
      }

      setState(() {
        devices = newDevices;
        isLoading = false;
      });
    } catch (e) {
      log.warning('_loadDevices: 获取设备列表失败: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  // 新增：加载分包列表
  Future<void> _loadSplitApks() async {
    try {
      final installer = XapkInstaller();
      final splits = await installer.getSplitApks(widget.apkPath);
      if (splits != null) {
        setState(() {
          splitApks = splits;
          // 默认全选
          for (var split in splits) {
            options.selectedSplits[split] = true;
          }
        });
      }
    } catch (e) {
      log.severe('Failed to load split APKs: $e');
    }
  }

  Future<void> _installApk() async {
    if (!canInstall) return;

    setState(() {
      isInstalling = true;
      _isCancelled = false;
    });

    try {
      // 准备安装选项
      final installOptions = <String>[];
      if (options.allowDowngrade) installOptions.add('-d');
      if (options.forceInstall) installOptions.add('-r');
      if (options.allowTest) installOptions.add('-t');

      // 获取选中的设备
      final selectedDevices = devices.where((d) => d.selected).toList();

      // 安装到每个选中的设备
      for (final device in selectedDevices) {
        // 检查是否已取消
        if (_isCancelled) {
          break;
        }

        try {
          setState(() {
            device.installStatus = t.install.installing;
            device.errorMessage = null;
          });

          bool success;
          String? errorMessage;

          if (widget.isXapk) {
            final installer = XapkInstaller();
            _currentInstaller = installer;
            success = await installer.install(
              widget.apkPath,
              device.id,
              installOptions,
              selectedSplits: options.selectedSplits,
              isCancelled: () => _isCancelled,
            );
            _currentInstaller = null;
          } else {
            // 安装普通APK - 使用 Process.start 以支持中断
            final process = await Process.start(
              CommandTools.getAdbPath(),
              ['-s', device.id, 'install', ...installOptions, widget.apkPath],
            );
            _currentProcess = process;

            // 收集输出
            final stdoutBuffer = StringBuffer();
            final stderrBuffer = StringBuffer();
            process.stdout.transform(const SystemEncoding().decoder).listen((data) {
              stdoutBuffer.write(data);
            });
            process.stderr.transform(const SystemEncoding().decoder).listen((data) {
              stderrBuffer.write(data);
            });

            final exitCode = await process.exitCode;
            _currentProcess = null;

            success = exitCode == 0;
            if (!success) {
              errorMessage = stderrBuffer.toString();
            }
          }

          // 检查是否被中断
          if (_isCancelled) {
            setState(() {
              device.installStatus = t.install.stopped;
              device.errorMessage = null;
            });
            break;
          }

          setState(() {
            device.installStatus = success ? t.install.success : t.install.failed;
            device.errorMessage = errorMessage;
            // 安装成功后自动取消选中，避免用户重复点击确定时重新安装
            if (success) {
              device.selected = false;
            }
          });
        } catch (e) {
          // 如果是被中断导致的异常，显示已停止状态
          if (_isCancelled) {
            setState(() {
              device.installStatus = t.install.stopped;
              device.errorMessage = null;
            });
            break;
          }
          setState(() {
            device.installStatus = t.install.failed;
            device.errorMessage = e.toString();
          });
        }
      }
    } finally {
      setState(() {
        isInstalling = false;
        _isCancelled = false;
        _currentProcess = null;
        _currentInstaller = null;
      });
    }
  }

  // 显示停止确认对话框
  Future<void> _showStopConfirmDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.install.stop_confirm_title),
        content: Text(t.install.stop_confirm_message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.base.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.install.stop),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isCancelled = true;
      });
      // 中断当前正在执行的进程
      _currentProcess?.kill();
      _currentInstaller?.cancel();
    }
  }

  bool get canInstall {
    return !isInstalling &&
        devices.any((d) => d.selected) &&
        devices.where((d) => d.selected).every((d) => !d.isOffline);
  }

  // 新增：构建分包选择部分
  Widget _buildSplitApksSection() {
    if (!widget.isXapk || splitApks == null || splitApks!.isEmpty) {
      return const SizedBox.shrink();
    }

    // 按类型对分包进行分组
    final splitsByType = <SplitType, List<String>>{};
    for (var split in splitApks!) {
      final type = SplitType.fromId(path.basenameWithoutExtension(split));
      splitsByType.putIfAbsent(type, () => []).add(split);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text(t.install.split_options),
          trailing: IconButton(
            icon: Icon(showSplitOptions ? Icons.expand_less : Icons.expand_more),
            onPressed: () {
              setState(() {
                showSplitOptions = !showSplitOptions;
              });
            },
          ),
        ),
        if (showSplitOptions) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          for (var split in splitApks!) {
                            options.selectedSplits[split] = true;
                          }
                        });
                      },
                      child: Text(t.install.select_all),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          for (var split in splitApks!) {
                            final name = path.basenameWithoutExtension(split);
                            if (SplitType.fromId(name) != SplitType.base) {
                              options.selectedSplits[split] = false;
                            }
                          }
                        });
                      },
                      child: Text(t.install.base_only),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...splitsByType.entries.map((entry) {
                  final type = entry.key;
                  final splits = entry.value;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type.getDisplayText(t),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: splits.map((split) {
                          final name = path.basenameWithoutExtension(split);
                          // base包不允许取消选择
                          final isBase = SplitType.fromId(name) == SplitType.base;
                          return FilterChip(
                            label: Text(name),
                            selected: options.selectedSplits[split] ?? false,
                            onSelected: isBase ? null : (selected) {
                              setState(() {
                                options.selectedSplits[split] = selected;
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.install.title),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.install.select_device),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: devices.length,
                        itemBuilder: (context, index) {
                          final device = devices[index];
                          return ListTile(
                            leading: Checkbox(
                              value: device.selected,
                              onChanged: isInstalling || device.isOffline
                                  ? null
                                  : (value) {
                                      setState(() {
                                        device.selected = value ?? false;
                                      });
                                    },
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    device.isWireless
                                        ? device.id
                                        : device.displayName,
                                    style: device.isOffline
                                        ? const TextStyle(color: Colors.grey)
                                        : null,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: device.isOffline
                                        ? Colors.grey[300]
                                        : Colors.green[100],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    device.status,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: device.isOffline
                                          ? Colors.grey[700]
                                          : Colors.green[700],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: device.installStatus != null
                                ? Text(
                                    device.errorMessage ?? device.installStatus!,
                                    style: TextStyle(
                                      color: device.errorMessage != null
                                          ? Colors.red
                                          : Colors.green,
                                    ),
                                  )
                                : (device.isWireless
                                    ? null
                                    : Text(device.id,
                                        style: const TextStyle(fontSize: 12))),
                          );
                        },
                      ),
              ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          showAdvancedOptions = !showAdvancedOptions;
                        });
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            showAdvancedOptions
                                ? Icons.arrow_drop_down
                                : Icons.arrow_right,
                            size: 20,
                          ),
                          Text(
                            t.install.advanced_options,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (showAdvancedOptions) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: Checkbox(
                                    value: options.allowTest,
                                    onChanged: isInstalling
                                        ? null
                                        : (value) {
                                            setState(() {
                                              options.allowTest = value ?? false;
                                            });
                                          },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  t.install.allow_test,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: Checkbox(
                                    value: options.allowDowngrade,
                                    onChanged: isInstalling
                                        ? null
                                        : (value) {
                                            setState(() {
                                              options.allowDowngrade = value ?? false;
                                            });
                                          },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  t.install.allow_downgrade,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: Checkbox(
                                    value: options.forceInstall,
                                    onChanged: isInstalling
                                        ? null
                                        : (value) {
                                            setState(() {
                                              options.forceInstall = value ?? false;
                                            });
                                          },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  t.install.force_install,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
              if (widget.isXapk) ...[
                const SizedBox(height: 16),
                _buildSplitApksSection(),
              ],
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: isInstalling || isLoading ? null : _loadDevices,
          tooltip: t.install.refresh_devices,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isInstalling)
              TextButton(
                onPressed: _showStopConfirmDialog,
                child: Text(t.install.stop),
              )
            else
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(t.base.close),
              ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: canInstall ? _installApk : null,
              child: isInstalling
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(t.install.apk),
            ),
          ],
        ),
      ],
    );
  }
}
