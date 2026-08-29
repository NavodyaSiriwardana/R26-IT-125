const _monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatLoggedTime(int minutes) {
  if (minutes < 60) return '${minutes}m';

  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  return remainingMinutes == 0 ? '${hours}h' : '${hours}h ${remainingMinutes}m';
}

String formatCompactMinutes(int minutes) {
  if (minutes == 0) return '0m';
  if (minutes < 60) return '${minutes}m';

  final hours = minutes / 60;
  return hours == hours.roundToDouble()
      ? '${hours.round()}h'
      : '${hours.toStringAsFixed(1)}h';
}

double percentageFraction(double percentage) {
  return (percentage / 100).clamp(0.0, 1.0).toDouble();
}

String formatPercentage(double percentage) {
  return '${percentage.clamp(0, 100).round()}%';
}

String formatRate(double rate) {
  final percentage = rate <= 1 ? rate * 100 : rate;
  return formatPercentage(percentage);
}

String formatWeekRange(String start, String end) {
  final startDate = DateTime.tryParse(start);
  final endDate = DateTime.tryParse(end);

  if (startDate == null || endDate == null) return 'Current week';

  final startText = '${_monthNames[startDate.month - 1]} ${startDate.day}';
  final endText = startDate.month == endDate.month
      ? '${endDate.day}'
      : '${_monthNames[endDate.month - 1]} ${endDate.day}';

  return '$startText – $endText';
}

String formatEntryDate(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  return '${_monthNames[date.month - 1]} ${date.day}';
}

String formatGeneratedAt(String value) {
  final timestamp = DateTime.tryParse(value)?.toLocal();
  if (timestamp == null) return value;

  final hour = timestamp.hour == 0
      ? 12
      : timestamp.hour > 12
      ? timestamp.hour - 12
      : timestamp.hour;
  final minute = timestamp.minute.toString().padLeft(2, '0');
  final period = timestamp.hour >= 12 ? 'PM' : 'AM';

  return '${_monthNames[timestamp.month - 1]} ${timestamp.day}, '
      '$hour:$minute $period';
}
