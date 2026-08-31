/// Formats a byte count as a human-readable string (e.g. "512 MB", "1.2 GB").
/// Shared across features that display sizes — Status today, Clean/Analyze
/// later — so it lives in `core/` rather than inside one feature.
String formatBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final digits = unitIndex == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
}

/// Formats a byte-per-second rate, reusing [formatBytes].
String formatByteRate(num bytesPerSecond) => '${formatBytes(bytesPerSecond)}/s';

/// Formats a duration as "Hh Mm" (or "Mm" under an hour). Used for uptime
/// and battery time-remaining display.
String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours <= 0) return '${minutes}m';
  return '${hours}h ${minutes}m';
}
