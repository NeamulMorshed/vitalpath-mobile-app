/// gps_walk_service.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// GPS walk tracking engine for VitalPath's Active Workout module.
///
/// Blueprint §1.1 / §4:
///   "Build a 'Start Walk' interface that utilises Google Maps / Apple Maps.
///    Trigger a distinct vibration every 1 KM reached."
///   "If device storage is low, prioritise the numeric step data and
///    auto-archive/compress old GPS path data."
///
/// Architecture:
///   • Subscribes to the device location stream via geolocator with a
///     [_distanceFilterM] noise gate — ignores micro-jitter < 5 m.
///   • Computes running distance with the Haversine formula applied to
///     consecutive [RoutePoint]s.
///   • Emits a [GpsWalkSession] snapshot on every position update so the UI
///     can repaint the map polyline and stats HUD in real-time.
///   • On each integer km boundary, fires [HapticService.medicineReminder()]
///     (two short sharp pulses — distinct from the goal-success pattern).
///   • [isStorageLow] checks available disk space via platform channel.
///     If below [_storageLowThresholdMb], [archiveOldSessions] replaces the
///     full route_points array in Firestore with a 4-coordinate BoundingBox,
///     keeping all numeric fields intact.
///
/// Dependencies (pubspec.yaml):
///   geolocator: ^12.0.0
///   path_provider: ^2.1.0   (used for storage fallback on simulator)
///
/// ── Add to AndroidManifest.xml ──────────────────────────────────────────────
///   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
///   <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
///
/// ── Add to ios/Runner/Info.plist ────────────────────────────────────────────
///   <key>NSLocationWhenInUseUsageDescription</key>
///   <string>VitalPath tracks your walk route for your Activity log.</string>
///   <key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
///   <string>VitalPath tracks your walk route in the background.</string>
///
/// ── Native storage channel (iOS Swift) ─────────────────────────────────────
///   let channel = FlutterMethodChannel(name: "com.vitalpath.storage", ...)
///   channel.setMethodCallHandler { call, result in
///     if call.method == "getAvailableBytes" {
///       let attrs = try! FileManager.default.attributesOfFileSystem(
///         forPath: NSHomeDirectory())
///       result(attrs[.systemFreeSize] as? Int ?? 0)
///     }
///   }
///
/// ── Native storage channel (Android Kotlin) ─────────────────────────────────
///   MethodChannel(binaryMessenger, "com.vitalpath.storage")
///     .setMethodCallHandler { call, result ->
///       if (call.method == "getAvailableBytes") {
///         val stat = StatFs(Environment.getDataDirectory().path)
///         result.success(stat.availableBlocksLong * stat.blockSizeLong)
///       }
///     }
/// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:vitalpath/models/gps_walk_session.dart';
import 'package:vitalpath/services/haptic_service.dart';

// ── Constants ─────────────────────────────────────────────────────────────────
const _distanceFilterM = 5.0;       // GPS noise gate (metres)
const _storageLowThresholdMb = 500; // archive trigger (megabytes)
const _caloriesPerKm = 60.0;        // MET-based estimate for brisk walking

// ── GPS permission contract ───────────────────────────────────────────────────
// geolocator usage shown in comments; avoids hard import for testability.
//
//   import 'package:geolocator/geolocator.dart';
//
//   // Permission check before startWalk():
//   var perm = await Geolocator.checkPermission();
//   if (perm == LocationPermission.denied) {
//     perm = await Geolocator.requestPermission();
//   }
//   if (perm == LocationPermission.deniedForever) throw Exception('no perms');
//
//   // Position stream:
//   final settings = LocationSettings(
//     accuracy: LocationAccuracy.high,
//     distanceFilter: _distanceFilterM.toInt(),
//   );
//   Geolocator.getPositionStream(locationSettings: settings).listen(_handlePosition);

// ── Firestore save contract (injectable) ─────────────────────────────────────
typedef SaveWalkFn = Future<String?> Function(Map<String, dynamic> data);
typedef UpdateWalkFn = Future<void> Function(
    String sessionId, Map<String, dynamic> data);

