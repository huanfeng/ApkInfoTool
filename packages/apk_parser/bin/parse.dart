import 'dart:io';
import 'package:apk_parser/apk_parser.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run bin/parse.dart <apk_file>');
    exit(1);
  }

  final filePath = args[0];
  if (!File(filePath).existsSync()) {
    print('Error: File not found: $filePath');
    exit(1);
  }

  final sw = Stopwatch()..start();
  final reader = ApkReader();

  if (!await reader.open(filePath)) {
    print('Error: Failed to open APK file');
    exit(1);
  }

  try {
    final meta = await reader.parse();
    sw.stop();

    if (meta == null) {
      print('Error: Failed to parse APK');
      exit(1);
    }

    print('=== APK Info (Dart parser) ===');
    print('Time: ${sw.elapsedMilliseconds}ms');
    print('');
    print('packageName:      ${meta.packageName}');
    print('versionCode:      ${meta.versionCode}');
    print('versionName:      ${meta.versionName}');
    print('label:            ${meta.label}');
    print('minSdkVersion:    ${meta.minSdkVersion}');
    print('targetSdkVersion: ${meta.targetSdkVersion}');
    print('compileSdkVer:    ${meta.compileSdkVersion}');
    print('');
    print('permissions (${meta.permissions.length}):');
    for (final p in meta.permissions) {
      print('  $p');
    }
    print('');
    print('features (${meta.features.length}):');
    for (final f in meta.features) {
      print('  $f');
    }
    print('');
    print('nativeCodes:      ${meta.nativeCodes}');
    print(
        'locales:          ${meta.locales.take(20).toList()}${meta.locales.length > 20 ? "... (${meta.locales.length} total)" : ""}');
    print('densities:        ${meta.densities}');
    print('');
    print('applicationIcon:  ${meta.applicationIcon}');
    print('iconPaths:');
    meta.iconPaths.forEach((dpi, path) {
      print('  ${dpi}dpi -> $path');
    });
    print('');
    print('labels (${meta.labels.length} locales):');
    meta.labels.entries.take(10).forEach((e) {
      print('  ${e.key}: ${e.value}');
    });
    if (meta.labels.length > 10) {
      print('  ... (${meta.labels.length} total)');
    }
    print('');
    print('launchableActivities:');
    for (final a in meta.launchableActivities) {
      print('  $a');
    }
  } finally {
    reader.close();
  }
}
