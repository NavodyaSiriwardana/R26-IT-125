import 'dart:io';
import 'package:app_usage/app_usage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:usage_stats/usage_stats.dart';
import 'location_service.dart';
import 'calendar_settings_service.dart';

class SensorDataService {
  static const _youtubeChannel = MethodChannel('com.truthlens/youtube');

  static const List<String> _educationalKeywords = [
    'lecture',
    'tutorial',
    'course',
    'exam',
    'study',
    'lesson',
    'explained',
    'how to',
    'crash course',
    'documentary',
    'physics',
    'chemistry',
    'math',
    'programming',
    'science',
    'university',
  ];

  static const List<String> _entertainmentKeywords = [
    'vlog',
    'prank',
    'reaction',
    'funny',
    'comedy',
    'meme',
    'highlights',
    'trailer',
    'music video',
    'gaming',
    'live',
  ];

  static Future<String?> _getCurrentYoutubeTitle() async {
    try {
      final title = await _youtubeChannel.invokeMethod<String>(
        'getCurrentYoutubeTitle',
      );
      return title;
    } catch (e) {
      return null;
    }
  }

  static String _classifyYoutubeTitle(String title) {
    final lower = title.toLowerCase();
    for (final kw in _educationalKeywords) {
      if (lower.contains(kw)) return 'educational';
    }
    for (final kw in _entertainmentKeywords) {
      if (lower.contains(kw)) return 'entertainment';
    }
    return 'entertainment';
  }

  // Package name → category mapping
  static const Map<String, String> _appCategories = {
    // Entertainment / social media
    'com.facebook.katana': 'entertainment',
    'com.facebook.lite': 'entertainment',
    'com.instagram.android': 'entertainment',
    'com.zhiliaoapp.musically': 'entertainment', // TikTok
    'com.ss.android.ugc.trill': 'entertainment', // TikTok (alt)
    'com.twitter.android': 'entertainment',
    'com.snapchat.android': 'entertainment',
    'com.whatsapp': 'entertainment',
    'com.google.android.youtube':
        'entertainment', // fallback if title detection fails
    // Educational
    'com.google.android.apps.meetings': 'educational', // Google Meet
    'us.zoom.videomeetings': 'educational',
    'com.microsoft.teams': 'educational',
    'com.google.android.apps.docs': 'educational',
    'com.google.android.apps.classroom': 'educational',
    'com.google.android.apps.docs.editors.docs': 'educational',
  };

  // Friendly display names for the breakdown shown on the result screen —
  // purely presentational, not used in any classification logic.
  static const Map<String, String> _friendlyNames = {
    'com.facebook.katana': 'Facebook',
    'com.facebook.lite': 'Facebook',
    'com.instagram.android': 'Instagram',
    'com.zhiliaoapp.musically': 'TikTok',
    'com.ss.android.ugc.trill': 'TikTok',
    'com.twitter.android': 'Twitter',
    'com.snapchat.android': 'Snapchat',
    'com.whatsapp': 'WhatsApp',
    'com.google.android.youtube': 'YouTube',
    'com.google.android.apps.meetings': 'Google Meet',
    'us.zoom.videomeetings': 'Zoom',
    'com.microsoft.teams': 'Microsoft Teams',
    'com.google.android.apps.docs': 'Google Docs',
    'com.google.android.apps.classroom': 'Google Classroom',
    'com.google.android.apps.docs.editors.docs': 'Google Docs',
  };

  /// Request the runtime permissions needed for sensor data collection.
  static Future<bool> requestPermissions() async {
    final locationStatus = await Permission.locationWhenInUse.request();
    return locationStatus.isGranted;
  }

  /// Usage Access (needed for [getCategorizedAppUsage]) is a special
  /// Android setting, not a normal runtime permission — there's no native
  /// grant popup for it, only a status check and a deep link to the
  /// system settings screen where the student toggles it on themselves.
  static Future<bool> hasUsageAccess() async {
    final granted = await UsageStats.checkUsagePermission();
    return granted ?? false;
  }

  static void openUsageAccessSettings() {
    UsageStats.grantUsagePermission();
  }

