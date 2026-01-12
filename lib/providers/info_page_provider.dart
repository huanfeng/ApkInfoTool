import 'package:apk_info_tool/apkparser/apk_info.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'info_page_provider.g.dart';

@Riverpod(keepAlive: true)
class CurrentApkInfo extends _$CurrentApkInfo {
  @override
  ApkInfo? build() {
    return null;
  }

  void update(ApkInfo? apkInfo) {
    state = apkInfo;
  }

  void reset() {
    state = null;
  }
}

@Riverpod(keepAlive: true)
class IsParsing extends _$IsParsing {
  @override
  bool build() {
    return false;
  }

  void update(bool isParsing) {
    state = isParsing;
  }
}

class FileState {
  final String? filePath;
  final int? fileSize;
  final ApkInfo? apkInfo;
  final String? md5Hash;
  final String? sha1Hash;
  final bool isComputingHash;

  FileState({
    this.filePath,
    this.fileSize,
    this.apkInfo,
    this.md5Hash,
    this.sha1Hash,
    this.isComputingHash = false,
  });

  FileState copyWith({
    String? filePath,
    int? fileSize,
    ApkInfo? apkInfo,
    String? md5Hash,
    String? sha1Hash,
    bool? isComputingHash,
  }) {
    return FileState(
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      apkInfo: apkInfo ?? this.apkInfo,
      md5Hash: md5Hash ?? this.md5Hash,
      sha1Hash: sha1Hash ?? this.sha1Hash,
      isComputingHash: isComputingHash ?? this.isComputingHash,
    );
  }
}

@Riverpod(keepAlive: true)
class CurrentFileState extends _$CurrentFileState {
  @override
  FileState build() {
    return FileState();
  }

  void update(FileState fileState) {
    state = fileState;
  }

  void updateFilePath(String? filePath) {
    state = state.copyWith(filePath: filePath);
  }

  void updateFileSize(int? fileSize) {
    state = state.copyWith(fileSize: fileSize);
  }
}
