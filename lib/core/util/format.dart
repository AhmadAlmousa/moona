/// Formats an item count, dropping a trailing `.0` (e.g. `2.0` → `2`,
/// `1.5` stays `1.5`).
String formatCount(double count) {
  if (count == count.roundToDouble()) return count.toInt().toString();
  return count
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
