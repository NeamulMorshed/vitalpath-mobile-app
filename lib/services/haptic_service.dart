/// haptic_service.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Behavioral haptic patterns for VitalPath.
///
/// Blueprint §4 — Behavioral Feedback:
///   "Distinct haptic patterns differentiate between 'Medicine Reminders'
///    and 'Goal Success'."
///
/// Pattern mapping:
///   • [medicineReminder()]  → Two short, sharp pulses.
///                             Conveys urgency and clinical precision.
///                             Platform: iOS CoreHaptics impact + pause + impact.
///                             Android: short + short via MethodChannel.
///
///   • [goalSuccess()]       → Long, building celebratory pattern.
///                             Conveys achievement and positive reinforcement.
///                             Platform: iOS CoreHaptics notification success.
///                             Android: long + short + long via MethodChannel.
///
///   • [appointmentConfirmed()] → Single medium pulse. Clear and affirming.
///
///   • [criticalWarning()]   → Heavy single impact. Highest available urgency.
///
/// Implementation:
///   Flutter's built-in [HapticFeedback] provides four basic patterns.
///   For the medicine/goal distinction, we use a platform channel to access
///   native CoreHaptics (iOS) and VibrationEffect (Android) for richer patterns.
///   The fallback chain: custom pattern → HapticFeedback.vibrate() → silent.
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/services.dart';

class HapticService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static HapticService? _instance;
  factory HapticService() => _instance ??= HapticService._internal();
  HapticService._internal();

  // ── Platform channel for native haptics ───────────────────────────────────
  static const _channel = MethodChannel('com.vitalpath.haptics');

  // ── Pattern definitions ───────────────────────────────────────────────────
  // Each entry is [intensityMs, pauseMs] pairs.
  // iOS: maps to CoreHaptics intensity/sharpness.
  // Android: maps to VibrationEffect.createWaveform().
  static const _medicineReminderPattern = [
    {'duration': 80, 'intensity': 0.9, 'sharpness': 1.0},  // sharp pulse 1
    {'pause': 120},
    {'duration': 80, 'intensity': 0.9, 'sharpness': 1.0},  // sharp pulse 2
  ];

  static const _goalSuccessPattern = [
    {'duration': 60, 'intensity': 0.5, 'sharpness': 0.3},  // soft start
    {'pause': 40},
    {'duration': 80, 'intensity': 0.7, 'sharpness': 0.5},  // build
    {'pause': 40},
    {'duration': 120, 'intensity': 1.0, 'sharpness': 0.7}, // peak
    {'pause': 60},
    {'duration': 60, 'intensity': 0.4, 'sharpness': 0.2},  // soft fade
  ];

  // ── Public API ────────────────────────────────────────────────────────────

  /// Two short, sharp pulses — "Take your medicine."
  /// Falls back to two rapid HapticFeedback.lightImpact() calls.
  Future<void> medicineReminder() async {
    try {
      await _channel.invokeMethod('playPattern', {
        'pattern': _medicineReminderPattern,
        'type': 'medicineReminder',
      });
    } catch (_) {
      // Fallback: two quick impacts
      HapticFeedback.lightImpact();
      await Future.delayed(const Duration(milliseconds: 200));
      HapticFeedback.lightImpact();
    }
  }

  /// Long, celebratory multi-pulse — "You reached your goal!"
  /// Falls back to HapticFeedback.heavyImpact() + medium.
  Future<void> goalSuccess() async {
    try {
      await _channel.invokeMethod('playPattern', {
        'pattern': _goalSuccessPattern,
        'type': 'goalSuccess',
      });
    } catch (_) {
      // Fallback: escalating haptics
      HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 80));
      HapticFeedback.heavyImpact();
    }
  }

  /// Single medium confirmation pulse — "Appointment confirmed."
  Future<void> appointmentConfirmed() async {
    try {
      await _channel.invokeMethod('playPattern', {
        'pattern': [
          {'duration': 100, 'intensity': 0.8, 'sharpness': 0.6},
        ],
        'type': 'appointmentConfirmed',
      });
    } catch (_) {
      HapticFeedback.mediumImpact();
    }
  }

  /// Heavy single impact — critical safety alerts (overdose warning, etc.).
  Future<void> criticalWarning() async {
    try {
      await _channel.invokeMethod('playPattern', {
        'pattern': [
          {'duration': 150, 'intensity': 1.0, 'sharpness': 1.0},
        ],
        'type': 'criticalWarning',
      });
    } catch (_) {
      HapticFeedback.heavyImpact();
    }
  }

  /// Standard light tap — navigation, button press, general UI feedback.
  void lightTap() => HapticFeedback.lightImpact();

  /// Standard selection change.
  void selectionClick() => HapticFeedback.selectionClick();
}


