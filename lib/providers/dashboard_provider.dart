/// dashboard_provider.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// State owner for the Home screen Smart Timeline.
///
/// Blueprint §3.1 / §7 — "The Living Passbook":
///   "Pull data from Medication, Nutrition, and Appointment modules for the
///    current date.  Upcoming tasks must be Elevated; Completed tasks must
///    move to a Faded state."
///
/// Architecture:
///   [DashboardProvider] does NOT own domain data — it *projects* it.
///   It holds references to [PrescriptionProvider] and [AppointmentProvider]
///   and rebuilds [_todayEntries] whenever those upstream providers notify.
///
///   Today's entries are rebuilt lazily (dirty flag) on each [todayEntries]
///   read, keeping the notifyListeners() hot path allocation-free.
///
/// Quick-Log action (Blueprint §3.1):
///   [quickLog(medicineId)] calls [MedicineLoggingService.logDose()].
///   On success   → optimistic state update (completed).
///   On duplicate → throws [DuplicateLogException] — caller shows modal.
///   On error     → entry state rolled back to pre-log state.
///
/// Performance:
///   • [todayEntries] getter returns cached [List.unmodifiable].
///   • Rebuild only triggered when upstream providers change.
///   • Entry state computation is O(n), no nested loops.
/// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:vitalpath/models/appointment_model.dart';
import 'package:vitalpath/models/prescription_model.dart';
import 'package:vitalpath/models/timeline_entry.dart';
import 'package:vitalpath/providers/appointment_provider.dart';
import 'package:vitalpath/providers/prescription_provider.dart';
import 'package:vitalpath/services/medicine_logging_service.dart';

class DashboardProvider extends ChangeNotifier {
  // ── Upstream providers (injected) ──────────────────────────────────────────
  final PrescriptionProvider _prescriptions;
  final AppointmentProvider _appointments;
  final MedicineLoggingService _logger;

  // ── Cached timeline ────────────────────────────────────────────────────────
  List<TimelineEntry> _todayEntries = [];
  bool _dirty = true;

  // ── Completion tracking (local, per session) ───────────────────────────────
  /// Maps medicineId → true once a quick-log succeeds in this session.
  /// Cleared on date rollover (detected in [_rebuildIfNeeded]).
  final Map<String, bool> _completedMedicineIds = {};
  DateTime _lastBuildDate = DateTime(0);

  DashboardProvider({
    required PrescriptionProvider prescriptions,
    required AppointmentProvider appointments,
    MedicineLoggingService? logger,
  })  : _prescriptions = prescriptions,
        _appointments = appointments,
        _logger = logger ?? MedicineLoggingService() {
    // Listen to upstream providers — mark dirty when they change.
    _prescriptions.addListener(_onUpstreamChange);
    _appointments.addListener(_onUpstreamChange);
  }

  void _onUpstreamChange() {
    _dirty = true;
    notifyListeners();
  }

  // ── Public API ─────────────────────────────────────────────────────────────
  /// Sorted list of today's timeline entries (by [scheduledAt] ascending).
  ///
  /// Elevated (upcoming/dueNow) entries appear first within their time slot;
  /// completed/missed entries sink naturally by time.
  List<TimelineEntry> get todayEntries {
    _rebuildIfNeeded();
    return List.unmodifiable(_todayEntries);
  }

  int get totalTodayCount => todayEntries.length;

  int get completedTodayCount =>
      todayEntries.where((e) => e.isCompleted).length;

  int get upcomingCount =>
      todayEntries.where((e) => e.isUpcoming || e.isDueNow).length;

  double get todayCompletionRatio {
    final total = totalTodayCount;
    return total == 0 ? 0.0 : completedTodayCount / total;
  }

  // ── Quick-Log action ───────────────────────────────────────────────────────
  /// Logs a medicine dose directly from the timeline card.
  ///
  /// Returns normally on success.
  /// Throws [DuplicateLogException] when within the 15-min lockout window.
  /// Throws [StateError] if entry not found.
  Future<void> quickLog({
    required String entryId,
    required String medicineId,
    bool forceOverride = false,
    bool isOnline = true,
  }) async {
    // Find and optimistically update.
    final idx = _todayEntries.indexWhere((e) => e.id == entryId);
    if (idx == -1) throw StateError('Timeline entry $entryId not found.');

    final original = _todayEntries[idx];
    if (!original.canQuickLog) return;

    // Optimistic update.
    _todayEntries[idx] = original.copyWith(state: TimelineEntryState.completed);
    _completedMedicineIds[medicineId] = true;
    notifyListeners();

    // Resolve prescription to supply required logging fields.
    final rx = _prescriptions.allPrescriptions
        .where((p) => p.id == original.prescriptionId)
        .firstOrNull;

    try {
      await _logger.logDose(
        patientId: rx?.patientId ?? '',
        medicineId: medicineId,
        medicineName: original.title,
        dosage: rx?.dosage ?? 0.0,
        unit: rx?.unit.label ?? '',
        isOnline: isOnline,
        forceOverride: forceOverride,
      );
    } on DuplicateLogException {
      // Roll back the optimistic update — let caller show the modal.
      _todayEntries[idx] = original;
      _completedMedicineIds.remove(medicineId);
      notifyListeners();
      rethrow;
    } catch (e) {
      // Roll back on unexpected error.
      _todayEntries[idx] = original;
      _completedMedicineIds.remove(medicineId);
      notifyListeners();
      debugPrint('[DashboardProvider] quickLog error: $e');
      rethrow;
    }
  }

  /// Forces a full rebuild on the next [todayEntries] access.
  /// Call after date rollover or when upstream data is refreshed externally.
  void invalidate() {
    _dirty = true;
    notifyListeners();
  }

