import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'home_page_provider.g.dart';

@riverpod
class PageActions extends _$PageActions {
  @override
  List<Widget> build() => [];

  void setActions(List<Widget> actions) {
    state = actions;
  }
}

@riverpod
class CurrentPage extends _$CurrentPage {
  @override
  int build() => 0;

  void setIndex(int index) {
    state = index;
  }
}
