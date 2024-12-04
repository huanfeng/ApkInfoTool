import 'dart:io';

import 'package:apk_info_tool/config.dart';
import 'package:apk_info_tool/gen/strings.g.dart';
import 'package:apk_info_tool/utils/command_tools.dart';
import 'package:apk_info_tool/utils/logger.dart';
import 'package:flutter/material.dart';

class InstallOptions {
  bool allowDowngrade = false;
  bool forceInstall = false;
  bool allowTest = false;
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

  const InstallDialog({super.key, required this.apkPath});

  @override
  State<InstallDialog> createState() => _InstallDialogState();
}

class _InstallDialogState extends State<InstallDialog> {
  List<AdbDevice> devices = [];
  bool isLoading = true;
  bool isInstalling = false;
  bool showAdvancedOptions = false;
  final InstallOptions options = InstallOptions();

  @override
  void initState() {
    super.initState();
    _loadDevices();
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

  Future<void> _installApk() async {
    setState(() {
      isInstalling = true;
    });

    for (var device in devices.where((d) => d.selected)) {
      setState(() {
        device.installStatus = t.install.installing;
        device.errorMessage = null;
      });

      List<String> args = ['install'];

      if (options.allowDowngrade) {
        args.add('-d');
      }
      if (options.forceInstall) {
        args.add('-r');
      }
      if (options.allowTest) {
        args.add('-t');
      }

      args.add(widget.apkPath);

      try {
        final result = await Process.run(
          'adb',
          ['-s', device.id, ...args],
        );

        setState(() {
          if (result.exitCode == 0) {
            device.installStatus = t.install.success;
          } else {
            device.installStatus = t.install.failed;
            device.errorMessage = result.stderr.toString();
          }
        });
      } catch (e) {
        setState(() {
          device.installStatus = t.install.error;
          device.errorMessage = e.toString();
        });
      }
    }

    setState(() {
      isInstalling = false;
    });
  }

  bool get canInstall {
    return !isInstalling &&
        devices.any((d) => d.selected) &&
        devices.where((d) => d.selected).every((d) => !d.isOffline);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.install.apk),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (devices.isEmpty)
              Text(t.install.no_devices)
            else
              SizedBox(
                height: 200,
                child: ListView.builder(
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isInstalling ? null : () => Navigator.of(context).pop(),
          child: Text(t.base.cancel),
        ),
        ElevatedButton(
          onPressed: canInstall ? _installApk : null,
          child: isInstalling
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t.base.confirm),
        ),
      ],
    );
  }
}