  // ── Rebuild ────────────────────────────────────────────────────────────────
  void _rebuildIfNeeded() {
    final today = DateTime.now();

    // Date rollover: clear completion tracking.
    if (today.day != _lastBuildDate.day ||
        today.month != _lastBuildDate.month ||
        today.year != _lastBuildDate.year) {
      _completedMedicineIds.clear();
      _dirty = true;
    }

    if (!_dirty) return;

    _dirty = false;
    _lastBuildDate = today;
    _todayEntries = _buildEntries(today);
  }

  List<TimelineEntry> _buildEntries(DateTime now) {
    final entries = <TimelineEntry>[];

    // ── 1. Medicine entries ───────────────────────────────────────────────
    for (final rx in _prescriptions.allPrescriptions) {
      final slots = _doseTimesFor(rx);
      for (final slot in slots) {
        final scheduledAt = DateTime(
          now.year,
          now.month,
          now.day,
          slot.hour,
          slot.minute,
        );

        final medicineId =
            '${rx.id}_${slot.hour.toString().padLeft(2, '0')}${slot.minute.toString().padLeft(2, '0')}';

        final isCompleted = _completedMedicineIds[medicineId] == true;

        entries.add(TimelineEntry.withComputedState(
          id: '${rx.id}_${slot.hour}_${slot.minute}',
          type: TimelineEntryType.medicine,
          title: rx.medicineName,
          subtitle: '${rx.dosage} ${rx.unit.label}'
              '${rx.instructions != null ? ' · ${rx.instructions}' : ''}',
          scheduledAt: scheduledAt,
          isCompleted: isCompleted,
          isVerified: rx.isVerified,
          doctorName: rx.doctorName,
          prescriptionId: rx.id,
          medicineId: medicineId,
          now: now,
        ));
      }
    }

    // ── 2. Appointment entries ────────────────────────────────────────────
    for (final appt in _appointments.confirmedAppointments) {
      final apptTime = appt.displayTime;

      // Only include appointments scheduled for today.
      if (apptTime.year != now.year ||
          apptTime.month != now.month ||
          apptTime.day != now.day) {
        continue;
      }

      final isCompleted = appt.status == AppointmentStatus.completed;

      entries.add(TimelineEntry.withComputedState(
        id: 'appt_${appt.id ?? appt.doctorId}_${apptTime.millisecondsSinceEpoch}',
        type: TimelineEntryType.appointment,
        title: 'Dr. ${appt.doctorName}',
        subtitle: appt.reason,
        scheduledAt: apptTime,
        isCompleted: isCompleted,
        isVerified: appt.isVerified,
        doctorName: appt.doctorName,
        appointment: appt,
        now: now,
      ));
    }

    // ── 3. Sort: ascending by scheduledAt ──────────────────────────────────
    //    Within the same minute, dueNow > upcoming > completed > missed.
    entries.sort((a, b) {
      final timeCmp = a.scheduledAt.compareTo(b.scheduledAt);
      if (timeCmp != 0) return timeCmp;
      return _statePriority(a.state).compareTo(_statePriority(b.state));
    });

    return entries;
  }

  // ── Dose time derivation ───────────────────────────────────────────────────
  /// Derives scheduled dose times from a prescription's instructions.
  ///
  /// Blueprint: In Phase 2 this is replaced by explicit [ScheduledDose]
  /// sub-collection from Firestore.  For Phase 1, we parse heuristics from the
  /// instructions field or default to once-daily at 09:00.
  static List<TimeOfDay> _doseTimesFor(PrescriptionModel rx) {
    final instr = rx.instructions?.toLowerCase() ?? '';

    // Frequency heuristics — order matters (most specific first).
    if (instr.contains('three') || instr.contains('3x') || instr.contains('tds') || instr.contains('ter')) {
      return const [
        TimeOfDay(hour: 8, minute: 0),
        TimeOfDay(hour: 14, minute: 0),
        TimeOfDay(hour: 20, minute: 0),
      ];
    }
    if (instr.contains('twice') || instr.contains('2x') || instr.contains('bd') || instr.contains('bis')) {
      return const [
        TimeOfDay(hour: 8, minute: 0),
        TimeOfDay(hour: 20, minute: 0),
      ];
    }
    if (instr.contains('four') || instr.contains('4x') || instr.contains('qds')) {
      return const [
        TimeOfDay(hour: 7, minute: 0),
        TimeOfDay(hour: 12, minute: 0),
        TimeOfDay(hour: 17, minute: 0),
        TimeOfDay(hour: 22, minute: 0),
      ];
    }
    if (instr.contains('bedtime') || instr.contains('night') || instr.contains('nocte')) {
      return const [TimeOfDay(hour: 21, minute: 0)];
    }
    if (instr.contains('morning') || instr.contains('morning')) {
      return const [TimeOfDay(hour: 8, minute: 0)];
    }

    // Default: once daily, 09:00.
    return const [TimeOfDay(hour: 9, minute: 0)];
  }

  /// Lower = rendered first when times are equal.
  static int _statePriority(TimelineEntryState s) {
    switch (s) {
      case TimelineEntryState.dueNow:
        return 0;
      case TimelineEntryState.upcoming:
        return 1;
      case TimelineEntryState.locked:
        return 2;
      case TimelineEntryState.missed:
        return 3;
      case TimelineEntryState.completed:
        return 4;
    }
  }

  @override
  void dispose() {
    _prescriptions.removeListener(_onUpstreamChange);
    _appointments.removeListener(_onUpstreamChange);
    super.dispose();
  }
}
