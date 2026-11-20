/// Dates, times and codes the way the design library writes them:
/// "20 Nov 2026", "9:41 AM", "20 Nov 2026, 9:41 AM", "482 913", "4:05".
library;

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String formatTime(DateTime d) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${d.hour < 12 ? 'AM' : 'PM'}';
}

String formatDateTime(DateTime d) => '${formatDate(d)}, ${formatTime(d)}';

/// `m:ss`, never negative.
String formatCountdown(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// "482913" → "482 913". Other lengths are returned unchanged.
String formatCode(String code) =>
    code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;

/// "1 message" / "2 messages".
String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';
