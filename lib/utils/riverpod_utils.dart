import 'package:flutter_riverpod/flutter_riverpod.dart';
// WidgetRef 的监听扩展
extension WidgetRefListenExtension on WidgetRef {
  // 批量监听, 注意只能知道变化, 值因为类型不匹配不方便回调
  void listenAll(List<Object?> providers, void Function() callback) {
    for (var provider in providers) {
      listen(provider as dynamic, (previous, next) {
        callback();
      });
    }
  }
}
