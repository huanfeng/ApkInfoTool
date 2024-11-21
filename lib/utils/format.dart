String formatFileSize(int? bytes) {
  if (bytes == null) return "";
  
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unitIndex = 0;
  
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  
  // 如果是B，不需要小数点
  if (unitIndex == 0) {
    return '${size.toInt()} ${units[unitIndex]}';
  }
  
  // 保留两位小数，去掉末尾的0
  return '${size.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '')} ${units[unitIndex]}';
}
