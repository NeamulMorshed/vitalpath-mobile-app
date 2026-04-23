/// activity_provider.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// State owner for the Activity & Wellness module.
///
/// Blueprint §1.1 / §1.2 / §4 / §7:
///   Merges two data sources into one coherent activity state:
///   1. Passive steps — from [HealthService.stepsStream] (real-time) +
///      a [Timer.periodic(15 minutes)] background refresh tick.
///   2. Active GPS walks — from [GpsWalkService.sessionStream].
///
/// Prescribed activities (isVerified = true):
///   Pushed via the Doctor Sync flow and pinned at the top of the Workouts tab.
///   Patients may mark them complete ([isCompleted] = true) — that is
///   adherence logging, not a mutation of the clinical prescription.
///
/// Goal celebration:
///   [shouldCelebrate] becomes true exactly once per day when step count first
///   crosses [HealthService.defaultStepGoal]. The UI calls [markGoalCelebrated]
///   after showing the burst animation to suppress repeat fires.
///
/// Storage pressure:
///   On every new walk completion [_checkAndArchive] queries storage pressure
///   and delegates archival to [GpsWalkService.archiveOldSessions] if low.
/// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:vitalpath/models/activity_model.dart';
import 'package:vitalpath/models/governance_level.dart';
import 'package:vitalpath/models/gps_walk_session.dart';
import 'package:vitalpath/services/gps_walk_service.dart';
import 'package:vitalpath/services/health_service.dart';

// ── Firestore load contract (injectable) ──────────────────────────────────────
typedef LoadPrescribedFn = Future<List<ActivityModel>> Function(
    String patientId);
typedef LoadWalkHistoryFn =
    Future<List<GpsWalkSession>> Function(String patientId);
typedef SaveActivityFn = Future<void> Function(ActivityModel activity);

class ActivityProvider extends ChangeNotifier {
  // ── Dependencies ───────────────────────────────────────────────────────────
  final HealthService _health;
  final GpsWalkService _gps;
  final LoadPrescribedFn? _loadPrescribedFn;
  final LoadWalkHistoryFn? _loadWalkHistoryFn;
  final SaveActivityFn? _saveActivityFn;

  ActivityProvider({
    HealthService? health,
    GpsWalkService? gps,
    LoadPrescribedFn? loadPrescribedFn,
    LoadWalkHistoryFn? loadWalkHistoryFn,
    SaveActivityFn? saveActivityFn,
  })  : _health = health ?? HealthService(),
        _gps = gps ?? GpsWalkService(),
        _loadPrescribedFn = loadPrescribedFn,
        _loadWalkHistoryFn = loadWalkHistoryFn,
        _saveActivityFn = saveActivityFn;

  // ── Steps state ────────────────────────────────────────────────────────────
  int _steps = 0;
  bool _goalCelebrated = false;

  // ── Activity state ─────────────────────────────────────────────────────────
  List<ActivityModel> _prescribed = [];
  List<GpsWalkSession> _walkHistory = [];
  GpsWalkSession? _activeSession;

  bool _isLoading = false;
  bool _isStartingWalk = false;
  String? _error;

  // ── Subscriptions ──────────────────────────────────────────────────────────
  StreamSubscription<int>? _stepsSub;
  StreamSubscription<GpsWalkSession>? _walkSub;
  Timer? _bgRefreshTimer;

  // ── Getters ────────────────────────────────────────────────────────────────
  int get steps => _steps;
  bool get isGoalReached => _steps >= HealthService.defaultStepGoal;
  bool get isLoading => _isLoading;
  bool get isStartingWalk => _isStartingWalk;
  bool get isWalking => _gps.isTracking;
  String? get error => _error;

  /// True exactly once after steps first cross 10k today.
  /// UI must call [markGoalCelebrated] after showing the celebration.
  bool get shouldCelebrate => isGoalReached && !_goalCelebrated;

  /// Physician-prescribed activities — pinned at top of Workouts tab.
  List<ActivityModel> get prescribed =>
      List.unmodifiable(_prescribed);

  /// Completed walk sessions, newest first.
  List<GpsWalkSession> get walkHistory =>
      List.unmodifiable(_walkHistory);

  GpsWalkSession? get activeSession => _activeSession;

  // ── Step tracking ──────────────────────────────────────────────────────────
  /// Subscribes to the live steps stream and starts the 15-minute background
  /// refresh timer. Call once from the screen's [initState].
  void startStepTracking() {
    _stepsSub?.cancel();
    _stepsSub = _health.stepsStream.listen((steps) {
      _steps = steps;
      notifyListeners();
    }, onError: (e) {
      _error = 'Step tracking error: $e';
      notifyListeners();
    });
    _startBackgroundRefresh();
  }

  // Every 15 minutes, force-fetch current steps from HealthKit / Health Connect.
  // This keeps the counter accurate when the app is in the foreground but
  // the native observer has not fired (e.g., device was in airplane mode).
  void _startBackgroundRefresh() {
    _bgRefreshTimer?.cancel();
    _bgRefreshTimer =
        Timer.periodic(const Duration(minutes: 15), (_) async {
      final fresh = await _health.fetchStepsNow();
      if (fresh != _steps) {
        _steps = fresh;
        notifyListeners();
      }
      debugPrint('[ActivityProvider] 15-min refresh — steps: $fresh');
    });
  }

  void markGoalCelebrated() {
    _goalCelebrated = true;
    notifyListeners();
  }