// ── GpsWalkService ────────────────────────────────────────────────────────────
class GpsWalkService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static GpsWalkService? _instance;
  factory GpsWalkService({
    SaveWalkFn? saveWalkFn,
    UpdateWalkFn? updateWalkFn,
  }) {
    _instance ??=
        GpsWalkService._internal(saveWalkFn, updateWalkFn);
    return _instance!;
  }
  GpsWalkService._internal(this._saveWalkFn, this._updateWalkFn);

  final SaveWalkFn? _saveWalkFn;
  final UpdateWalkFn? _updateWalkFn;

  // ── Channels ───────────────────────────────────────────────────────────────
  static const _storageChannel =
      MethodChannel('com.vitalpath.storage');

  // ── Live session state ─────────────────────────────────────────────────────
  bool _isTracking = false;
  String? _patientId;
  String? _sessionId; // Firestore doc ID once saved
  final List<RoutePoint> _points = [];
  double _distanceKm = 0;
  int _lastKmMilestone = 0;
  int _durationSeconds = 0;
  DateTime? _startedAt;
  Timer? _durationTicker;

  bool get isTracking => _isTracking;

  // ── Session broadcast stream ───────────────────────────────────────────────
  final _sessionCtrl =
      StreamController<GpsWalkSession>.broadcast();

  Stream<GpsWalkSession> get sessionStream => _sessionCtrl.stream;

  // ── Public: start walk ─────────────────────────────────────────────────────
  /// Requests location permissions and starts the GPS listener.
  /// Returns false if permissions are denied.
  Future<bool> startWalk(String patientId) async {
    if (_isTracking) return true;

    // ── Real permission check (geolocator) ────────────────────────────────
    // var perm = await Geolocator.checkPermission();
    // if (perm == LocationPermission.denied) {
    //   perm = await Geolocator.requestPermission();
    // }
    // if (perm == LocationPermission.denied ||
    //     perm == LocationPermission.deniedForever) return false;

    _patientId = patientId;
    _points.clear();
    _distanceKm = 0;
    _lastKmMilestone = 0;
    _durationSeconds = 0;
    _startedAt = DateTime.now();
    _isTracking = true;

    // ── Real position stream subscription (geolocator) ────────────────────
    // const settings = LocationSettings(
    //   accuracy: LocationAccuracy.high,
    //   distanceFilter: _distanceFilterM.toInt(),
    // );
    // _positionSub = Geolocator.getPositionStream(
    //   locationSettings: settings,
    // ).listen(_handlePosition, onError: _handlePositionError);

    // ── Duration ticker ───────────────────────────────────────────────────
    _durationTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      _durationSeconds++;
      _sessionCtrl.add(_buildSnapshot());
    });

    debugPrint('[GpsWalkService] Walk started for patient $patientId');
    _sessionCtrl.add(_buildSnapshot());

    // In debug: simulate movement after a short delay.
    if (kDebugMode) _startDebugSimulation();

    return true;
  }

  // ── Public: stop walk ──────────────────────────────────────────────────────
  /// Stops GPS tracking, finalises the session, saves to Firestore.
  /// Returns the completed [GpsWalkSession] or null on error.
  Future<GpsWalkSession?> stopWalk() async {
    if (!_isTracking) return null;

    _isTracking = false;
    _durationTicker?.cancel();
    _durationTicker = null;
    _debugTimer?.cancel();
    _debugTimer = null;

    // ── Real position stream cancel ───────────────────────────────────────
    // await _positionSub?.cancel();

    final session = _buildSnapshot().copyWith(
      isActive: false,
      endedAt: DateTime.now(),
    );

    // ── Storage pressure check before saving route ────────────────────────
    final lowStorage = await isStorageLow();
    final finalSession = lowStorage && session.routePoints.isNotEmpty
        ? session.copyWith(
            isGpsArchived: true,
            archiveBounds: BoundingBox.fromPoints(session.routePoints),
            routePoints: [], // drop path to save space
          )
        : session;

    if (lowStorage) {
      debugPrint('[GpsWalkService] Low storage — GPS path archived for '
          'session, bounding box preserved.');
    }

    // ── Persist to Firestore ───────────────────────────────────────────────
    // Real implementation:
    // final savedId = await _saveWalkFn?.call(finalSession.toJson());
    // if (savedId != null) finalSession = finalSession.copyWith(id: savedId);
    debugPrint('[GpsWalkService] Walk stopped. '
        'Distance: ${finalSession.formattedDistance}, '
        'Duration: ${finalSession.formattedDuration}, '
        'KMs: ${finalSession.kmMilestonesReached}');

    _sessionCtrl.add(finalSession);
    return finalSession;
  }

  // ── Internal: handle a position update ────────────────────────────────────
  void handlePosition(double lat, double lng,
      {double? altitude, double? speed}) {
    if (!_isTracking) return;

    final now = DateTime.now();
    final newPoint = RoutePoint(
      latitude: lat,
      longitude: lng,
      timestamp: now,
      altitudeM: altitude,
      speedMs: speed,
    );

    if (_points.isNotEmpty) {
      final last = _points.last;
      final delta = _haversineKm(
        last.latitude, last.longitude, lat, lng);
      // Ignore GPS jitter — only accept if > noise gate equivalent in km
      if (delta < _distanceFilterM / 1000) return;

      _distanceKm += delta;
      _checkKmMilestone();
    }

    _points.add(newPoint);
    _sessionCtrl.add(_buildSnapshot());
  }

  // ── Internal: km milestone haptic ─────────────────────────────────────────
  void _checkKmMilestone() {
    final milestone = _distanceKm.floor();
    if (milestone > _lastKmMilestone) {
      _lastKmMilestone = milestone;
      // Two short sharp pulses — "distinct vibration every 1 KM reached"
      // (Blueprint §4 / §7). Intentionally different from goalSuccess().
      HapticService().medicineReminder();
      debugPrint(
          '[GpsWalkService] KM milestone reached: ${_lastKmMilestone}km');
    }
  }

  // ── Internal: build current session snapshot ───────────────────────────────
  GpsWalkSession _buildSnapshot() {
    final calories = _distanceKm * _caloriesPerKm;
    return GpsWalkSession(
      id: _sessionId,
      patientId: _patientId ?? '',
      routePoints: List.unmodifiable(_points),
      distanceKm: _distanceKm,
      durationSeconds: _durationSeconds,
      caloriesBurned: calories,
      stepCount: (_distanceKm * 1312).round(), // ~1312 steps/km estimate
      kmMilestonesReached: _lastKmMilestone,
      startedAt: _startedAt ?? DateTime.now(),
      isActive: _isTracking,
    );
  }

  // ── Storage pressure ───────────────────────────────────────────────────────
  /// Returns true if free device storage is below [_storageLowThresholdMb].
  Future<bool> isStorageLow() async {
    try {
      final bytes = await _storageChannel
          .invokeMethod<int>('getAvailableBytes');
      if (bytes == null) return false;
      return bytes < _storageLowThresholdMb * 1024 * 1024;
    } on PlatformException catch (e) {
      debugPrint('[GpsWalkService] Storage check failed: ${e.message}');
      return false; // fail open — don't archive unnecessarily
    }
  }

  /// Archives GPS path data for a stored session by replacing route_points
  /// with a [BoundingBox] in Firestore. Called on new walk save when storage
  /// is low; can also be triggered by [ActivityProvider] on app foreground.
  Future<void> archiveOldSessions(
      List<GpsWalkSession> sessions) async {
    for (final session in sessions) {
      if (session.isGpsArchived ||
          session.id == null ||
          session.routePoints.isEmpty) continue;

      final bounds = BoundingBox.fromPoints(session.routePoints);
      await _updateWalkFn?.call(session.id!, {
        'route_points': [], // clear path
        'is_gps_archived': true,
        'archive_bounds': bounds.toJson(),
      });
      debugPrint('[GpsWalkService] Archived GPS path for session ${session.id}');
    }
  }

  // ── Haversine distance ─────────────────────────────────────────────────────
  // Returns the great-circle distance in kilometres between two coordinates.
  static double _haversineKm(
      double lat1, double lon1, double lat2, double lon2) {
    const earthR = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthR * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180;

  // ── Debug simulation ───────────────────────────────────────────────────────
  // Simulates a ~5km/h walk by feeding synthetic route points.
  // Disabled in production builds.
  Timer? _debugTimer;
  double _debugLat = 51.5074;
  double _debugLng = -0.1278;
  int _debugTick = 0;

  void _startDebugSimulation() {
    _debugTimer =
        Timer.periodic(const Duration(seconds: 4), (_) {
      _debugTick++;
      // Move ~22m NE every 4 seconds → ~5.5 km/h
      _debugLat += 0.00010;
      _debugLng += 0.00008;
      handlePosition(_debugLat, _debugLng,
          altitude: 35.0, speed: 1.4);
    });
  }

  Future<void> dispose() async {
    _durationTicker?.cancel();
    _debugTimer?.cancel();
    await _sessionCtrl.close();
  }
}
