import 'package:flutter/foundation.dart';

/// Tells screens that already exist in the navigation stack (Home,
/// Recommendations) that new data has been saved, so they reload.
///
/// Reloading from `Navigator.push(...).then(...)` is not enough here: the scan
/// flow uses `pushReplacement` (scan, then analysis, then result), which
/// completes that Future as soon as the scan screen is replaced, long before
/// the new result exists.
class DataRefresh {
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  static void notify() => tick.value++;
}