  // ── Load data ──────────────────────────────────────────────────────────────
  Future<void> loadData(String patientId) async {
    _setLoading(true);
    clearError();

    try {
      await Future.wait([
        _loadPrescribed(patientId),
        _loadWalkHistory(patientId),
      ]);
    } catch (e) {
      _error = 'Failed to load activity data: $e';
      debugPrint('[ActivityProvider] Load error: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _loadPrescribed(String patientId) async {
    if (_loadPrescribedFn != null) {
      _prescribed = await _loadPrescribedFn(patientId);
    } else {
      // Debug stub: one sample prescribed activity.
      await Future.delayed(const Duration(milliseconds: 400));
      _prescribed = kDebugMode
          ? [
              ActivityModel(
                id: 'rx-001',
                patientId: patientId,
                activityType: ActivityType.walking,
                durationMinutes: 30,
                caloriesBurned: 150,
                distanceKm: 2.5,
                intensity: IntensityLevel.moderate,
                performedAt: DateTime.now(),
                prescribingDoctorName: 'Patel',
                protocolName: 'Knee Rehab Phase 2',
                isVerified: true,
                governanceLevel: GovernanceLevel.physicianVerified,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            ]
          : [];
    }
    notifyListeners();
  }

  Future<void> _loadWalkHistory(String patientId) async {
    if (_loadWalkHistoryFn != null) {
      _walkHistory = await _loadWalkHistoryFn(patientId);
    } else {
      await Future.delayed(const Duration(milliseconds: 300));
      _walkHistory = kDebugMode ? _debugWalkHistory(patientId) : [];
    }
    notifyListeners();
  }

  // ── GPS walk ───────────────────────────────────────────────────────────────
  Future<bool> startWalk(String patientId) async {
    if (_isStartingWalk || _gps.isTracking) return false;
    _isStartingWalk = true;
    clearError();
    notifyListeners();

    try {
      final started = await _gps.startWalk(patientId);
      if (!started) {
        _error = 'Location permission is required for GPS walks.';
        return false;
      }

      // Subscribe to live session updates.
      _walkSub?.cancel();
      _walkSub = _gps.sessionStream.listen((session) {
        _activeSession = session;
        notifyListeners();
      });

      return true;
    } catch (e) {
      _error = 'Failed to start walk: $e';
      return false;
    } finally {
      _isStartingWalk = false;
      notifyListeners();
    }
  }

  Future<GpsWalkSession?> stopWalk() async {
    _walkSub?.cancel();
    _walkSub = null;

    final session = await _gps.stopWalk();
    if (session != null) {
      _walkHistory.insert(0, session);
      await _checkAndArchive();
    }
    _activeSession = null;
    notifyListeners();
    return session;
  }

  // ── Storage pressure management ────────────────────────────────────────────
  // Triggered after each walk completion. Archives old session GPS paths if
  // storage is low, preserving numeric data and bounding boxes.
  Future<void> _checkAndArchive() async {
    final isLow = await _gps.isStorageLow();
    if (!isLow) return;

    // Target oldest sessions with un-archived GPS paths for compression.
    final archiveCandidates = _walkHistory
        .where((s) => !s.isGpsArchived && s.routePoints.isNotEmpty)
        .toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt)); // oldest first

    final toArchive = archiveCandidates.take(5).toList();
    await _gps.archiveOldSessions(toArchive);

    // Update local list to reflect archived state.
    for (final s in toArchive) {
      final idx = _walkHistory.indexWhere((w) => w.id == s.id);
      if (idx != -1) {
        _walkHistory[idx] = _walkHistory[idx].copyWith(
          isGpsArchived: true,
          archiveBounds: BoundingBox.fromPoints(s.routePoints),
          routePoints: [],
        );
      }
    }
    notifyListeners();
    debugPrint(
        '[ActivityProvider] Archived GPS paths for ${toArchive.length} sessions.');
  }

  // ── Prescribed activity adherence ──────────────────────────────────────────
  Future<void> markPrescribedComplete(String activityId) async {
    final idx = _prescribed.indexWhere((a) => a.id == activityId);
    if (idx == -1) return;

    final updated = _prescribed[idx].copyWith(isCompleted: true);
    final rollback = _prescribed[idx];
    _prescribed[idx] = updated;
    notifyListeners();

    try {
      await _saveActivityFn?.call(updated);
    } catch (e) {
      _prescribed[idx] = rollback;
      _error = 'Failed to save: $e';
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  @override
  void dispose() {
    _stepsSub?.cancel();
    _walkSub?.cancel();
    _bgRefreshTimer?.cancel();
    super.dispose();
  }

  // ── Debug data ─────────────────────────────────────────────────────────────
  List<GpsWalkSession> _debugWalkHistory(String patientId) {
    final now = DateTime.now();
    return [
      GpsWalkSession(
        id: 'w-001',
        patientId: patientId,
        routePoints: const [],
        distanceKm: 3.42,
        durationSeconds: 2460,
        caloriesBurned: 205,
        stepCount: 4492,
        kmMilestonesReached: 3,
        startedAt: now.subtract(const Duration(days: 1, hours: 7)),
        endedAt: now.subtract(const Duration(days: 1, hours: 6, minutes: 19)),
        isActive: false,
      ),
      GpsWalkSession(
        id: 'w-002',
        patientId: patientId,
        routePoints: const [],
        distanceKm: 5.01,
        durationSeconds: 3420,
        caloriesBurned: 301,
        stepCount: 6573,
        kmMilestonesReached: 5,
        startedAt: now.subtract(const Duration(days: 3, hours: 8)),
        endedAt: now.subtract(const Duration(days: 3, hours: 7, minutes: 3)),
        isActive: false,
        isGpsArchived: true,
        archiveBounds: const BoundingBox(
            minLat: 51.507, maxLat: 51.512,
            minLng: -0.130, maxLng: -0.120),
      ),
    ];
  }
}
