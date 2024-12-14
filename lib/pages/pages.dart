enum Pages {
  home,
  info,
  setting,
  install,
}

abstract class PageBase {
  final Pages page;

  PageBase(this.page);
}
