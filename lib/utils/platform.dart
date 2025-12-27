import 'dart:io';

Future<void> openFileInExplorer(String filePath) async {
  if (Platform.isWindows) {
    // Windows: 使用 explorer.exe /select 命令选中文件
    await Process.run('explorer.exe', ['/select,', filePath]);
  } else if (Platform.isMacOS) {
    // macOS: 使用 open -R 命令选中文件
    await Process.run('open', ['-R', filePath]);
  } else if (Platform.isLinux) {
    // Linux: 尝试使用 xdg-open 打开目录
    final directory = File(filePath).parent.path;
    await Process.run('xdg-open', [directory]);
  }
}

Future<void> openDirectoryInExplorer(String directoryPath) async {
  if (Platform.isWindows) {
    await Process.run('explorer.exe', [directoryPath]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [directoryPath]);
  } else if (Platform.isLinux) {
    await Process.run('xdg-open', [directoryPath]);
  }
}
