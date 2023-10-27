import 'dart:convert';
import 'dart:io';

Future<void> getApkInfo() async {
  print("getApkInfo: start");
  // 启动子进程
  Process process = await Process.start('python', ['--version']);

// 监听stdout
  process.stdout.listen((List<int> data) {
    String output = utf8.decode(data);
    print(output);
    // 从output提取信息
  });

// 监听stderr
  process.stderr.listen((List<int> data) {
    String output = utf8.decode(data);
    print(output);
  });

// 等待子进程退出
  var exitCode = await process.exitCode;
  print("getApkInfo: end exitCode=${exitCode}");
}