  /// Whether [YouTubeAccessibilityService] (native, reads the on-screen
  /// video title so [getCategorizedAppUsage] can tell an educational
  /// YouTube video from entertainment) is turned on. Same "no native grant
  /// popup, only a status check + settings deep link" shape as Usage
  /// Access, just a different Android settings screen.
  static Future<bool> hasAccessibilityAccess() async {
    try {
      final enabled = await _youtubeChannel.invokeMethod<bool>(
        'isAccessibilityServiceEnabled',
      );
      return enabled ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> openAccessibilitySettings() async {
    try {
      await _youtubeChannel.invokeMethod('openAccessibilitySettings');
    } catch (e) {
      // ignore — worst case the settings shortcut silently does nothing
    }
  }

  /// Collect and categorize app usage over the last [hours] hours.
  /// Returns social_media_minutes, entertainment_minutes,
  /// verified_educational_minutes, app_switch_count, and a per-app
  /// breakdown (educational_breakdown / entertainment_breakdown) so the
  /// result screen can show *which* apps made up each total — purely for
  /// display, not used anywhere in the bias classification itself.
  static Future<Map<String, dynamic>> getCategorizedAppUsage({
    int hours = 3,
  }) async {
    double socialMediaMinutes = 0;
    double entertainmentMinutes = 0;
    double educationalMinutes = 0;
    double otherMinutes = 0;
    int appSwitchCount = 0;
    final Map<String, double> educationalBreakdown = {};
    final Map<String, double> entertainmentBreakdown = {};
    final Map<String, double> socialMediaBreakdown = {};
    final Map<String, double> otherBreakdown = {};

    if (!Platform.isAndroid) {
      // app_usage only works on Android; return zeros elsewhere (e.g. web/dev testing)
      return {
        'social_media_minutes': 0,
        'entertainment_minutes': 0,
        'verified_educational_minutes': 0,
        'other_minutes': 0,
        'app_switch_count': 0,
        'educational_breakdown': <String, double>{},
        'entertainment_breakdown': <String, double>{},
        'social_media_breakdown': <String, double>{},
        'other_breakdown': <String, double>{},
      };
    }

    try {
      final endDate = DateTime.now();
      final startDate = endDate.subtract(Duration(hours: hours));

      final List<AppUsageInfo> infoList = await AppUsage().getAppUsage(
        startDate,
        endDate,
      );

      // TEMP DEBUG — remove once the entertainment-minutes discrepancy
      // against Digital Wellbeing is understood. Prints every raw
      // (packageName, minutes) pair the app_usage plugin returned for
      // this window, so duplicate/inflated entries are visible directly.
      // ignore: avoid_print
      print('--- RAW app_usage entries (${startDate.toIso8601String()} to ${endDate.toIso8601String()}) ---');
      for (final app in infoList) {
        // ignore: avoid_print
        print('  ${app.packageName}: ${app.usage.inMinutes} min (raw usage=${app.usage})');
      }
      // ignore: avoid_print
      print('--- end raw entries (${infoList.length} total) ---');

      appSwitchCount = infoList.length;

      for (final app in infoList) {
        final minutes = app.usage.inMinutes.toDouble();

        final friendlyName = _friendlyNames[app.packageName] ?? app.packageName;

        if (app.packageName == 'com.google.android.youtube') {
          // Content-level classification via detected video title
          final title = await _getCurrentYoutubeTitle();
          final youtubeCategory = title != null
              ? _classifyYoutubeTitle(title)
              : 'entertainment';

          if (youtubeCategory == 'educational') {
            educationalMinutes += minutes;
            educationalBreakdown[friendlyName] =
                (educationalBreakdown[friendlyName] ?? 0) + minutes;
          } else {
            entertainmentMinutes += minutes;
            entertainmentBreakdown[friendlyName] =
                (entertainmentBreakdown[friendlyName] ?? 0) + minutes;
          }
          continue;
        }

        final category = _appCategories[app.packageName];

        if (category == 'entertainment') {
          if (_isSocialApp(app.packageName)) {
            socialMediaMinutes += minutes;
            socialMediaBreakdown[friendlyName] =
                (socialMediaBreakdown[friendlyName] ?? 0) + minutes;
          } else {
            entertainmentMinutes += minutes;
            entertainmentBreakdown[friendlyName] =
                (entertainmentBreakdown[friendlyName] ?? 0) + minutes;
          }
        } else if (category == 'educational') {
          educationalMinutes += minutes;
          educationalBreakdown[friendlyName] =
              (educationalBreakdown[friendlyName] ?? 0) + minutes;
        } else {
          // Unmapped apps (ChatGPT, Chrome, PickMe, banking apps, etc.)
          // used to vanish entirely — neither counted nor shown. They
          // still can't be confidently sorted into study vs. distraction,
          // so they stay OUT of duration_gap/activity_match/distraction_
          // duration (comparator.py, classifier features unchanged) —
          // this is purely so the student can see where the rest of
          // their screen time actually went, not a new scoring signal.
          otherMinutes += minutes;
          otherBreakdown[friendlyName] =
              (otherBreakdown[friendlyName] ?? 0) + minutes;
        }
      }
    } catch (e) {
      // Usage access permission likely not granted; return zeros
    }

    return {
      'social_media_minutes': socialMediaMinutes,
      'entertainment_minutes': entertainmentMinutes,
      'verified_educational_minutes': educationalMinutes,
      'other_minutes': otherMinutes,
      'app_switch_count': appSwitchCount,
      'educational_breakdown': educationalBreakdown,
      'entertainment_breakdown': entertainmentBreakdown,
      'social_media_breakdown': socialMediaBreakdown,
      'other_breakdown': otherBreakdown,
    };
  }

  static bool _isSocialApp(String packageName) {
    const socialApps = [
      'com.facebook.katana',
      'com.facebook.lite',
      'com.instagram.android',
      'com.zhiliaoapp.musically',
      'com.ss.android.ugc.trill',
      'com.twitter.android',
      'com.snapchat.android',
      'com.whatsapp',
    ];
    return socialApps.contains(packageName);
  }

  /// Get the current GPS location as a simple label.
  /// Compares against the user's saved reference points (Home, Library,
  /// etc. — see LocationService/add_location_screen) and returns the
  /// matching name so it can be string-compared against claimed_location
  /// on the backend. Falls back to raw coordinates if no saved location
  /// contains the current position (or no userId is available).
  static Future<String> getCurrentLocationLabel({String? userId}) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return 'Unknown';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        return 'Unknown';
      }

      final position = await Geolocator.getCurrentPosition();

      if (userId != null && userId.isNotEmpty) {
        try {
          final match = await LocationService.matchLocation(
            userId: userId,
            currentLat: position.latitude,
            currentLng: position.longitude,
          );
          if (match.matchedName != 'Unknown') {
            return match.matchedName;
          }
        } catch (_) {
          // Locations lookup failed (offline, no saved locations yet, etc.)
          // — fall through to raw coordinates below.
        }
      }

      return '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
    } catch (e) {
      return 'Unknown';
    }
  }

  /// Checks whether the student has a calendar event overlapping the
  /// claimed activity's time window. Opt-in only (see
  /// [CalendarSettingsService]) — never requests calendar permission
  /// unless the student has explicitly enabled verification in Profile.
  /// Any failure (permission denied, no calendars, plugin error) falls
  /// back to 0, matching prior behaviour.
  static Future<int> _getCalendarMatch({
    required DateTime claimedStart,
    required DateTime claimedEnd,
  }) async {
    try {
      final enabled = await CalendarSettingsService.isEnabled();
      if (!enabled) return 0;

      final plugin = DeviceCalendarPlugin();

      var permission = await plugin.hasPermissions();
      if (permission.data != true) {
        permission = await plugin.requestPermissions();
      }
      if (permission.data != true) return 0;

      final calendarsResult = await plugin.retrieveCalendars();
      final calendars = calendarsResult.data;
      if (!calendarsResult.isSuccess || calendars == null) return 0;

      for (final calendar in calendars) {
        if (calendar.id == null) continue;

        final eventsResult = await plugin.retrieveEvents(
          calendar.id,
          RetrieveEventsParams(
            startDate: claimedStart.subtract(const Duration(minutes: 30)),
            endDate: claimedEnd.add(const Duration(minutes: 30)),
          ),
        );
        final events = eventsResult.data;
        if (!eventsResult.isSuccess || events == null) continue;

        for (final event in events) {
          final start = event.start;
          final end = event.end;
          if (start == null || end == null) continue;

          final overlaps =
              start.isBefore(claimedEnd) && end.isAfter(claimedStart);
          if (overlaps) return 1;
        }
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  /// Convenience method: collect everything needed for sensor_data at once.
  /// [claimedStart]/[claimedEnd] locate the diary entry's claimed time
  /// window so calendar verification (when enabled) can check for an
  /// overlapping planned event.
  static Future<Map<String, dynamic>> collectAll({
    String? userId,
    DateTime? claimedStart,
    DateTime? claimedEnd,
  }) async {
    final usage = await getCategorizedAppUsage();
    final location = await getCurrentLocationLabel(userId: userId);

    final socialMediaMinutes = usage['social_media_minutes'] as double;
    final entertainmentMinutes = usage['entertainment_minutes'] as double;

    final calendarMatch = (claimedStart != null && claimedEnd != null)
        ? await _getCalendarMatch(
            claimedStart: claimedStart, claimedEnd: claimedEnd)
        : 0;

    return {
      'verified_educational_minutes': usage['verified_educational_minutes'],
      'social_media_minutes': socialMediaMinutes,
      'entertainment_minutes': entertainmentMinutes,
      // Display-only — apps that couldn't be confidently classified as
      // study or distraction (ChatGPT, Chrome, PickMe, etc.). Deliberately
      // left out of distraction_duration below, so it never reaches the
      // classifier features and every existing score/classification stays
      // exactly as it was before this field existed.
      'other_minutes': usage['other_minutes'],
      'app_switch_count': usage['app_switch_count'],
      'gps_location': location,
      'distraction_duration': socialMediaMinutes + entertainmentMinutes,
      'calendar_match': calendarMatch,
      'educational_breakdown': usage['educational_breakdown'],
      'other_breakdown': usage['other_breakdown'],
      'entertainment_breakdown': usage['entertainment_breakdown'],
      'social_media_breakdown': usage['social_media_breakdown'],
    };
  }
}
