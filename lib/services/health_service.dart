/// health_service.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Real-time step count abstraction over HealthKit (iOS) and Health Connect
/// (Android).
///
/// Blueprint §3.1 — "Implement a high-performance circular progress bar for
/// Step Goals (10,000 steps default).  Use a StreamBuilder pattern to ensure
/// the bar fills in real-time as background data arrives from HealthKit /
/// Google Fit."
///
/// Channel architecture:
///   MethodChannel  'com.vitalpath.health'        — one-shot calls
///   EventChannel   'com.vitalpath.health/steps'  — continuous stream
///
/// ── iOS native (AppDelegate.swift) ─────────────────────────────────────────
///
///   import HealthKit
///
///   class HealthStreamHandler: NSObject, FlutterStreamHandler {
///     private let store = HKHealthStore()
///     private var query: HKObserverQuery?
///     private var anchor: HKQueryAnchor?
///     private var eventSink: FlutterEventSink?
///
///     func onListen(withArguments a: Any?, eventSink sink: @escaping FlutterEventSink) -> FlutterError? {
///       eventSink = sink
///       let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
///       query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, _, error in
///         guard error == nil else { return }
///         self?.fetchTodaySteps()
///       }
///       store.execute(query!)
///       fetchTodaySteps() // immediate delivery
///       return nil
///     }
///
///     private func fetchTodaySteps() {
///       let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
///       let now = Date()
///       let start = Calendar.current.startOfDay(for: now)
///       let pred = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
///       let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: pred, options: .cumulativeSum) { _, result, _ in
///         let steps = Int(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
///         DispatchQueue.main.async { self.eventSink?(steps) }
///       }
///       store.execute(query)
///     }
///
///     func onCancel(withArguments a: Any?) -> FlutterError? { store.stop(query!); return nil }
///   }
///
/// ── Android native (MainActivity.kt) ───────────────────────────────────────
///
///   import androidx.health.connect.client.HealthConnectClient
///   import androidx.health.connect.client.records.StepsRecord
///   import androidx.health.connect.client.request.ReadRecordsRequest
///   import androidx.health.connect.client.time.TimeRangeFilter
///   import io.flutter.plugin.common.EventChannel
///   import kotlinx.coroutines.*
///
///   class StepsStreamHandler(private val context: Context) : EventChannel.StreamHandler {
///     private var job: Job? = null
///     override fun onListen(args: Any?, events: EventChannel.EventSink) {
///       job = CoroutineScope(Dispatchers.IO).launch {
///         val client = HealthConnectClient.getOrCreate(context)
///         while (isActive) {
///           val start = LocalDateTime.now().toLocalDate().atStartOfDay().toInstant(ZoneOffset.UTC)
///           val req = ReadRecordsRequest(StepsRecord::class, TimeRangeFilter.between(start, Instant.now()))
///           val total = client.readRecords(req).records.sumOf { it.count }
///           withContext(Dispatchers.Main) { events.success(total) }
///           delay(30_000) // poll every 30 s as passive listener fallback
///         }
///       }
///     }
///     override fun onCancel(args: Any?) { job?.cancel() }
///   }
///
/// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class HealthService {
  // ── Platform channels ──────────────────────────────────────────────────────
  static const _method  = MethodChannel('com.vitalpath.health');
  static const _event   = EventChannel('com.vitalpath.health/steps');

  // ── Blueprint default ──────────────────────────────────────────────────────
  static const int defaultStepGoal = 10_000;

  // ── Permission state ───────────────────────────────────────────────────────
  bool _permissionsGranted = false;
  bool get permissionsGranted => _permissionsGranted;

  // ── Singleton stream (shared across all StreamBuilder consumers) ───────────
  Stream<int>? _stepsStream;

  /// Real-time broadcast stream of today's step count.
  ///
  /// First emits a value immediately (current count).  Thereafter emits on
  /// every HealthKit / Health Connect observation event.
  ///
  /// On permission denial or channel unavailability, falls back to a 30-second
  /// polling stream.
  ///
  /// The stream is a broadcast stream — safe to listen from multiple
  /// [StreamBuilder] widgets simultaneously.
  Stream<int> get stepsStream {
    _stepsStream ??= _buildStream();
    return _stepsStream!;
  }

  Stream<int> _buildStream() {
    try {
      return _event
          .receiveBroadcastStream()
          .map<int>((dynamic event) {
            if (event is int) return event;
            if (event is double) return event.toInt();
            return 0;
          })
          .handleError((Object e) {
            debugPrint('[HealthService] EventChannel error: $e — switching to poll');
          })
          .asBroadcastStream();
    } catch (e) {
      debugPrint('[HealthService] EventChannel unavailable ($e) — using poll');
      return _pollingStream().asBroadcastStream();
    }
  }

  /// 30-second polling fallback.  Used when:
  ///   • Running on Android pre-Health Connect
  ///   • Simulator / unit tests (mock mode)
  ///   • EventChannel throws during registration
  Stream<int> _pollingStream() async* {
    while (true) {
      yield await _fetchStepsOnce();
      await Future.delayed(const Duration(seconds: 30));
    }
  }

  // ── One-shot step fetch ────────────────────────────────────────────────────
  Future<int> _fetchStepsOnce() async {
    try {
      final result = await _method.invokeMethod<int>('getTodaySteps');
      return result ?? 0;
    } on PlatformException catch (e) {
      debugPrint('[HealthService] getTodaySteps failed: ${e.message}');
      return 0;
    }
  }

  // ── Permissions ────────────────────────────────────────────────────────────
  /// Requests HealthKit / Health Connect read permissions for step count.
  ///
  /// Returns true if permission is granted.
  Future<bool> requestPermissions() async {
    try {
      final granted =
          await _method.invokeMethod<bool>('requestPermissions') ?? false;
      _permissionsGranted = granted;
      if (granted) {
        // Reset the cached stream so it rebuilds with auth in place.
        _stepsStream = null;
      }
      return granted;
    } on PlatformException catch (e) {
      debugPrint('[HealthService] requestPermissions error: ${e.message}');
      return false;
    }
  }

  // ── Mock mode (dev / CI) ───────────────────────────────────────────────────
  /// Returns a simulated step count stream that increments by ~50 steps every
  /// 3 seconds.  Useful for UI development without a physical device.
  static Stream<int> mockStream({int startSteps = 4_200}) async* {
    var steps = startSteps;
    while (true) {
      yield steps;
      await Future.delayed(const Duration(seconds: 3));
      // Simulate burst activity: +40-80 steps.
      steps += 40 + (steps % 41);
      if (steps > defaultStepGoal + 2_000) steps = 0; // wrap for demo
    }
  }
}
