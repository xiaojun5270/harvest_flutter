String formatBytes(
  num bytes, {
  String suffix = '',
  bool showZero = true,
  int? decimals,
  int unit = 1024,
}) {
  if (bytes <= 0) return showZero ? '0 B$suffix' : '∞';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  final base = unit > 1 ? unit : 1024;
  var index = 0;
  var value = bytes.toDouble();
  while (value >= base && index < units.length - 1) {
    value /= base;
    index++;
  }
  if (base == 1024 &&
      index > 0 &&
      value >= 1000 &&
      value < base &&
      index < units.length - 1) {
    value /= base;
    index++;
  }
  final fractionDigits = decimals ?? (index >= 2 ? 2 : (index >= 1 ? 1 : 0));
  return '${value.toStringAsFixed(fractionDigits)} ${units[index]}$suffix';
}

String formatSpeed(num bytesPerSecond, {int unit = 1024}) =>
    formatBytes(bytesPerSecond, suffix: '/s', unit: unit);

String formatCompactBytes(int bytes) {
  if (bytes == 0) return '0 B';
  final neg = bytes < 0;
  var size = bytes.abs().toDouble();
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var index = 0;
  while (size >= 1024 && index < units.length - 1) {
    size /= 1024;
    index++;
  }
  return '${neg ? '-' : ''}${size.toStringAsFixed(index > 1 ? 1 : 0)} ${units[index]}';
}
