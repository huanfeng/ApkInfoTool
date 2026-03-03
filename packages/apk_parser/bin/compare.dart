import 'dart:convert';
import 'dart:io';
import 'package:apk_parser/apk_parser.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print(
        'Usage: dart run bin/compare.dart <apk_file_or_directory> [--aapt2 <path>]');
    exit(1);
  }

  final target = args[0];
  var aapt2Path = 'aapt2';
  final aapt2Index = args.indexOf('--aapt2');
  if (aapt2Index >= 0 && aapt2Index + 1 < args.length) {
    aapt2Path = args[aapt2Index + 1];
  }

  final apkFiles = <File>[];
  final entity = FileSystemEntity.typeSync(target);
  if (entity == FileSystemEntityType.directory) {
    final dir = Directory(target);
    await for (final file in dir.list(recursive: true)) {
      if (file is File && file.path.toLowerCase().endsWith('.apk')) {
        apkFiles.add(file);
      }
    }
  } else if (entity == FileSystemEntityType.file) {
    apkFiles.add(File(target));
  } else {
    print('Error: $target not found');
    exit(1);
  }

  if (apkFiles.isEmpty) {
    print('No APK files found');
    exit(1);
  }

  print('Found ${apkFiles.length} APK file(s)\n');

  var passCount = 0;
  var failCount = 0;
  var skipCount = 0;
  var totalDartMs = 0;
  var totalAapt2Ms = 0;
  final failures = <String, List<String>>{};

  for (var i = 0; i < apkFiles.length; i++) {
    final file = apkFiles[i];
    final fileName = file.uri.pathSegments.last;
    print('${"=" * 60}');
    print('[${i + 1}/${apkFiles.length}] $fileName');
    print('${"=" * 60}');

    // Dart parse
    final dartSw = Stopwatch()..start();
    final reader = ApkReader();
    ApkMeta? dartResult;
    try {
      if (await reader.open(file.path)) {
        dartResult = await reader.parse();
      }
    } catch (e) {
      print('  Dart parse error: $e');
    } finally {
      reader.close();
    }
    dartSw.stop();
    final dartMs = dartSw.elapsedMilliseconds;
    totalDartMs += dartMs;

    // aapt2 parse
    final aapt2Sw = Stopwatch()..start();
    Map<String, String>? aapt2Result;
    try {
      final result = await Process.run(
        aapt2Path,
        ['dump', 'badging', file.path],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 120));
      if (result.exitCode == 0) {
        aapt2Result = _parseAapt2Output(result.stdout.toString());
      }
    } catch (e) {
      print('  aapt2 error: $e');
    }
    aapt2Sw.stop();
    final aapt2Ms = aapt2Sw.elapsedMilliseconds;
    totalAapt2Ms += aapt2Ms;

    if (dartResult == null || aapt2Result == null) {
      print('  SKIP (parse failed)\n');
      skipCount++;
      continue;
    }

    // Compare fields
    final fields = _buildComparisonFields(dartResult, aapt2Result);
    var allMatch = true;
    final fileFailures = <String>[];

    print(
        '  ${"Field".padRight(22)} ${"Dart".padRight(30)} ${"aapt2".padRight(30)} Match');
    print('  ${"-" * 87}');

    for (final field in fields) {
      final match = field.dartValue == field.aapt2Value;
      final icon = match ? 'OK' : 'FAIL';
      if (!match) {
        allMatch = false;
        fileFailures.add(field.name);
      }
      print('  ${field.name.padRight(22)} '
          '${_truncate(field.dartValue, 28).padRight(30)} '
          '${_truncate(field.aapt2Value, 28).padRight(30)} '
          '$icon');
    }

    final speedup = dartMs > 0 ? (aapt2Ms / dartMs).toStringAsFixed(1) : '?';
    print('');
    print('  Time: Dart=${dartMs}ms  aapt2=${aapt2Ms}ms  (${speedup}x)');

    if (allMatch) {
      passCount++;
      print('  Result: PASS');
    } else {
      failCount++;
      failures[fileName] = fileFailures;
      print('  Result: FAIL (${fileFailures.join(", ")})');
    }
    print('');
  }

  // Summary
  print('${"=" * 60}');
  print('Summary: ${apkFiles.length} APKs tested');
  print('  Pass: $passCount  Fail: $failCount  Skip: $skipCount');
  if (totalDartMs > 0 && totalAapt2Ms > 0) {
    print('  Total time: Dart=${totalDartMs}ms  aapt2=${totalAapt2Ms}ms');
    print(
        '  Avg speedup: ${(totalAapt2Ms / totalDartMs).toStringAsFixed(1)}x');
  }
  if (failures.isNotEmpty) {
    print('  Failures:');
    failures.forEach((file, fields) {
      print('    $file: ${fields.join(", ")}');
    });
  }
}

