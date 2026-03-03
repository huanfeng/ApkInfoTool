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
    state?.dispose();
    state = apkInfo;
  }

  void reset() {
    state?.dispose();
    state = null;
  }
}

@Riverpod(keepAlive: true)
class SelectedIconIndex extends _$SelectedIconIndex {
  @override
  int build() => 0;

  void select(int index) => state = index;
  void reset() => state = 0;
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
  final String? signatureInfo;
  final bool isComputingSignature;

  FileState({
    this.filePath,
    this.fileSize,
    this.apkInfo,
    this.md5Hash,
    this.sha1Hash,
    this.isComputingHash = false,
    this.signatureInfo,
    this.isComputingSignature = false,
  });

  FileState copyWith({
    String? filePath,
    int? fileSize,
    ApkInfo? apkInfo,
    String? md5Hash,
    String? sha1Hash,
    bool? isComputingHash,
    String? signatureInfo,
    bool? isComputingSignature,
  }) {
    return FileState(
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      apkInfo: apkInfo ?? this.apkInfo,
      md5Hash: md5Hash ?? this.md5Hash,
      sha1Hash: sha1Hash ?? this.sha1Hash,
      isComputingHash: isComputingHash ?? this.isComputingHash,
      signatureInfo: signatureInfo ?? this.signatureInfo,
      isComputingSignature: isComputingSignature ?? this.isComputingSignature,
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
