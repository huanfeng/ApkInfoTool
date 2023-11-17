import 'dart:convert';
import 'dart:io';
import 'dart:developer';

Future<void> getApkInfo() async {
  log("getApkInfo: start");
  // 启动子进程
  Process process = await Process.start('python', ['--version']);

// 监听stdout
  process.stdout.listen((List<int> data) {
    String output = utf8.decode(data);
    log(output);
    // 从output提取信息
  });

// 监听stderr
  process.stderr.listen((List<int> data) {
    String output = utf8.decode(data);
    log(output);
  });

// 等待子进程退出
  var exitCode = await process.exitCode;
  log("getApkInfo: end exitCode=$exitCode");
}
