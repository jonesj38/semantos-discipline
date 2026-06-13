---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/lib/services/screen_time_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.748791+00:00
---

# archive/apps-navigation_app/lib/services/screen_time_service.dart

```dart
import 'dart:async';

/// Categorisation of apps by attention quality
enum AppCategory {
  productive,    // Work tools, learning apps, creation tools
  neutral,       // Utilities, system apps, maps
  consumptive,   // Social media, news, entertainment
  destructive,   // Gambling, doom-scrolling patterns
  consciousness, // This app, meditation apps, journaling
}

/// Represents usage data for a single app
class AppUsageData {
  final String packageName;
  final String appName;
  final Duration totalTime;
  final int openCount;
  final DateTime firstUsed;
  final DateTime lastUsed;
  final AppCategory category;

  AppUsageData({
    required this.packageName,
    required this.appName,
    required this.totalTime,
    required this.openCount,
    required this.firstUsed,
    required this.lastUsed,
    this.category = AppCategory.neutral,
  });

  /// Minutes spent
  double get minutes => totalTime.inSeconds / 60.0;
}

/// Daily screen time summary
class ScreenTimeSummary {
  final DateTime date;
  final Duration totalScreenTime;
  final Map<AppCategory, Duration> timeByCategory;
  final List<AppUsageData> topApps;
  final int totalPickups;
  final Duration longestSession;

  ScreenTimeSummary({
    required this.date,
    required this.totalScreenTime,
    required this.timeByCategory,
    required this.topApps,
    required this.totalPickups,
    required this.longestSession,
  });

  /// What percentage of time was spent on consumptive/destructive apps
  double get distractionRatio {
    final distractedTime =
        (timeByCategory[AppCategory.consumptive]?.inSeconds ?? 0) +
        (timeByCategory[AppCategory.destructive]?.inSeconds ?? 0);
    if (totalScreenTime.inSeconds == 0) return 0;
    return distractedTime / totalScreenTime.inSeconds;
  }

  /// Attention score from 0-100 based on usage patterns
  int get attentionScore {
    final prodTime =
        (timeByCategory[AppCategory.productive]?.inSeconds ?? 0) +
        (timeByCategory[AppCategory.consciousness]?.inSeconds ?? 0);
    final wasteTime =
        (timeByCategory[AppCategory.consumptive]?.inSeconds ?? 0) +
        (timeByCategory[AppCategory.destructive]?.inSeconds ?? 0);
    final total = totalScreenTime.inSeconds;
    if (total == 0) return 50;

    // Base score from productive vs consumptive ratio
    final ratio = (prodTime - wasteTime) / total;
    final baseScore = ((ratio + 1) / 2 * 100).clamp(0, 100).round();

    // Penalty for excessive pickups (>100/day is scattered attention)
    final pickupPenalty = (totalPickups > 100)
        ? ((totalPickups - 100) * 0.2).clamp(0, 20).round()
        : 0;

    return (baseScore - pickupPenalty).clamp(0, 100);
  }
}

/// Monitors screen time and app usage via Android UsageStatsManager.
/// Feeds attention data into the Paskian learning graph and accountability system.
class ScreenTimeService {
  bool _hasPermission = false;

  /// Known app categorisations (user can override)
  final Map<String, AppCategory> _appCategories = {
    // Social media — consumptive
    'com.instagram.android': AppCategory.consumptive,
    'com.twitter.android': AppCategory.consumptive,
    'com.facebook.katana': AppCategory.consumptive,
    'com.zhiliaoapp.musically': AppCategory.consumptive, // TikTok
    'com.reddit.frontpage': AppCategory.consumptive,
    'com.snapchat.android': AppCategory.consumptive,

    // Messaging — neutral (communication, not consumption)
    'com.whatsapp': AppCategory.neutral,
    'org.telegram.messenger': AppCategory.neutral,
    'com.discord': AppCategory.neutral,

    // Productivity — productive
    'com.google.android.apps.docs': AppCategory.productive,
    'com.google.android.calendar': AppCategory.productive,
    'com.todoist': AppCategory.productive,
    'com.notion.id': AppCategory.productive,

    // Entertainment — consumptive
    'com.google.android.youtube': AppCategory.consumptive,
    'com.netflix.mediaclient': AppCategory.consumptive,
    'com.spotify.music': AppCategory.neutral, // music can aid focus

    // Browsers — depends on usage, default neutral
    'com.android.chrome': AppCategory.neutral,
    'org.mozilla.firefox': AppCategory.neutral,

    // Games — consumptive
    // (detected by category from Play Store metadata)
  };

  /// Check and request UsageStats permission
  Future<bool> requestPermission() async {
    // TODO: Check if PACKAGE_USAGE_STATS permission is granted
    // if (!await UsageStats.checkUsagePermission()) {
    //   await UsageStats.grantUsagePermission();
    // }
    // _hasPermission = await UsageStats.checkUsagePermission();
    _hasPermission = false; // Placeholder
    return _hasPermission;
  }

  bool get hasPermission => _hasPermission;

  /// Get usage data for a time range
  Future<List<AppUsageData>> getUsage({
    required DateTime start,
    required DateTime end,
  }) async {
    if (!_hasPermission) return [];

    // TODO: Query Android UsageStatsManager
    // final stats = await UsageStats.queryUsageStats(start, end);
    // return stats.map((s) => AppUsageData(
    //   packageName: s.packageName,
    //   appName: s.appName ?? s.packageName,
    //   totalTime: Duration(milliseconds: s.totalTimeInForeground ?? 0),
    //   openCount: s.launchCount ?? 0,
    //   firstUsed: DateTime.fromMillisecondsSinceEpoch(s.firstTimeStamp ?? 0),
    //   lastUsed: DateTime.fromMillisecondsSinceEpoch(s.lastTimeStamp ?? 0),
    //   category: _categorizeApp(s.packageName ?? ''),
    // )).toList();

    return []; // Placeholder
  }

  /// Get today's screen time summary
  Future<ScreenTimeSummary> getTodaySummary() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final usage = await getUsage(start: startOfDay, end: now);

    final timeByCategory = <AppCategory, Duration>{};
    var totalTime = Duration.zero;

    for (final app in usage) {
      totalTime += app.totalTime;
      timeByCategory[app.category] =
          (timeByCategory[app.category] ?? Duration.zero) + app.totalTime;
    }

    // Sort by time descending
    usage.sort((a, b) => b.totalTime.compareTo(a.totalTime));

    return ScreenTimeSummary(
      date: startOfDay,
      totalScreenTime: totalTime,
      timeByCategory: timeByCategory,
      topApps: usage.take(10).toList(),
      totalPickups: 0, // TODO: Get from system
      longestSession: Duration.zero, // TODO: Calculate from events
    );
  }

  /// Get weekly trend data for the attention dimension
  Future<List<ScreenTimeSummary>> getWeeklyTrend() async {
    final now = DateTime.now();
    final summaries = <ScreenTimeSummary>[];

    for (int i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final start = DateTime(day.year, day.month, day.day);
      final end = start.add(const Duration(days: 1));
      final usage = await getUsage(start: start, end: end);

      final timeByCategory = <AppCategory, Duration>{};
      var totalTime = Duration.zero;
      for (final app in usage) {
        totalTime += app.totalTime;
        timeByCategory[app.category] =
            (timeByCategory[app.category] ?? Duration.zero) + app.totalTime;
      }

      summaries.add(ScreenTimeSummary(
        date: start,
        totalScreenTime: totalTime,
        timeByCategory: timeByCategory,
        topApps: usage.take(5).toList(),
        totalPickups: 0,
        longestSession: Duration.zero,
      ));
    }

    return summaries;
  }

  /// Override app category (user learning)
  void setCategoryForApp(String packageName, AppCategory category) {
    _appCategories[packageName] = category;
    // TODO: Persist to local storage
  }

  AppCategory _categorizeApp(String packageName) {
    return _appCategories[packageName] ?? AppCategory.neutral;
  }

  /// Generate attention insights from screen time data.
  /// Called by the Paskian adapter to feed the constraint graph.
  Future<Map<String, dynamic>> generateAttentionInsights() async {
    final summary = await getTodaySummary();
    final weeklyTrend = await getWeeklyTrend();

    // Calculate trend direction
    final recentScores =
        weeklyTrend.map((s) => s.attentionScore).toList();
    final trending = recentScores.length >= 3
        ? (recentScores.last - recentScores.first) / recentScores.length
        : 0.0;

    return {
      'todayScore': summary.attentionScore,
      'distractionRatio': summary.distractionRatio,
      'totalScreenMinutes': summary.totalScreenTime.inMinutes,
      'topDistractors': summary.topApps
          .where((a) =>
              a.category == AppCategory.consumptive ||
              a.category == AppCategory.destructive)
          .take(3)
          .map((a) => {'app': a.appName, 'minutes': a.minutes.round()})
          .toList(),
      'trendDirection': trending > 0.5
          ? 'improving'
          : trending < -0.5
              ? 'declining'
              : 'stable',
      'weeklyScores': recentScores,
    };
  }

  void dispose() {}
}

```
