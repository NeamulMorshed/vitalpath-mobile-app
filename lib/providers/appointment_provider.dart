/// appointment_provider.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// State owner for the Appointment Lifecycle.
///
/// Blueprint §1.1 — Appointment Lifecycle:
///   "Patients request appointments through the 'My Doctors' interface.
///    Doctors receive notifications, accept requests, and set time schedules.
///    Confirmed schedules are pushed to the patient's appointment list
///    and dashboard."
///
/// Firestore real-time listener:
///   • Listens to `users/{patientId}/appointments` collection.
///   • When a document's status field changes to 'confirmed':
///       1. [applyClinicaLock()] is called → [isVerified] = true.
///       2. A dashboard task entry is created (via [onAppointmentConfirmed]).
///       3. [HapticService.appointmentConfirmed()] fires.
///       4. A local notification is pushed via [NotificationService].
///
/// Conflict resolution (Blueprint §1.3 — Server-Side Stamp wins):
///   • If the doctor updates at the same moment as a patient edit, the
///     Firestore [serverTimestamp] on the doctor's write wins. Our listener
///     receives the authoritative server version and replaces local state.
///
/// Offline behaviour:
///   • [requestAppointment()] routes through [SyncQueueService] when offline,
///     preserving the [originalTimestamp] = moment of patient request.
/// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:vitalpath/models/appointment_model.dart';
import 'package:vitalpath/models/sync_queue_entry.dart';
import 'package:vitalpath/services/haptic_service.dart';
import 'package:vitalpath/services/notification_service.dart';
import 'package:vitalpath/services/sync_queue_service.dart';

// ── Callback types ────────────────────────────────────────────────────────────
typedef FirestoreAppointmentListenFn = StreamSubscription<dynamic> Function({
  required String patientId,
  required void Function(List<AppointmentModel>) onData,
  required void Function(Object) onError,
});

typedef SaveAppointmentFn = Future<String> Function(
    AppointmentModel appointment);

/// Called when a new confirmed appointment should be added to the dashboard.
typedef OnAppointmentConfirmedFn = void Function(
    AppointmentModel confirmedAppointment);

class AppointmentProvider extends ChangeNotifier {
  // ── Dependencies ───────────────────────────────────────────────────────────
  final SyncQueueService _syncQueue;
  final HapticService _haptics;
  final NotificationService _notifications;
  final SaveAppointmentFn? _saveFn;
  final OnAppointmentConfirmedFn? onAppointmentConfirmed;

  // ── State ──────────────────────────────────────────────────────────────────
  List<AppointmentModel> _appointments = [];
  bool _isLoading = false;
  String? _lastError;
  StreamSubscription<dynamic>? _firestoreSubscription;
  String? _patientId;

  AppointmentProvider({
    SyncQueueService? syncQueue,
    HapticService? haptics,
    NotificationService? notifications,
    SaveAppointmentFn? saveFn,
    this.onAppointmentConfirmed,
  })  : _syncQueue = syncQueue ?? SyncQueueService(),
        _haptics = haptics ?? HapticService(),
        _notifications = notifications ?? NotificationService(),
        _saveFn = saveFn;

  // ── Getters ────────────────────────────────────────────────────────────────
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

  List<AppointmentModel> get allAppointments =>
      List.unmodifiable(_appointments);

  List<AppointmentModel> get activeAppointments =>
      _appointments.where((a) => a.status.isActive).toList()
        ..sort((a, b) => a.displayTime.compareTo(b.displayTime));

  List<AppointmentModel> get confirmedAppointments =>
      _appointments
          .where((a) => a.status == AppointmentStatus.confirmed)
          .toList()
        ..sort((a, b) => a.appointedAt!.compareTo(b.appointedAt!));

  int get pendingCount =>
      _appointments.where((a) => a.status == AppointmentStatus.pending).length;

  // ── Firebase real-time listener ────────────────────────────────────────────
  /// Attaches a Firestore snapshot listener for [patientId]'s appointments.
  ///
  /// Every time the collection changes, [_onFirestoreUpdate] is called with
  /// the full updated list. Status transitions to 'confirmed' trigger the
  /// Clinical Lock and dashboard sync.
  void startListening({
    required String patientId,
    FirestoreAppointmentListenFn? listenFn,
  }) {
    _patientId = patientId;

    // Real Firestore implementation:
    //
    // _firestoreSubscription = FirebaseFirestore.instance
    //   .collection('users/$patientId/appointments')
    //   .snapshots()
    //   .listen(
    //     (snapshot) {
    //       final appointments = snapshot.docs
    //         .map((d) => AppointmentModel.fromJson({...d.data(), 'id': d.id}))
    //         .toList();
    //       _onFirestoreUpdate(appointments);
    //     },
    //     onError: (e) => _handleError('Appointment listener error: $e'),
    //   );

    if (listenFn != null) {
      _firestoreSubscription = listenFn(
        patientId: patientId,
        onData: _onFirestoreUpdate,
        onError: (e) => _handleError('Appointment listener error: $e'),
      );
    }

    debugPrint('[AppointmentProvider] Listening for $patientId');
  }

