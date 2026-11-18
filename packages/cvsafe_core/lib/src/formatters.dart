// Time formatting helpers. API timestamps are Unix seconds (double).

/// Relative time such as `45s ago`, `12m ago`, `3h ago`, `2d ago`.
String timeAgo(double ts, {DateTime? now}) {
  final nowS = (now ?? DateTime.now()).millisecondsSinceEpoch / 1000;
  final s = (nowS - ts).round();
  if (s < 0) return 'now';
  if (s < 60) return '${s}s ago';
  if (s < 3600) return '${s ~/ 60}m ago';
  if (s < 86400) return '${s ~/ 3600}h ago';
  return '${s ~/ 86400}d ago';
}

String _two(int v) => v.toString().padLeft(2, '0');

DateTime _local(double ts) => DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());

/// Local wall-clock time `HH:mm:ss`.
String clock(double ts) {
  final d = _local(ts);
  return '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
}

/// Local date and time `dd.MM.yyyy HH:mm`.
String dateTime(double ts) {
  final d = _local(ts);
  return '${_two(d.day)}.${_two(d.month)}.${d.year} ${_two(d.hour)}:${_two(d.minute)}';
}

/// Duration in seconds as `4m 05s`.
String durationLabel(int seconds) => '${seconds ~/ 60}m ${_two(seconds % 60)}s';
