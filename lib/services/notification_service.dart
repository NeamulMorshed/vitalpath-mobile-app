/// notification_service.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Notification management with Silent Mode Detection for VitalPath.
///
/// Blueprint §1.2 — Notification Fatigue:
///   "After five ignored notifications, the system triggers 'Silent Mode
///    Detection' and suggests shifting to 'Critical Alerts'."
///
/// Architecture:
///   • Each notification channel (medicine, goal, appointment) has an
///     independent ignored-count tracked in SharedPreferences.
///   • When a channel's ignored count reaches [_silentModeThreshold] (5),
///     [silentModeDetectedStream] emits a [SilentModeEvent].
///   • The UI listens to this stream and shows a prompt offering to escalate
///     to "Critical Alerts" (iOS) or a persistent notification (Android).
///   • "Critical Alerts" on iOS bypass Do Not Disturb and mute switches.
///   • Acknowledged / dismissed notifications decrement the ignored count.
///
/// Notification channels:
///   'medicine_reminder' — scheduled dose reminders
///   'goal_success'      — achievement notifications
///   'appointment'       — appointment confirmations/reminders
///
/// Dependencies: flutter_local_notifications: ^17.2.2
/// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Channel IDs ───────────────────────────────────────────────────────────────
abstract class NotificationChannel {
  static const String medicineReminder = 'medicine_reminder';
  static const String goalSuccess = 'goal_success';
  static const String appointment = 'appointment';
  static const String criticalAlert = 'critical_alert';

  static const List<String> all = [
    medicineReminder,
    goalSuccess,
    appointment,
  ];
}

// ── Silent Mode Event ─────────────────────────────────────────────────────────
class SilentModeEvent {
  final String channelId;
  final int ignoredCount;

  const SilentModeEvent({
    required this.channelId,
    required this.ignoredCount,
  });

  String get channelDisplayName {
    switch (channelId) {
      case NotificationChannel.medicineReminder:
        return 'Medicine Reminders';
      case NotificationChannel.goalSuccess:
        return 'Goal Achievements';
      case NotificationChannel.appointment:
        return 'Appointment Alerts';
      default:
        return channelId;
    }
  }
}