// ─────────────────────────────────────────────────────────────────────────────
// iOS NATIVE SIDE (Swift) — add to ios/Runner/AppDelegate.swift
// ─────────────────────────────────────────────────────────────────────────────
// import CoreHaptics
//
// func registerHapticsChannel(controller: FlutterViewController) {
//   let channel = FlutterMethodChannel(
//     name: "com.vitalpath.haptics",
//     binaryMessenger: controller.binaryMessenger
//   )
//   var engine: CHHapticEngine?
//   try? engine = CHHapticEngine()
//   try? engine?.start()
//
//   channel.setMethodCallHandler { call, result in
//     guard call.method == "playPattern",
//           let args = call.arguments as? [String: Any],
//           let pattern = args["pattern"] as? [[String: Any]] else {
//       result(FlutterMethodNotImplemented)
//       return
//     }
//
//     var events: [CHHapticEvent] = []
//     var time: Double = 0
//
//     for entry in pattern {
//       if let pause = entry["pause"] as? Int {
//         time += Double(pause) / 1000.0
//       } else if let duration = entry["duration"] as? Int {
//         let intensity = CHHapticEventParameter(
//           parameterID: .hapticIntensity,
//           value: Float(entry["intensity"] as? Double ?? 1.0))
//         let sharpness = CHHapticEventParameter(
//           parameterID: .hapticSharpness,
//           value: Float(entry["sharpness"] as? Double ?? 0.5))
//         let event = CHHapticEvent(
//           eventType: .hapticContinuous,
//           parameters: [intensity, sharpness],
//           relativeTime: time,
//           duration: Double(duration) / 1000.0)
//         events.append(event)
//         time += Double(duration) / 1000.0
//       }
//     }
//
//     try? engine?.makePlayer(
//       with: try! CHHapticPattern(events: events, parameters: [])
//     ).start(atTime: 0)
//     result(nil)
//   }
// }
//
// ─────────────────────────────────────────────────────────────────────────────
// ANDROID NATIVE SIDE (Kotlin) — add to MainActivity.kt
// ─────────────────────────────────────────────────────────────────────────────
// import android.os.VibrationEffect
// import android.os.Vibrator
//
// MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
//               "com.vitalpath.haptics").setMethodCallHandler { call, result ->
//   if (call.method == "playPattern") {
//     val args = call.arguments as Map<*, *>
//     val pattern = args["pattern"] as List<Map<*, *>>
//     val type = args["type"] as String
//
//     val timings = mutableListOf<Long>()
//     val amplitudes = mutableListOf<Int>()
//     var isOff = true   // patterns start with an off interval
//
//     for (entry in pattern) {
//       if (entry.containsKey("pause")) {
//         timings.add((entry["pause"] as Int).toLong())
//         amplitudes.add(0)
//       } else {
//         val duration = (entry["duration"] as Int).toLong()
//         val intensity = ((entry["intensity"] as Double) * 255).toInt()
//         timings.add(duration)
//         amplitudes.add(intensity.coerceIn(1, 255))
//       }
//     }
//
//     val vibrator = getSystemService(VIBRATOR_SERVICE) as Vibrator
//     if (android.os.Build.VERSION.SDK_INT >= 26) {
//       vibrator.vibrate(
//         VibrationEffect.createWaveform(
//           timings.toLongArray(),
//           amplitudes.toIntArray(),
//           -1
//         )
//       )
//     } else {
//       vibrator.vibrate(timings.sum())
//     }
//     result.success(null)
//   }
// }
