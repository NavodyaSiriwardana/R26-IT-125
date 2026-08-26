class TimeUtils {
  static String calculateTimePeriod(String startTime) {
    if (startTime.isEmpty) return '';
    try {
      final parts = startTime.split(':');
      final hour = int.parse(parts[0]);
      if (hour >= 5 && hour < 12) return 'Morning';
      if (hour >= 12 && hour < 17) return 'Afternoon';
      if (hour >= 17 && hour < 21) return 'Evening';
      return 'Night';
    } catch (e) {
      return '';
    }
  }

  static String calculateDuration(String startTime, String endTime) {
    if (startTime.isEmpty || endTime.isEmpty) return '';
    try {
      final startParts = startTime.split(':');
      final endParts = endTime.split(':');
      int startMinutes =
          int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
      int endMinutes =
          int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
      if (endMinutes < startMinutes) endMinutes += 24 * 60;
      int diff = endMinutes - startMinutes;
      int hours = diff ~/ 60;
      int minutes = diff % 60;
      if (hours > 0 && minutes > 0) return '${hours}h ${minutes}m';
      if (hours > 0) return '${hours}h';
      return '${minutes}m';
    } catch (e) {
      return '';
    }
  }

  static String todayDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static String formatDisplayDate(String date) {
    if (date.isEmpty) return '';
    try {
      final parts = date.split('-');
      final dt = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      const days = [
        '', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
      ];
      return '${days[dt.weekday]}, ${dt.day} ${months[dt.month]} ${dt.year}';
    } catch (e) {
      return date;
    }
  }
}