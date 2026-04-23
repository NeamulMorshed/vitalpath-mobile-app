/// doctor_provider.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// State owner for the "My Doctors" feature in the Profile tab.
///
/// Blueprint §1.1 / §7:
///   "Patients request appointments through the 'My Doctors' interface.
///    Once synced, the doctor appears at the top of the list with a
///    'Connected' status badge."
///
/// Architecture:
///   [DoctorProvider] owns the list of linked doctors and delegates all
///   Firebase I/O to [DoctorSyncService]. The UI consumes:
///     • [sortedDoctors]  — connected first, then alphabetical
///     • [filtered(q)]    — search across name / specialty / clinic
///     • [isLoading]      — drives shimmer skeleton
///     • [syncError]      — surfaces handshake failures
///
/// Sync handshake flow:
///   1. UI calls [syncByCode] or [syncByQr].
///   2. [DoctorSyncService.validateCode] queries Firestore for matching code.
///   3. [DoctorSyncService.linkDoctor] writes to linked_doctors sub-collection.
///   4. Doctor is prepended to the list with 'connected' status.
///   5. Caller triggers [HapticService.goalSuccess()] on the returned model.
///
/// Unsync flow:
///   1. UI shows confirmation dialog (Blueprint §unsync safety).
///   2. On confirm, UI calls [unsyncDoctor].
///   3. [DoctorSyncService.unlinkDoctor] deletes the Firestore document.
///   4. Doctor is removed from local list.
/// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:vitalpath/models/doctor_model.dart';
import 'package:vitalpath/services/doctor_sync_service.dart';

class DoctorProvider extends ChangeNotifier {
  // ── Dependencies ───────────────────────────────────────────────────────────
  final DoctorSyncService _syncService;

  // ── State ──────────────────────────────────────────────────────────────────
  List<DoctorModel> _doctors = [];
  bool _isLoading = false;
  bool _isSyncing = false;
  String? _syncError;
  StreamSubscription<List<DoctorModel>>? _firestoreSubscription;

  DoctorProvider({DoctorSyncService? syncService})
      : _syncService = syncService ?? DoctorSyncService();

  // ── Getters ────────────────────────────────────────────────────────────────
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String? get syncError => _syncError;

  /// Connected doctors first (sorted by name), then pending/disconnected.
  List<DoctorModel> get sortedDoctors {
    final connected = _doctors
        .where((d) => d.syncStatus == DoctorSyncStatus.connected)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final others = _doctors
        .where((d) => d.syncStatus != DoctorSyncStatus.connected)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return [...connected, ...others];
  }

  /// Filters [sortedDoctors] against a search query.
  /// Matches name, specialty, and clinic name (case-insensitive).
  List<DoctorModel> filtered(String query) {
    if (query.trim().isEmpty) return sortedDoctors;
    final q = query.trim().toLowerCase();
    return sortedDoctors.where((d) {
      return d.name.toLowerCase().contains(q) ||
          d.specialty.toLowerCase().contains(q) ||
          d.clinicName.toLowerCase().contains(q);
    }).toList();
  }

  int get connectedCount =>
      _doctors.where((d) => d.isConnected).length;

  // ── Load / stream from Firestore ───────────────────────────────────────────
  Future<void> loadDoctors(String patientId) async {
    _setLoading(true);
    clearError();

    // Real Firestore: start snapshot listener via [streamLinkedDoctors].
    _firestoreSubscription?.cancel();
    _firestoreSubscription = _syncService
        .streamLinkedDoctors(patientId)
        .listen(
      (docs) {
        _doctors = docs;
        _setLoading(false);
        notifyListeners();
      },
      onError: (e) {
        _syncError = 'Failed to load doctors: $e';
        _setLoading(false);
        notifyListeners();
        debugPrint('[DoctorProvider] Stream error: $e');
      },
    );
  }

  // ── Sync via 6-digit code ──────────────────────────────────────────────────
  /// Returns the newly linked [DoctorModel] on success (caller triggers haptic).
  /// Throws [DoctorSyncException] on invalid code or network error.
  Future<DoctorModel> syncByCode({
    required String patientId,
    required String code,
  }) async {
    clearError();
    _setSyncing(true);

    try {
      final doctor = await _syncService.validateCode(code);
      if (doctor == null) {
        throw const DoctorSyncException(
          'No doctor found with this code. Please check with your doctor.',
          DoctorSyncErrorType.invalidCode,
        );
      }

      final linked = await _syncService.linkDoctor(
        patientId: patientId,
        doctor: doctor,
        existingDoctors: _doctors,
      );

      // Optimistic update — Firestore stream will reconcile if needed.
      _doctors.removeWhere((d) => d.uid == linked.uid);
      _doctors.insert(0, linked);
      notifyListeners();

      debugPrint('[DoctorProvider] Synced: ${linked.name}');
      return linked;
    } on DoctorSyncException catch (e) {
      _syncError = e.message;
      notifyListeners();
      rethrow;
    } finally {
      _setSyncing(false);
    }
  }

  /// Convenience wrapper that parses a QR payload then delegates to [syncByCode].
  Future<DoctorModel> syncByQr({
    required String patientId,
    required String qrPayload,
  }) async {
    final code = DoctorSyncService.parseSyncCodeFromQr(qrPayload);
    if (code == null) {
      throw const DoctorSyncException(
        'Invalid QR code. Please ask your doctor for a fresh code.',
        DoctorSyncErrorType.invalidCode,
      );
    }
    return syncByCode(patientId: patientId, code: code);
  }

  // ── Unsync a doctor ────────────────────────────────────────────────────────
  Future<void> unsyncDoctor({
    required String patientId,
    required String doctorId,
  }) async {
    clearError();
    _setSyncing(true);

    final rollback = List.of(_doctors);
    _doctors.removeWhere((d) => d.uid == doctorId);
    notifyListeners();

    try {
      await _syncService.unlinkDoctor(
        patientId: patientId,
        doctorId: doctorId,
      );
      debugPrint('[DoctorProvider] Unsynced doctor: $doctorId');
    } on DoctorSyncException catch (e) {
      _doctors = rollback;
      _syncError = e.message;
      notifyListeners();
      rethrow;
    } finally {
      _setSyncing(false);
    }
  }

  void clearError() {
    _syncError = null;
    notifyListeners();
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  void _setSyncing(bool v) {
    _isSyncing = v;
    notifyListeners();
  }

  @override
  void dispose() {
    _firestoreSubscription?.cancel();
    super.dispose();
  }
}
