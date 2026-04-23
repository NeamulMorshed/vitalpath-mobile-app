/// medicine_logging_service.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Handles medicine dose logging with the Duplicate Log Guard.
///
/// Blueprint §1.2 — The Duplicate Log:
///   "If a user logs a dose and attempts to re-log within 15 minutes, a
///    critical warning appears to prevent potential overdose."
///
/// Guard contract:
///   • [logDose()] checks the last logged timestamp for [medicineId].
///   • If the delta is < [_lockoutDuration] (15 min), it throws a
///     [DuplicateLogException] containing:
///       - [medicineId], [medicineName]
///       - [lastLoggedAt]: when the previous dose was taken
///       - [remainingLockoutSeconds]: countdown for the UI to display
///   • The calling UI catches this exception and shows [DuplicateLogModal].
///   • After the modal, the user can OVERRIDE (continue logging) or CANCEL.
///     The override path logs the dose with a [forcedOverride: true] flag.
///
/// Persistence: Last-log timestamps stored in SharedPreferences.
/// Offline behaviour: Routes through [SyncQueueService] when offline.
/// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vitalpath/models/sync_queue_entry.dart';
import 'package:vitalpath/services/sync_queue_service.dart';

// ── Exception ─────────────────────────────────────────────────────────────────
class DuplicateLogException implements Exception {
  final String medicineId;
  final String medicineName;
  final DateTime lastLoggedAt;
  final int remainingLockoutSeconds;

  const DuplicateLogException({
    required this.medicineId,
    required this.medicineName,
    required this.lastLoggedAt,
    required this.remainingLockoutSeconds,
  });

  @override
  String toString() =>
      'DuplicateLogException: $medicineName logged at $lastLoggedAt — '
      '${remainingLockoutSeconds}s remaining in lockout window.';
}

// ── Log result ────────────────────────────────────────────────────────────────
class DoseLogResult {
  final String logId;
  final DateTime loggedAt;     // the originalTimestamp used for Firebase
  final bool queuedOffline;    // true if routed through SyncQueueService
  final bool forcedOverride;   // true if patient overrode the duplicate guard

  const DoseLogResult({
    required this.logId,
    required this.loggedAt,
    required this.queuedOffline,
    this.forcedOverride = false,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────
class MedicineLoggingService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static MedicineLoggingService? _instance;
  factory MedicineLoggingService({
    SyncQueueService? syncQueue,
  }) =>
      _instance ??= MedicineLoggingService._internal(syncQueue: syncQueue);

  MedicineLoggingService._internal({SyncQueueService? syncQueue})
      : _syncQueue = syncQueue ?? SyncQueueService();

  final SyncQueueService _syncQueue;

  // ── Lockout window (Blueprint §1.2: 15 minutes) ───────────────────────────
  static const Duration _lockoutDuration = Duration(minutes: 15);

  // ── SharedPreferences key prefix ─────────────────────────────────────────
  static const String _prefPrefix = 'last_dose_';

  // ── Core log method ───────────────────────────────────────────────────────
  /// Logs a medicine dose.
  ///
  /// Throws [DuplicateLogException] if the same medicine was logged within
  /// the last 15 minutes, UNLESS [forceOverride] is true (patient confirmed
  /// they want to log anyway after seeing the critical alert).
  ///
  /// [actionTimestamp] is the moment the user tapped "Log". This is always
  /// used as the Firestore document timestamp — even if the write is queued
  /// offline and delivered later.
  Future<DoseLogResult> logDose({
    required String patientId,
    required String medicineId,
    required String medicineName,
    required double dosage,
    required String unit,
    bool forceOverride = false,
    bool isOnline = true,
    DateTime? actionTimestamp, // defaults to now if null
  }) async {
    final loggedAt = actionTimestamp ?? DateTime.now();

    // ── DUPLICATE GUARD ───────────────────────────────────────────────────
    if (!forceOverride) {
      final lastLog = await _getLastLogTime(medicineId);
      if (lastLog != null) {
        final delta = loggedAt.difference(lastLog);
        if (delta < _lockoutDuration) {
          final remaining = (_lockoutDuration - delta).inSeconds;
          throw DuplicateLogException(
            medicineId: medicineId,
            medicineName: medicineName,
            lastLoggedAt: lastLog,
            remainingLockoutSeconds: remaining,
          );
        }
      }
    }

    // ── Build log payload ─────────────────────────────────────────────────
    final logId = '${medicineId}_${loggedAt.millisecondsSinceEpoch}';
    final payload = {
      'id': logId,
      'patient_id': patientId,
      'medicine_id': medicineId,
      'medicine_name': medicineName,
      'dosage': dosage,
      'unit': unit,
      'logged_at': loggedAt.toIso8601String(),
      // original_timestamp is injected by SyncQueueService on flush.
      'forced_override': forceOverride,
    };

    bool queuedOffline = false;

    if (isOnline) {
      // ── Direct Firebase write (handled by repository layer) ─────────────
      // In the full implementation this would call a repository method.
      // The SyncQueue path below is the canonical offline path.
      debugPrint('[MedicineLog] Online write: $medicineName at $loggedAt');
    } else {
      // ── Offline: enqueue with originalTimestamp ──────────────────────────
      await _syncQueue.enqueue(
        entityType: SyncEntityType.medicineLog,
        operation: SyncOperation.create,
        documentId: logId,
        collectionPath: 'users/$patientId/medicine_logs',
        payload: payload,
        originalTimestamp: loggedAt, // ← the ORIGINAL action time
      );
      queuedOffline = true;
      debugPrint('[MedicineLog] Queued offline: $medicineName at $loggedAt');
    }

    // ── Update last-log timestamp ─────────────────────────────────────────
    await _setLastLogTime(medicineId, loggedAt);

    return DoseLogResult(
      logId: logId,
      loggedAt: loggedAt,
      queuedOffline: queuedOffline,
      forcedOverride: forceOverride,
    );
  }

  // ── Last-log persistence ──────────────────────────────────────────────────
  Future<DateTime?> _getLastLogTime(String medicineId) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('$_prefPrefix$medicineId');
    if (stored == null) return null;
    return DateTime.tryParse(stored);
  }

  Future<void> _setLastLogTime(String medicineId, DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefPrefix$medicineId', time.toIso8601String());
  }

  /// Clears the lockout for a medicine (used in testing / by doctors resetting
  /// schedules). Should NOT be exposed to patients in the UI.
  @visibleForTesting
  Future<void> clearLockout(String medicineId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefPrefix$medicineId');
  }

  /// Returns the remaining lockout seconds for [medicineId], or 0 if clear.
  Future<int> remainingLockoutSeconds(String medicineId) async {
    final last = await _getLastLogTime(medicineId);
    if (last == null) return 0;
    final elapsed = DateTime.now().difference(last);
    if (elapsed >= _lockoutDuration) return 0;
    return (_lockoutDuration - elapsed).inSeconds;
  }
}
