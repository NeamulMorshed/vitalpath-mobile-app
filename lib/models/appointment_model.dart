/// appointment_model.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Represents the full lifecycle of a patient-doctor appointment in VitalPath.
///
/// State machine (Blueprint §1.1 — Appointment Lifecycle):
///
///   pending    → Patient submitted request; doctor has not yet responded.
///   confirmed  → Doctor accepted and scheduled a time. At this point:
///                • [isVerified] = true  (Clinical Lock applied)
///                • [governanceLevel] = physicianVerified
///                • The appointment is pushed to the patient's dashboard
///                  as an immutable, locked task.
///   cancelled  → Either party cancelled before the appointment date.
///   completed  → Appointment date has passed and was attended.
///   rescheduled→ Doctor moved the time; original [appointedAt] preserved
///                in [previousAppointedAt] for audit trail.
///
/// Conflict resolution (Blueprint §1.3):
///   "Server-Side Stamp wins" — if a doctor updates the schedule at the
///   exact moment a patient edits it, the server timestamp prevails.
///   Enforced in Firestore Security Rules; reflected here via [serverTimestamp].
///
/// Firestore path: `users/{patientId}/appointments/{appointmentId}`
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:vitalpath/models/governance_level.dart';

// ── Appointment status vocabulary ─────────────────────────────────────────────
enum AppointmentStatus {
  pending,
  confirmed,
  cancelled,
  completed,
  rescheduled,
}

extension AppointmentStatusX on AppointmentStatus {
  String toJson() => name; // pending, confirmed, cancelled, completed, rescheduled

  static AppointmentStatus fromJson(String? value) {
    return AppointmentStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => AppointmentStatus.pending,
    );
  }

  /// Human-readable label for UI display.
  String get label {
    switch (this) {
      case AppointmentStatus.pending:
        return 'Awaiting Confirmation';
      case AppointmentStatus.confirmed:
        return 'Confirmed';
      case AppointmentStatus.cancelled:
        return 'Cancelled';
      case AppointmentStatus.completed:
        return 'Completed';
      case AppointmentStatus.rescheduled:
        return 'Rescheduled';
    }
  }

  /// Whether this status represents an "active" appointment on the dashboard.
  bool get isActive =>
      this == AppointmentStatus.pending ||
      this == AppointmentStatus.confirmed ||
      this == AppointmentStatus.rescheduled;
}

// ── Appointment model ─────────────────────────────────────────────────────────
class AppointmentModel with GovernanceFields {
  // ── Identity ────────────────────────────────────────────────────────────────
  final String? id;
  final String patientId;
  final String doctorId;
  final String doctorName;

  // ── Request data (patient-authored) ─────────────────────────────────────────
  /// Why the patient is requesting the appointment.
  final String reason;

  /// Patient's preferred date/time — not binding until doctor confirms.
  final DateTime preferredAt;

  /// Optional patient notes.
  final String? patientNotes;

  // ── Confirmed schedule (doctor-authored) ─────────────────────────────────────
  /// The actual scheduled appointment date/time. Set by doctor on confirmation.
  final DateTime? appointedAt;

  /// Doctor's optional notes / instructions (e.g., "Bring last blood report").
  final String? doctorNotes;

  /// The previous appointment time, preserved when doctor reschedules.
  final DateTime? previousAppointedAt;

  // ── Lifecycle state ──────────────────────────────────────────────────────────
  final AppointmentStatus status;

  // ── Governance — applied on confirmation ─────────────────────────────────────
  /// True once the doctor confirms. The appointment becomes a locked dashboard
  /// task that the patient cannot edit or delete.
  @override
  final bool isVerified;

  @override
  final GovernanceLevel governanceLevel;

  // ── Timestamps ────────────────────────────────────────────────────────────────
  /// When the patient submitted the request.
  final DateTime requestedAt;

  /// When the doctor accepted/confirmed (null until then).
  final DateTime? confirmedAt;

  /// Last server-side write — the "Server-Side Stamp" used for conflict
  /// resolution. Firestore FieldValue.serverTimestamp() populates this.
  final DateTime? serverTimestamp;

  final DateTime updatedAt;

  // ── Constructor ───────────────────────────────────────────────────────────────
  const AppointmentModel({
    this.id,
    required this.patientId,
    required this.doctorId,
    required this.doctorName,
    required this.reason,
    required this.preferredAt,
    this.patientNotes,
    this.appointedAt,
    this.doctorNotes,
    this.previousAppointedAt,
    this.status = AppointmentStatus.pending,
    this.isVerified = false,
    this.governanceLevel = GovernanceLevel.patientManaged,
    required this.requestedAt,
    this.confirmedAt,
    this.serverTimestamp,
    required this.updatedAt,
  });

