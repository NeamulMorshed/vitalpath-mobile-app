/// prescription_model.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// The core health record model for VitalPath's Prescription Vault.
///
/// Design decisions:
///   • Mixes in [GovernanceFields] — Clinical Lock lives here.
///   • [DosageUnit] enum enforces controlled vocabulary (mg / ml / pills).
///   • [validate()] runs business rules before any Firestore write.
///   • Immutable via `const` constructor + [copyWith] for safe state updates.
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:vitalpath/models/governance_level.dart';

// ── Dosage unit vocabulary ────────────────────────────────────────────────────

enum DosageUnit { mg, ml, pills }

extension DosageUnitX on DosageUnit {
  String toJson() {
    switch (this) {
      case DosageUnit.mg:
        return 'mg';
      case DosageUnit.ml:
        return 'ml';
      case DosageUnit.pills:
        return 'pills';
    }
  }

  /// Display label shown in the Prescription Vault UI.
  String get label {
    switch (this) {
      case DosageUnit.mg:
        return 'mg';
      case DosageUnit.ml:
        return 'ml';
      case DosageUnit.pills:
        return 'pill(s)';
    }
  }

  static DosageUnit fromJson(String? value) {
    switch (value) {
      case 'mg':
        return DosageUnit.mg;
      case 'ml':
        return DosageUnit.ml;
      case 'pills':
        return DosageUnit.pills;
      default:
        throw ArgumentError('Unknown DosageUnit: "$value".');
    }
  }
}

// ── Prescription model ────────────────────────────────────────────────────────

/// Represents a single prescription record in the Prescription Vault.
///
/// Firestore path: `users/{userId}/prescriptions/{prescriptionId}`
class PrescriptionModel with GovernanceFields {
  // ── Identity ────────────────────────────────────────────────────────────────
  /// Firestore document ID. Null before first save.
  final String? id;

  /// UID of the owning patient.
  final String patientId;

  // ── Clinical fields ─────────────────────────────────────────────────────────
  /// Name of the prescribing doctor.
  /// Used as the primary grouping key in the Prescription Vault.
  final String doctorName;

  /// Optional Firestore UID of the doctor. Present for Synced records.
  final String? doctorId;

  /// Human-readable drug / supplement name.
  final String medicineName;

  /// Amount per dose. Must be > 0 (enforced in [validate]).
  final double dosage;

  /// Unit of measurement for [dosage].
  final DosageUnit unit;

  /// Free-text instructions (e.g. "Take after meals").
  final String? instructions;

  // ── Schedule ────────────────────────────────────────────────────────────────
  /// Inclusive start date of the prescription course.
  final DateTime startDate;

  /// Inclusive end date. Must be ≥ [startDate] (enforced in [validate]).
  final DateTime endDate;

  // ── Governance ──────────────────────────────────────────────────────────────
  /// True when a physician has pushed and locked this record.
  @override
  final bool isVerified;

  /// Authority level governing mutation rights.
  @override
  final GovernanceLevel governanceLevel;

  // ── Timestamps ──────────────────────────────────────────────────────────────
  /// Server timestamp of record creation.
  final DateTime createdAt;

  /// Server timestamp of the most recent update.
  /// Drives the "Latest-First" sort in the Prescription Vault.
  final DateTime updatedAt;

  // ── Constructor ─────────────────────────────────────────────────────────────
  const PrescriptionModel({
    this.id,
    required this.patientId,
    required this.doctorName,
    this.doctorId,
    required this.medicineName,
    required this.dosage,
    required this.unit,
    this.instructions,
    required this.startDate,
    required this.endDate,
    this.isVerified = false,
    this.governanceLevel = GovernanceLevel.patientManaged,
    required this.createdAt,
    required this.updatedAt,
  });

