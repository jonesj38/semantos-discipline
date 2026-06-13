---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/lib/services/notification_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.749407+00:00
---

# archive/apps-navigation_app/lib/services/notification_service.dart

```dart
import 'dart:async';

/// Notification channels for different accountability touchpoints
enum NotificationChannel {
  morningIntention(
    id: 'morning_intention',
    name: 'Morning Intention',
    description: 'Daily morning intention and focus setting',
    hour: 7,
    minute: 0,
  ),
  middayPulse(
    id: 'midday_pulse',
    name: 'Midday Pulse',
    description: 'Quick dimension check-in',
    hour: 12,
    minute: 30,
  ),
  eveningReview(
    id: 'evening_review',
    name: 'Evening Review',
    description: 'Daily review: wins, improvements, tomorrow',
    hour: 21,
    minute: 0,
  ),
  prizeWin(
    id: 'prize_win',
    name: 'Prize Win',
    description: 'You won a prize!',
    hour: 0,
    minute: 0,
  ),
  streakWarning(
    id: 'streak_warning',
    name: 'Streak Warning',
    description: 'Your streak is at risk',
    hour: 20,
    minute: 0,
  ),
  vestingMilestone(
    id: 'vesting_milestone',
    name: 'Vesting Milestone',
    description: 'Winnings have vested',
    hour: 0,
    minute: 0,
  );

  final String id;
  final String name;
  final String description;
  final int hour;
  final int minute;

  const NotificationChannel({
    required this.id,
    required this.name,
    required this.description,
    required this.hour,
    required this.minute,
  });
}

/// Manages Android notifications and WorkManager scheduled tasks.
/// This is the bridge between the accountability system and the OS.
class NotificationService {
  bool _initialized = false;

  /// Initialize notification channels and WorkManager
  Future<void> initialize() async {
    if (_initialized) return;

    // TODO: Initialize flutter_local_notifications
    // final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    // const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    // const settings = InitializationSettings(android: androidSettings);
    // await flutterLocalNotificationsPlugin.initialize(settings);

    // TODO: Create Android notification channels
    // for (final channel in NotificationChannel.values) {
    //   await flutterLocalNotificationsPlugin
    //       .resolvePlatformSpecificImplementation<
    //           AndroidFlutterLocalNotificationsPlugin>()
    //       ?.createNotificationChannel(AndroidNotificationChannel(
    //         channel.id,
    //         channel.name,
    //         description: channel.description,
    //         importance: Importance.high,
    //       ));
    // }

    // TODO: Register WorkManager tasks
    // await Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
    // _scheduleAccountabilityTasks();

    _initialized = true;
  }

  /// Schedule the three daily accountability notifications
  Future<void> scheduleAccountabilityTasks() async {
    // Morning intention — 7:00 AM
    await _scheduleDailyTask(
      uniqueName: 'morning_intention',
      channel: NotificationChannel.morningIntention,
      title: 'Good morning — set your intention',
      body: 'What dimension are you focusing on today?',
    );

    // Midday pulse — 12:30 PM
    await _scheduleDailyTask(
      uniqueName: 'midday_pulse',
      channel: NotificationChannel.middayPulse,
      title: 'Midday pulse check',
      body: 'Quick score — how\'s your focus dimension going? (30 seconds)',
    );

    // Evening review — 9:00 PM
    await _scheduleDailyTask(
      uniqueName: 'evening_review',
      channel: NotificationChannel.eveningReview,
      title: 'Evening review time',
      body: '3 wins, 3 improvements, tomorrow\'s intention',
    );
  }

  /// Show an immediate notification (e.g., prize win)
  Future<void> showPrizeNotification({
    required int satoshis,
    required String tierName,
  }) async {
    final amount = (satoshis / 100000000).toStringAsFixed(
        satoshis > 100000000 ? 2 : 4);
    // TODO: Show notification via flutter_local_notifications
    // await flutterLocalNotificationsPlugin.show(
    //   DateTime.now().millisecondsSinceEpoch ~/ 1000,
    //   '🎉 You won $tierName!',
    //   '$amount BSV just dropped. Keep your streak alive to vest it.',
    //   NotificationDetails(android: AndroidNotificationDetails(
    //     NotificationChannel.prizeWin.id,
    //     NotificationChannel.prizeWin.name,
    //     channelDescription: NotificationChannel.prizeWin.description,
    //     importance: Importance.high,
    //     priority: Priority.high,
    //   )),
    // );
  }

  /// Warn user their streak is at risk (no check-in today)
  Future<void> showStreakWarning({
    required int currentStreak,
    required int unvestedSatoshis,
  }) async {
    final bsvAtRisk = (unvestedSatoshis / 100000000).toStringAsFixed(4);
    // TODO: Show streak warning notification
    // 'Day $currentStreak streak at risk. $bsvAtRisk BSV unvested.'
  }

  Future<void> _scheduleDailyTask({
    required String uniqueName,
    required NotificationChannel channel,
    required String title,
    required String body,
  }) async {
    // TODO: Use Workmanager to schedule periodic task
    // await Workmanager().registerPeriodicTask(
    //   uniqueName,
    //   uniqueName,
    //   frequency: const Duration(hours: 24),
    //   initialDelay: _calculateInitialDelay(channel.hour, channel.minute),
    //   constraints: Constraints(networkType: NetworkType.not_required),
    //   inputData: {'title': title, 'body': body, 'channelId': channel.id},
    // );
  }

  /// Calculate delay until next occurrence of a given time
  Duration _calculateInitialDelay(int targetHour, int targetMinute) {
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, targetHour, targetMinute);
    if (target.isBefore(now)) {
      target = target.add(const Duration(days: 1));
    }
    return target.difference(now);
  }

  /// Update notification times (user can customize)
  Future<void> updateSchedule({
    int? morningHour,
    int? middayHour,
    int? eveningHour,
  }) async {
    // Cancel existing and reschedule with new times
    // TODO: Workmanager().cancelAll() then re-register
  }

  void dispose() {}
}

/// WorkManager callback dispatcher (must be top-level function)
// @pragma('vm:entry-point')
// void callbackDispatcher() {
//   Workmanager().executeTask((task, inputData) async {
//     // Show the notification based on task name
//     final title = inputData?['title'] ?? 'Navigation';
//     final body = inputData?['body'] ?? 'Time for your practice';
//     final channelId = inputData?['channelId'] ?? 'morning_intention';
//     // ... show notification
//     return true;
//   });
// }

```