  // ── Convenience getters ───────────────────────────────────────────────────────

  /// True when this appointment should appear locked on the dashboard.
  bool get isDashboardLocked =>
      isVerified && status == AppointmentStatus.confirmed;

  /// The display time: [appointedAt] if confirmed, else [preferredAt].
  DateTime get displayTime => appointedAt ?? preferredAt;

  // ── Factory: apply Clinical Lock when doctor confirms ─────────────────────────
  /// Returns a new instance with governance fields locked.
  /// Called by [AppointmentProvider] when Firestore status → 'confirmed'.
  AppointmentModel applyClinicaLock({
    required DateTime confirmedAppointedAt,
    String? notes,
    required DateTime confirmedAt,
  }) {
    return AppointmentModel(
      id: id,
      patientId: patientId,
      doctorId: doctorId,
      doctorName: doctorName,
      reason: reason,
      preferredAt: preferredAt,
      patientNotes: patientNotes,
      appointedAt: confirmedAppointedAt,
      doctorNotes: notes ?? doctorNotes,
      previousAppointedAt: appointedAt, // preserve prior time for audit
      status: AppointmentStatus.confirmed,
      isVerified: true,                              // ← LOCKED
      governanceLevel: GovernanceLevel.physicianVerified, // ← LOCKED
      requestedAt: requestedAt,
      confirmedAt: confirmedAt,
      serverTimestamp: serverTimestamp,
      updatedAt: confirmedAt,
    );
  }

  // ── Serialisation ─────────────────────────────────────────────────────────────
  factory AppointmentModel.fromJson(Map<String, dynamic> json) {
    return AppointmentModel(
      id: json['id'] as String?,
      patientId: json['patient_id'] as String,
      doctorId: json['doctor_id'] as String,
      doctorName: json['doctor_name'] as String,
      reason: json['reason'] as String,
      preferredAt: DateTime.parse(json['preferred_at'] as String),
      patientNotes: json['patient_notes'] as String?,
      appointedAt: json['appointed_at'] != null
          ? DateTime.parse(json['appointed_at'] as String)
          : null,
      doctorNotes: json['doctor_notes'] as String?,
      previousAppointedAt: json['previous_appointed_at'] != null
          ? DateTime.parse(json['previous_appointed_at'] as String)
          : null,
      status: AppointmentStatusX.fromJson(json['status'] as String?),
      isVerified: json['is_verified'] as bool? ?? false,
      governanceLevel:
          GovernanceLevelX.fromJson(json['governance_level'] as String?),
      requestedAt: DateTime.parse(json['requested_at'] as String),
      confirmedAt: json['confirmed_at'] != null
          ? DateTime.parse(json['confirmed_at'] as String)
          : null,
      serverTimestamp: json['server_timestamp'] != null
          ? DateTime.parse(json['server_timestamp'] as String)
          : null,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'patient_id': patientId,
        'doctor_id': doctorId,
        'doctor_name': doctorName,
        'reason': reason,
        'preferred_at': preferredAt.toIso8601String(),
        if (patientNotes != null) 'patient_notes': patientNotes,
        if (appointedAt != null) 'appointed_at': appointedAt!.toIso8601String(),
        if (doctorNotes != null) 'doctor_notes': doctorNotes,
        if (previousAppointedAt != null)
          'previous_appointed_at': previousAppointedAt!.toIso8601String(),
        'status': status.toJson(),
        'requested_at': requestedAt.toIso8601String(),
        if (confirmedAt != null) 'confirmed_at': confirmedAt!.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        ...governanceToJson(),
      };

  AppointmentModel copyWith({
    String? id,
    AppointmentStatus? status,
    DateTime? appointedAt,
    String? doctorNotes,
    DateTime? confirmedAt,
    DateTime? updatedAt,
  }) {
    return AppointmentModel(
      id: id ?? this.id,
      patientId: patientId,
      doctorId: doctorId,
      doctorName: doctorName,
      reason: reason,
      preferredAt: preferredAt,
      patientNotes: patientNotes,
      appointedAt: appointedAt ?? this.appointedAt,
      doctorNotes: doctorNotes ?? this.doctorNotes,
      previousAppointedAt: previousAppointedAt,
      status: status ?? this.status,
      isVerified: isVerified,
      governanceLevel: governanceLevel,
      requestedAt: requestedAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      serverTimestamp: serverTimestamp,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'AppointmentModel(id: $id, doctor: $doctorName, '
      'status: ${status.name}, verified: $isVerified, '
      'at: ${appointedAt ?? preferredAt})';
}
