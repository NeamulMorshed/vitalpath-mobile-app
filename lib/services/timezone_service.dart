/// timezone_service.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Detects system timezone changes and fires events for the UI to handle.
///
/// Blueprint §1.2 — The Timezone Leap:
///   "The app detects system clock changes (e.g., GMT to PST) and prompts
///    the user to either adapt alarms to local time or maintain the home
///    timezone."
///
/// Detection strategy:
///   Flutter's [WidgetsBindingObserver.didChangeAppLifecycleState] fires when
///   the app resumes from background. This is the ideal hook — timezone changes
///   typically happen when the device is locked (during a flight), so the user
///   sees the prompt immediately upon unlocking.
///
///   On each resume:
///     1. Read the current UTC offset (DateTime.now().timeZoneOffset).
///     2. Compare with the stored [homeTimezoneOffset].
///     3. If they differ by ≥ 1 hour, emit a [TimezoneChangeEvent].
///
/// The UI layer listens to [timezoneChangeStream] and shows [TimezoneLeapModal].
///
/// Note: For production, use the `timezone` package for named timezone IDs
/// rather than raw UTC offsets (handles DST correctly). This implementation
/// uses Duration offsets for simplicity and zero-dependency setup.
/// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Event ─────────────────────────────────────────────────────────────────────
class TimezoneChangeEvent {
  /// The timezone offset stored when the user first set up the app.
  final Duration homeOffset;

  /// The newly detected system offset.
  final Duration newOffset;

  /// Human-readable home timezone string (e.g., "UTC+6:00").
  String get homeLabel => _offsetLabel(homeOffset);

  /// Human-readable new timezone string (e.g., "UTC-8:00").
  String get newLabel => _offsetLabel(newOffset);

  /// The direction and magnitude of the change.
  Duration get delta => newOffset - homeOffset;

  const TimezoneChangeEvent({
    required this.homeOffset,
    required this.newOffset,
  });

  static String _offsetLabel(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs();
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$minutes';
  }

  @override
  String toString() =>
      'TimezoneChangeEvent(home: $homeLabel → new: $newLabel, '
      'delta: ${delta.inHours}h)';
}

// ── User preference ───────────────────────────────────────────────────────────
enum TimezonePreference {
  /// Keep all alarms on the original home timezone.
  keepHome,

  /// Shift all alarms to match the new local timezone.
  adaptToLocal,
}

// ── Service ───────────────────────────────────────────────────────────────────
class TimezoneService with WidgetsBindingObserver {
  static TimezoneService? _instance;
  factory TimezoneService() => _instance ??= TimezoneService._internal();
  TimezoneService._internal();

  // ── Preferences keys ───────────────────────────────────────────────────────
  static const String _homeOffsetKey = 'home_timezone_offset_minutes';
  static const String _prefKey = 'timezone_preference';

  // ── Minimum drift to trigger the prompt (1 hour) ──────────────────────────
  static const Duration _minimumDrift = Duration(hours: 1);

  // ── Streams ────────────────────────────────────────────────────────────────
  final _changeController = StreamController<TimezoneChangeEvent>.broadcast();

  /// Listen to this stream to show [TimezoneLeapModal] when a leap is detected.
  Stream<TimezoneChangeEvent> get timezoneChangeStream =>
      _changeController.stream;

  // ── State ──────────────────────────────────────────────────────────────────
  Duration? _homeOffset;
  TimezonePreference _preference = TimezonePreference.keepHome;
  bool _isInitialised = false;

  Duration? get homeOffset => _homeOffset;
  TimezonePreference get currentPreference => _preference;

  // ── Initialisation ─────────────────────────────────────────────────────────
  Future<void> initialise() async {
    if (_isInitialised) return;

    WidgetsBinding.instance.addObserver(this);
    _isInitialised = true;

    final prefs = await SharedPreferences.getInstance();
    final storedMinutes = prefs.getInt(_homeOffsetKey);

    if (storedMinutes == null) {
      // First launch — record the current timezone as home.
      await _saveHomeOffset(DateTime.now().timeZoneOffset);
    } else {
      _homeOffset = Duration(minutes: storedMinutes);
    }

    final storedPref = prefs.getString(_prefKey);
    if (storedPref == TimezonePreference.adaptToLocal.name) {
      _preference = TimezonePreference.adaptToLocal;
    }

    debugPrint('[Timezone] Initialised. Home: ${_offsetLabel(_homeOffset!)}');
  }

  // ── WidgetsBindingObserver ────────────────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForTimezoneLeap();
    }
  }

  // ── Core detection logic ──────────────────────────────────────────────────
  void _checkForTimezoneLeap() {
    if (_homeOffset == null) return;

    final currentOffset = DateTime.now().timeZoneOffset;
    final drift = (currentOffset - _homeOffset!).abs();

    if (drift >= _minimumDrift) {
      final event = TimezoneChangeEvent(
        homeOffset: _homeOffset!,
        newOffset: currentOffset,
      );
      debugPrint('[Timezone] Leap detected: $event');
      _changeController.add(event);
    }
  }

  // ── User choice handlers ──────────────────────────────────────────────────
  /// Called when user taps "Keep Home Timezone" in [TimezoneLeapModal].
  /// All alarms remain scheduled on the original home timezone.
  Future<void> applyKeepHomeTimezone() async {
    _preference = TimezonePreference.keepHome;
    await _savePreference();
    debugPrint('[Timezone] User chose: Keep Home (${_offsetLabel(_homeOffset!)})');
    // In full implementation: trigger alarm scheduler to NOT shift times.
  }

  /// Called when user taps "Adapt to Local Time" in [TimezoneLeapModal].
  /// All alarms are shifted by the delta to match the new timezone.
  Future<void> applyAdaptToLocal(Duration newOffset) async {
    _preference = TimezonePreference.adaptToLocal;
    await _saveHomeOffset(newOffset); // new location is now "home"
    await _savePreference();
    debugPrint('[Timezone] User chose: Adapt to Local (${_offsetLabel(newOffset)})');
    // In full implementation: trigger alarm scheduler to shift all times by delta.
  }

  // ── Persistence helpers ───────────────────────────────────────────────────
  Future<void> _saveHomeOffset(Duration offset) async {
    _homeOffset = offset;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_homeOffsetKey, offset.inMinutes);
  }

  Future<void> _savePreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _preference.name);
  }

  static String _offsetLabel(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final h = offset.inHours.abs();
    final m = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return 'UTC$sign$h:$m';
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _changeController.close();
  }
}
