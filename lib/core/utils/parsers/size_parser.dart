int parseSizeToBytes(String value) {
  final text = value.trim().replaceAll(',', '');
  if (text.isEmpty || text == '0') return 0;

  final match = RegExp(r'([\d.]+)\s*([A-Za-z]+)').firstMatch(text);
  if (match == null) return int.tryParse(text) ?? 0;

  final size = double.tryParse(match.group(1)!) ?? 0;
  final unit = match.group(2)!.toUpperCase();
  return switch (unit) {
    'B' => size.toInt(),
    'K' || 'KB' || 'KIB' => (size * 1024).toInt(),
    'M' || 'MB' || 'MIB' => (size * 1024 * 1024).toInt(),
    'G' || 'GB' || 'GIB' => (size * 1024 * 1024 * 1024).toInt(),
    'T' || 'TB' || 'TIB' => (size * 1024 * 1024 * 1024 * 1024).toInt(),
    'P' || 'PB' || 'PIB' => (size * 1024 * 1024 * 1024 * 1024 * 1024).toInt(),
    _ => size.toInt(),
  };
}
