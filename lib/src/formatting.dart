String _two(int n) => n.toString().padLeft(2, '0');

/// 75300 -> "1:15.3", 3725000 -> "1:02:05.0".
String formatPrecise(int ms) {
  final tenths = (ms < 0 ? 0 : ms) ~/ 100;
  final totalSeconds = tenths ~/ 10;
  final h = totalSeconds ~/ 3600;
  final m = totalSeconds % 3600 ~/ 60;
  final s = totalSeconds % 60;
  final t = tenths % 10;
  return h > 0 ? '$h:${_two(m)}:${_two(s)}.$t' : '$m:${_two(s)}.$t';
}

/// 205000 -> "3:25", 3725000 -> "1:02:05".
String formatShort(int ms) {
  final totalSeconds = (ms < 0 ? 0 : ms) ~/ 1000;
  final h = totalSeconds ~/ 3600;
  final m = totalSeconds % 3600 ~/ 60;
  final s = totalSeconds % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '$m:${_two(s)}';
}

/// Parses "ss", "ss.s", "m:ss.s" or "h:mm:ss.s" into milliseconds. Spaces work as well as ':'
/// and ',' works as the decimal separator. Returns null for anything else.
int? parseTime(String text) {
  final parts = text.trim().replaceAll(',', '.').split(RegExp(r'\s*:\s*|\s+'));
  if (parts.isEmpty || parts.length > 3 || parts.any((p) => p.isEmpty)) return null;
  final seconds = double.tryParse(parts.last);
  if (seconds == null || seconds < 0 || seconds.isNaN || seconds.isInfinite) return null;
  var total = seconds;
  var multiplier = 60.0;
  for (final part in parts.sublist(0, parts.length - 1).reversed) {
    final value = int.tryParse(part);
    if (value == null || value < 0) return null;
    total += value * multiplier;
    multiplier *= 60;
  }
  return (total * 1000).round();
}

/// Replaces characters that aren't allowed in file names.
String sanitizeFileName(String name) {
  var result = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
  while (result.startsWith('.')) {
    result = result.substring(1);
  }
  while (result.endsWith('.')) {
    result = result.substring(0, result.length - 1);
  }
  return result.trim();
}

/// "My video.mp4" -> "My video".
String withoutExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot > 0 ? fileName.substring(0, dot) : fileName;
}

String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[unit]}';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String formatDate(DateTime date, {DateTime? now}) {
  now ??= DateTime.now();
  final dayMonth = '${_months[date.month - 1]} ${date.day}';
  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return '${_two(date.hour)}:${_two(date.minute)}';
  }
  return date.year == now.year ? dayMonth : '$dayMonth, ${date.year}';
}

/// 1 -> "1 song", 12 -> "12 songs".
String songCount(int n) => '$n ${n == 1 ? 'song' : 'songs'}';

/// Total length of a playlist: "40 s", "45 min", "1 h 05 min".
String formatTotalDuration(int ms) {
  if (ms < 60000) return '${(ms / 1000).round()} s';
  final minutes = (ms / 60000).round();
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${_two(minutes % 60)} min';
}