class _CompareField {
  final String name;
  final String dartValue;
  final String aapt2Value;
  _CompareField(this.name, this.dartValue, this.aapt2Value);
}

List<_CompareField> _buildComparisonFields(
    ApkMeta dart, Map<String, String> aapt2) {
  return [
    _CompareField(
        'packageName', dart.packageName ?? '', aapt2['packageName'] ?? ''),
    _CompareField(
        'versionCode', '${dart.versionCode ?? ""}', aapt2['versionCode'] ?? ''),
    _CompareField(
        'versionName', dart.versionName ?? '', aapt2['versionName'] ?? ''),
    _CompareField('label', dart.label ?? '', aapt2['label'] ?? ''),
    _CompareField('minSdkVersion', '${dart.minSdkVersion ?? ""}',
        aapt2['sdkVersion'] ?? ''),
    _CompareField('targetSdkVersion', '${dart.targetSdkVersion ?? ""}',
        aapt2['targetSdkVersion'] ?? ''),
    _CompareField('permissions', '${dart.permissions.length} items',
        aapt2['permissionCount'] ?? '?'),
    _CompareField(
        'nativeCodes', dart.nativeCodes.join(','), aapt2['nativeCodes'] ?? ''),
  ];
}

Map<String, String> _parseAapt2Output(String output) {
  final result = <String, String>{};
  var permCount = 0;
  final nativeCodes = <String>[];

  for (final line in output.split('\n')) {
    final colonPos = line.indexOf(':');
    if (colonPos < 0) continue;
    final key = line.substring(0, colonPos).trim();
    final value = line.substring(colonPos + 1).trim();

    switch (key) {
      case 'package':
        final nameMatch = RegExp(r"name='([^']*)'").firstMatch(value);
        final vcMatch = RegExp(r"versionCode='([^']*)'").firstMatch(value);
        final vnMatch = RegExp(r"versionName='([^']*)'").firstMatch(value);
        if (nameMatch != null) result['packageName'] = nameMatch.group(1)!;
        if (vcMatch != null) result['versionCode'] = vcMatch.group(1)!;
        if (vnMatch != null) result['versionName'] = vnMatch.group(1)!;
      case 'application-label':
        result['label'] = value.replaceAll("'", '');
      case 'sdkVersion':
      case 'minSdkVersion':
        result['sdkVersion'] = value.replaceAll("'", '');
      case 'targetSdkVersion':
        result['targetSdkVersion'] = value.replaceAll("'", '');
      case 'uses-permission':
        permCount++;
      case 'native-code':
        nativeCodes.addAll(value
            .split(' ')
            .map((s) => s.replaceAll("'", '').trim())
            .where((s) => s.isNotEmpty));
    }
  }

  result['permissionCount'] = '$permCount items';
  result['nativeCodes'] = nativeCodes.join(',');
  return result;
}

String _truncate(String s, int max) {
  return s.length <= max ? s : '${s.substring(0, max - 2)}..';
}