// ── Service ───────────────────────────────────────────────────────────────────
class NotificationService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static NotificationService? _instance;
  factory NotificationService() =>
      _instance ??= NotificationService._internal();
  NotificationService._internal();

  // ── Blueprint §1.2: threshold = 5 ignored notifications ──────────────────
  static const int _silentModeThreshold = 5;

  // ── SharedPreferences key prefixes ────────────────────────────────────────
  static const String _ignoredPrefix = 'notif_ignored_';
  static const String _criticalEnabledPrefix = 'notif_critical_';
  static const String _channelEnabledPrefix = 'notif_enabled_';

  // ── Streams ────────────────────────────────────────────────────────────────
  final _silentModeController =
      StreamController<SilentModeEvent>.broadcast();

  /// Emits when a channel's ignored count reaches [_silentModeThreshold].
  /// Listen in the root widget to show the Critical Alerts prompt.
  Stream<SilentModeEvent> get silentModeDetectedStream =>
      _silentModeController.stream;

  // ── Initialisation ─────────────────────────────────────────────────────────
  Future<void> initialise() async {
    // Real implementation uses flutter_local_notifications:
    //
    // final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    // await flutterLocalNotificationsPlugin.initialize(
    //   InitializationSettings(
    //     android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    //     iOS: DarwinInitializationSettings(
    //       requestCriticalPermission: true, // for Critical Alerts
    //       onDidReceiveNotificationResponse: _onNotificationResponse,
    //     ),
    //   ),
    //   onDidReceiveNotificationResponse: _onNotificationResponse,
    // );
    debugPrint('[Notifications] Service initialised.');
  }

  // ── Notification response tracking ────────────────────────────────────────

  /// Call this when a notification is DISMISSED (swiped away / ignored).
  /// Increments the ignored counter and checks the silent mode threshold.
  Future<void> onNotificationDismissed(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_ignoredPrefix$channelId';
    final current = prefs.getInt(key) ?? 0;
    final updated = current + 1;
    await prefs.setInt(key, updated);

    debugPrint(
        '[Notifications] $channelId dismissed. Count: $updated / $_silentModeThreshold');

    // ── SILENT MODE DETECTION ─────────────────────────────────────────────
    if (updated >= _silentModeThreshold) {
      final event = SilentModeEvent(
        channelId: channelId,
        ignoredCount: updated,
      );
      _silentModeController.add(event);
      debugPrint('[Notifications] Silent Mode detected for $channelId!');
    }
  }

  /// Call this when a notification is ACKNOWLEDGED (tapped or acted upon).
  /// Resets the ignored counter for that channel.
  Future<void> onNotificationAcknowledged(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_ignoredPrefix$channelId', 0);
    debugPrint('[Notifications] $channelId acknowledged. Counter reset.');
  }

  // ── Critical Alerts escalation ────────────────────────────────────────────

  /// Enables Critical Alerts for [channelId].
  ///
  /// iOS: Requests iOS Critical Alert entitlement permission (requires Apple
  ///      entitlement approval for healthcare apps).
  /// Android: Schedules as a high-priority persistent notification.
  Future<bool> enableCriticalAlerts(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_criticalEnabledPrefix$channelId', true);

    // Reset ignored counter — the user has actively addressed the issue.
    await prefs.setInt('$_ignoredPrefix$channelId', 0);

    // Real iOS implementation:
    // final bool? granted = await flutterLocalNotificationsPlugin
    //   .resolvePlatformSpecificImplementation<
    //     IOSFlutterLocalNotificationsPlugin>()
    //   ?.requestPermissions(critical: true);
    // return granted ?? false;

    debugPrint('[Notifications] Critical Alerts enabled for $channelId');
    return true;
  }

  Future<void> disableCriticalAlerts(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_criticalEnabledPrefix$channelId', false);
    debugPrint('[Notifications] Critical Alerts disabled for $channelId');
  }

  Future<bool> isCriticalAlertsEnabled(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_criticalEnabledPrefix$channelId') ?? false;
  }

  // ── Channel enable/disable ────────────────────────────────────────────────
  Future<void> setChannelEnabled(String channelId, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_channelEnabledPrefix$channelId', enabled);
  }

  Future<bool> isChannelEnabled(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_channelEnabledPrefix$channelId') ?? true;
  }

  // ── Ignored count queries ─────────────────────────────────────────────────
  Future<int> getIgnoredCount(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_ignoredPrefix$channelId') ?? 0;
  }

  /// Returns a map of all channel IDs to their current ignored counts.
  Future<Map<String, int>> getAllIgnoredCounts() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final ch in NotificationChannel.all)
        ch: prefs.getInt('$_ignoredPrefix$ch') ?? 0,
    };
  }

  // ── Schedule helpers (stub — full impl uses flutter_local_notifications) ──

  /// Schedules a medicine reminder notification.
  /// [hapticType] is passed to the native side to play the correct haptic
  /// pattern on delivery.
  Future<void> scheduleMedicineReminder({
    required int id,
    required String medicineName,
    required DateTime scheduledAt,
    String? body,
  }) async {
    if (!await isChannelEnabled(NotificationChannel.medicineReminder)) return;

    // Real implementation:
    // await flutterLocalNotificationsPlugin.zonedSchedule(
    //   id,
    //   'Medicine Reminder',
    //   body ?? 'Time to take $medicineName',
    //   tz.TZDateTime.from(scheduledAt, tz.local),
    //   NotificationDetails(
    //     android: AndroidNotificationDetails(
    //       NotificationChannel.medicineReminder,
    //       'Medicine Reminders',
    //       importance: Importance.high,
    //       priority: Priority.high,
    //     ),
    //     iOS: DarwinNotificationDetails(
    //       sound: 'medicine_reminder.aiff',
    //       criticalSound: await isCriticalAlertsEnabled(
    //         NotificationChannel.medicineReminder),
    //     ),
    //   ),
    //   payload: 'medicine:${id}',
    //   androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    //   uiLocalNotificationDateInterpretation:
    //     UILocalNotificationDateInterpretation.absoluteTime,
    // );
    debugPrint('[Notifications] Scheduled medicine reminder for $medicineName at $scheduledAt');
  }

  /// Fires a goal success notification immediately with celebratory haptic.
  Future<void> notifyGoalSuccess({
    required String goalName,
    String? body,
  }) async {
    if (!await isChannelEnabled(NotificationChannel.goalSuccess)) return;
    debugPrint('[Notifications] Goal success: $goalName');
  }

  Future<void> dispose() async {
    await _silentModeController.close();
  }
}
