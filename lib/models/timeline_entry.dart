/// timeline_entry.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Unified data model for a single entry in the Home screen Smart Timeline.
///
/// A [TimelineEntry] is the "view-model layer" representation of any health
/// event scheduled for today — medicine dose, meal, confirmed appointment, or
/// activity target.  It is built by [DashboardProvider] by projecting the raw
/// domain models (PrescriptionModel, AppointmentModel, NutritionModel) into a
/// flat, sorted list.
///
/// State machine:
///   upcoming  → scheduledAt is > 15 min in the future     (elevated UI)
///   dueNow    → within the 15-min due window              (pulsing accent)
///   completed → dose logged / appointment attended         (faded, checkmark)
///   missed    → past scheduledAt + not completed           (muted warning)
///   locked    → isVerified=true, read-only Clinical Lock   (lock badge)
///
/// Blueprint §3.1 / §7 — "Upcoming tasks must be Elevated; Completed tasks
/// must move to a Faded state."
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:vitalpath/models/appointment_model.dart';

// ── Entry type ────────────────────────────────────────────────────────────────
enum TimelineEntryType { medicine, meal, appointment, activity }

extension TimelineEntryTypeX on TimelineEntryType {
  String get label {
    switch (this) {
      case TimelineEntryType.medicine:
        return 'Medicine';
      case TimelineEntryType.meal:
        return 'Meal';
      case TimelineEntryType.appointment:
        return 'Appointment';
      case TimelineEntryType.activity:
        return 'Activity';
    }
  }

  IconData get icon {
    switch (this) {
      case TimelineEntryType.medicine:
        return Icons.medication_rounded;
      case TimelineEntryType.meal:
        return Icons.restaurant_rounded;
      case TimelineEntryType.appointment:
        return Icons.event_available_rounded;
      case TimelineEntryType.activity:
        return Icons.directions_run_rounded;
    }
  }
}

// ── Entry state ───────────────────────────────────────────────────────────────
enum TimelineEntryState {
  /// Scheduled time is > 15 minutes in the future.  Full-opacity, elevated UI.
  upcoming,

  /// Within the 15-minute due window.  Pulsing accent border.
  dueNow,

  /// User has logged/completed this entry.  Faded opacity + checkmark.
  completed,

  /// Past the scheduled time without completion.  Muted warning styling.
  missed,

  /// isVerified=true — doctor-locked, patient cannot edit.
  locked,
}

extension TimelineEntryStateX on TimelineEntryState {
  bool get isActive =>
      this == TimelineEntryState.upcoming || this == TimelineEntryState.dueNow;

  bool get isPast =>
      this == TimelineEntryState.completed || this == TimelineEntryState.missed;
}

// ── DoseSchedule ─────────────────────────────────────────────────────────────
/// Represents a single scheduled dose slot derived from a prescription.
///
/// [DashboardProvider] expands each [PrescriptionModel] into one or more
/// [DoseSchedule] objects (one per daily frequency slot), then converts each
/// into a [TimelineEntry].
class DoseSchedule {
  final String prescriptionId;
  final String medicineId; // unique per-dose key for lockout tracking
  final String medicineName;
  final String dosage;
  final String? doctorName;
  final bool isVerified;
  final TimeOfDay scheduledTime;

  const DoseSchedule({
    required this.prescriptionId,
    required this.medicineId,
    required this.medicineName,
    required this.dosage,
    this.doctorName,
    this.isVerified = false,
    required this.scheduledTime,
  });
}

// ── TimelineEntry ─────────────────────────────────────────────────────────────
class TimelineEntry {
  final String id;
  final TimelineEntryType type;

  /// Primary display text (medicine name, meal name, doctor name, etc.).
  final String title;

  /// Secondary text (dosage, meal type, specialty, distance target, etc.).
  final String subtitle;

  /// The wall-clock time this entry is scheduled for today.
  final DateTime scheduledAt;

  final TimelineEntryState state;

  /// Mirrors [GovernanceFields.isVerified].  True = Clinical Lock active.
  final bool isVerified;

  /// Doctor name for display (medicine / appointment entries).
  final String? doctorName;

  /// [PrescriptionModel.id] — used for the quick-log action.
  /// Null for non-medicine entries.
  final String? prescriptionId;

  /// Per-dose unique ID passed to [MedicineLoggingService] for lockout.
  /// Format: '{prescriptionId}_{HHmm}'.
  final String? medicineId;

  /// Populated for appointment entries only.
  final AppointmentModel? appointment;

  const TimelineEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.scheduledAt,
    required this.state,
    this.isVerified = false,
    this.doctorName,
    this.prescriptionId,
    this.medicineId,
    this.appointment,
  });

  // ── Convenience booleans ───────────────────────────────────────────────────
  bool get isUpcoming => state == TimelineEntryState.upcoming;
  bool get isDueNow => state == TimelineEntryState.dueNow;
  bool get isCompleted => state == TimelineEntryState.completed;
  bool get isMissed => state == TimelineEntryState.missed;
  bool get isLocked => state == TimelineEntryState.locked;

  /// Medicine entries that are not yet completed/missed may show Quick-Log.
  bool get canQuickLog =>
      type == TimelineEntryType.medicine &&
      !isCompleted &&
      !isMissed &&
      medicineId != null;

  // ── State transition ───────────────────────────────────────────────────────
  TimelineEntry copyWith({TimelineEntryState? state}) => TimelineEntry(
        id: id,
        type: type,
        title: title,
        subtitle: subtitle,
        scheduledAt: scheduledAt,
        state: state ?? this.state,
        isVerified: isVerified,
        doctorName: doctorName,
        prescriptionId: prescriptionId,
        medicineId: medicineId,
        appointment: appointment,
      );

  // ── Factory: compute state from clock ─────────────────────────────────────
  /// Derives the correct [TimelineEntryState] for [scheduledAt] relative to
  /// [now].  Call this when building entries in [DashboardProvider].
  factory TimelineEntry.withComputedState({
    required String id,
    required TimelineEntryType type,
    required String title,
    required String subtitle,
    required DateTime scheduledAt,
    required bool isCompleted,
    required bool isVerified,
    DateTime? now,
    String? doctorName,
    String? prescriptionId,
    String? medicineId,
    AppointmentModel? appointment,
  }) {
    final reference = now ?? DateTime.now();
    final TimelineEntryState state;

    if (isCompleted) {
      state = TimelineEntryState.completed;
    } else if (isVerified && scheduledAt.isAfter(reference)) {
      // Confirmed appointments that haven't occurred yet — locked + upcoming.
      state = TimelineEntryState.locked;
    } else {
      final delta = scheduledAt.difference(reference);
      if (delta.isNegative) {
        state = TimelineEntryState.missed;
      } else if (delta <= const Duration(minutes: 15)) {
        state = TimelineEntryState.dueNow;
      } else {
        state = TimelineEntryState.upcoming;
      }
    }

    return TimelineEntry(
      id: id,
      type: type,
      title: title,
      subtitle: subtitle,
      scheduledAt: scheduledAt,
      state: state,
      isVerified: isVerified,
      doctorName: doctorName,
      prescriptionId: prescriptionId,
      medicineId: medicineId,
      appointment: appointment,
    );
  }

  @override
  String toString() =>
      'TimelineEntry($type, "$title", $state, $scheduledAt)';
}