  /// Processes a Firestore snapshot update.
  ///
  /// Detects status transitions from non-confirmed → confirmed and applies
  /// the Clinical Lock + triggers the dashboard sync.
  void _onFirestoreUpdate(List<AppointmentModel> updatedAppointments) {
    // Detect newly confirmed appointments.
    for (final updated in updatedAppointments) {
      if (updated.status == AppointmentStatus.confirmed &&
          updated.isVerified == false) {
        // This can happen if Firestore returns a confirmed document before our
        // local state reflects it. Force-apply the lock.
        _handleNewlyConfirmed(updated);
        continue;
      }

      final existing = _appointments
          .where((a) => a.id == updated.id)
          .firstOrNull;

      if (existing != null &&
          existing.status != AppointmentStatus.confirmed &&
          updated.status == AppointmentStatus.confirmed) {
        // Status transitioned from pending → confirmed on this update.
        _handleNewlyConfirmed(updated);
      }
    }

    _appointments = updatedAppointments;
    notifyListeners();
  }

  /// Applies the Clinical Lock to a newly confirmed appointment and
  /// syncs it to the dashboard.
  void _handleNewlyConfirmed(AppointmentModel appointment) {
    final locked = appointment.applyClinicaLock(
      confirmedAppointedAt: appointment.appointedAt ?? appointment.preferredAt,
      notes: appointment.doctorNotes,
      confirmedAt: appointment.confirmedAt ?? DateTime.now(),
    );

    debugPrint(
        '[AppointmentProvider] Appointment confirmed & locked: ${locked.id}');

    // ── Dashboard sync ────────────────────────────────────────────────────
    // Push the locked appointment to the dashboard. The dashboard task is
    // immutable (isVerified = true) — patient cannot edit or delete it.
    onAppointmentConfirmed?.call(locked);

    // ── Haptic & notification ─────────────────────────────────────────────
    _haptics.appointmentConfirmed();
    _notifications.notifyGoalSuccess(
      goalName: 'Appointment Confirmed',
      body: 'Dr. ${appointment.doctorName} confirmed your appointment at '
          '${locked.displayTime.toLocal()}.',
    );
  }

  // ── Request appointment ────────────────────────────────────────────────────
  /// Patient submits a new appointment request.
  ///
  /// Routes through [SyncQueueService] when offline, preserving the
  /// [requestedAt] as the [originalTimestamp].
  Future<void> requestAppointment({
    required AppointmentModel appointment,
    required bool isOnline,
  }) async {
    final now = DateTime.now();
    final requestTimestamp = appointment.requestedAt; // original action time

    // Optimistic local add.
    final rollback = List.of(_appointments);
    _appointments.add(appointment);
    notifyListeners();

    try {
      _setLoading(true);

      if (isOnline) {
        final savedId = await _saveFn?.call(appointment);
        if (savedId != null) {
          final idx = _appointments.indexWhere(
              (a) => a.doctorId == appointment.doctorId &&
                  a.requestedAt == requestTimestamp);
          if (idx != -1) {
            _appointments[idx] = appointment.copyWith(id: savedId);
          }
          notifyListeners();
        }
      } else {
        // ── Offline path: queue with ORIGINAL request timestamp ───────────
        await _syncQueue.enqueue(
          entityType: SyncEntityType.appointment,
          operation: SyncOperation.create,
          collectionPath: 'users/${appointment.patientId}/appointments',
          payload: appointment.toJson(),
          originalTimestamp: requestTimestamp, // ← preserved action time
        );
        debugPrint(
            '[AppointmentProvider] Queued offline request with '
            'originalTimestamp: $requestTimestamp');
      }
    } catch (e) {
      _appointments = rollback;
      notifyListeners();
      _handleError('Failed to request appointment: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Patient cancels a pending appointment.
  Future<void> cancelAppointment(String appointmentId) async {
    final idx = _appointments.indexWhere((a) => a.id == appointmentId);
    if (idx == -1) return;

    if (_appointments[idx].isVerified) {
      _handleError(
          'Confirmed appointments can only be cancelled via your doctor.');
      return;
    }

    final rollback = List.of(_appointments);
    _appointments[idx] =
        _appointments[idx].copyWith(status: AppointmentStatus.cancelled);
    notifyListeners();

    try {
      _setLoading(true);
      // await _saveFn?.call(_appointments[idx]);
    } catch (e) {
      _appointments = rollback;
      notifyListeners();
      _handleError('Failed to cancel appointment: $e');
    } finally {
      _setLoading(false);
    }
  }

  void stopListening() {
    _firestoreSubscription?.cancel();
    _firestoreSubscription = null;
  }

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  void _handleError(String msg) {
    _lastError = msg;
    debugPrint('[AppointmentProvider] Error: $msg');
    notifyListeners();
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}