  // ── Validation ──────────────────────────────────────────────────────────────
  /// Runs all business-rule checks before a Firestore write.
  ///
  /// Returns a non-empty list of human-readable error strings on failure,
  /// or an empty list when the record is valid.
  List<String> validate() {
    final errors = <String>[];

    // Rule 1: Dosage must be a positive number.
    if (dosage <= 0) {
      errors.add('Dosage must be a positive value (got $dosage).');
    }

    // Rule 2: Dosage must be finite and not NaN.
    if (dosage.isNaN || dosage.isInfinite) {
      errors.add('Dosage must be a valid finite number.');
    }

    // Rule 3: start_date cannot be after end_date.
    if (startDate.isAfter(endDate)) {
      errors.add(
        'Start date (${startDate.toIso8601String()}) cannot be after '
        'end date (${endDate.toIso8601String()}).',
      );
    }

    // Rule 4: Doctor name must not be blank.
    if (doctorName.trim().isEmpty) {
      errors.add('Doctor name must not be empty.');
    }

    // Rule 5: Medicine name must not be blank.
    if (medicineName.trim().isEmpty) {
      errors.add('Medicine name must not be empty.');
    }

    // Rule 6: Governance consistency guard.
    // A record cannot be physicianVerified without a doctorId.
    if (governanceLevel == GovernanceLevel.physicianVerified &&
        (doctorId == null || doctorId!.trim().isEmpty)) {
      errors.add(
        'A physicianVerified record must carry a non-empty doctorId.',
      );
    }

    return errors;
  }

  /// Throws a [StateError] if the model is invalid.
  /// Convenient for use in repository save operations.
  void validateOrThrow() {
    final errors = validate();
    if (errors.isNotEmpty) {
      throw StateError(
        'PrescriptionModel validation failed:\n  • ${errors.join('\n  • ')}',
      );
    }
  }

  // ── Serialisation ────────────────────────────────────────────────────────────
  factory PrescriptionModel.fromJson(Map<String, dynamic> json) {
    return PrescriptionModel(
      id: json['id'] as String?,
      patientId: json['patient_id'] as String,
      doctorName: json['doctor_name'] as String,
      doctorId: json['doctor_id'] as String?,
      medicineName: json['medicine_name'] as String,
      dosage: (json['dosage'] as num).toDouble(),
      unit: DosageUnitX.fromJson(json['unit'] as String?),
      instructions: json['instructions'] as String?,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      isVerified: json['is_verified'] as bool? ?? false,
      governanceLevel: GovernanceLevelX.fromJson(
        json['governance_level'] as String?,
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'patient_id': patientId,
        'doctor_name': doctorName,
        if (doctorId != null) 'doctor_id': doctorId,
        'medicine_name': medicineName,
        'dosage': dosage,
        'unit': unit.toJson(),
        if (instructions != null) 'instructions': instructions,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        // Governance fields via mixin helper.
        ...governanceToJson(),
      };

  // ── CopyWith ─────────────────────────────────────────────────────────────────
  /// Returns a new instance with the specified fields replaced.
  ///
  /// NOTE: [isVerified] and [governanceLevel] are intentionally excluded from
  /// [copyWith]. Governance transitions must go through the dedicated
  /// `PrescriptionRepository.applyClinicaLock()` method, which verifies
  /// doctor authority before writing, keeping mutation paths explicit.
  PrescriptionModel copyWith({
    String? id,
    String? patientId,
    String? doctorName,
    String? doctorId,
    String? medicineName,
    double? dosage,
    DosageUnit? unit,
    String? instructions,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PrescriptionModel(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      doctorName: doctorName ?? this.doctorName,
      doctorId: doctorId ?? this.doctorId,
      medicineName: medicineName ?? this.medicineName,
      dosage: dosage ?? this.dosage,
      unit: unit ?? this.unit,
      instructions: instructions ?? this.instructions,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      // Governance fields are preserved — cannot be downgraded via copyWith.
      isVerified: isVerified,
      governanceLevel: governanceLevel,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'PrescriptionModel(id: $id, medicine: $medicineName, '
      'dosage: $dosage${unit.label}, doctor: $doctorName, '
      'verified: $isVerified, governance: ${governanceLevel.toJson()})';
}
