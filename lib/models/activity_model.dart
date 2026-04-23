/// activity_model.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Represents a single physical activity log in VitalPath.
///
/// Governance context:
///   A physician or physiotherapist can prescribe a rehabilitation exercise
///   protocol (e.g., post-surgery physiotherapy). These entries are pushed
///   via the doctor sync flow and locked as [isVerified] = true. The patient
///   can log adherence (mark as done) but cannot alter the prescribed
///   parameters (duration, intensity targets).
///
/// Firestore path: `users/{userId}/activity_logs/{logId}`
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:vitalpath/models/governance_level.dart';

// ── Activity type vocabulary ──────────────────────────────────────────────────

enum ActivityType {
  walking,
  running,
  cycling,
  swimming,
  strengthTraining,
  yoga,
  physiotherapy,
  other,
}

extension ActivityTypeX on ActivityType {
  String toJson() => name;

  static ActivityType fromJson(String? value) {
    return ActivityType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ActivityType.other,
    );
  }

  String get label {
    switch (this) {
      case ActivityType.walking:
        return 'Walking';
      case ActivityType.running:
        return 'Running';
      case ActivityType.cycling:
        return 'Cycling';
      case ActivityType.swimming:
        return 'Swimming';
      case ActivityType.strengthTraining:
        return 'Strength Training';
      case ActivityType.yoga:
        return 'Yoga';
      case ActivityType.physiotherapy:
        return 'Physiotherapy';
      case ActivityType.other:
        return 'Other';
    }
  }
}

// ── Intensity level vocabulary ────────────────────────────────────────────────

enum IntensityLevel { low, moderate, high }

extension IntensityLevelX on IntensityLevel {
  String toJson() => name;

  static IntensityLevel fromJson(String? value) {
    return IntensityLevel.values.firstWhere(
      (e) => e.name == value,
      orElse: () => IntensityLevel.moderate,
    );
  }
}

// ── Activity model ────────────────────────────────────────────────────────────

class ActivityModel with GovernanceFields {
  // ── Identity ────────────────────────────────────────────────────────────────
  final String? id;
  final String patientId;

  // ── Activity data ────────────────────────────────────────────────────────────
  /// Type of physical activity.
  final ActivityType activityType;

  /// Duration in minutes. Must be > 0.
  final int durationMinutes;

  /// Estimated calories burned in kcal. Must be ≥ 0.
  final double caloriesBurned;

  /// Number of steps recorded (applicable for walking/running).
  final int? stepCount;

  /// Distance covered in kilometres. Must be ≥ 0 if provided.
  final double? distanceKm;

  /// Perceived or prescribed intensity level.
  final IntensityLevel intensity;

  /// Optional notes or observations (e.g., "felt dizzy at 20 min").
  final String? notes;

  /// When the activity was performed. Used for "Latest-First" sorting.
  final DateTime performedAt;

  // ── Clinical protocol fields ──────────────────────────────────────────────
  /// Present when this is a physician-prescribed exercise prescription.
  final String? prescribingDoctorName;

  /// Protocol name (e.g., "Knee Rehab Phase 2").
  final String? protocolName;

  /// Whether the patient has marked this prescribed activity as completed.
  /// Patients CAN toggle this even on verified entries — it's adherence logging,
  /// not a mutation of the clinical prescription.
  final bool isCompleted;

  // ── Governance ──────────────────────────────────────────────────────────────
  @override
  final bool isVerified;

  @override
  final GovernanceLevel governanceLevel;

  // ── Timestamps ───────────────────────────────────────────────────────────────
  final DateTime createdAt;
  final DateTime updatedAt;

  // ── Constructor ──────────────────────────────────────────────────────────────
  const ActivityModel({
    this.id,
    required this.patientId,
    required this.activityType,
    required this.durationMinutes,
    required this.caloriesBurned,
    this.stepCount,
    this.distanceKm,
    required this.intensity,
    this.notes,
    required this.performedAt,
    this.prescribingDoctorName,
    this.protocolName,
    this.isCompleted = false,
    this.isVerified = false,
    this.governanceLevel = GovernanceLevel.patientManaged,
    required this.createdAt,
    required this.updatedAt,
  });

  // ── Validation ───────────────────────────────────────────────────────────────
  List<String> validate() {
    final errors = <String>[];

    if (durationMinutes <= 0) {
      errors.add(
        'Duration must be a positive number of minutes (got $durationMinutes).',
      );
    }
    if (caloriesBurned < 0) {
      errors.add('Calories burned cannot be negative (got $caloriesBurned).');
    }
    if (stepCount != null && stepCount! < 0) {
      errors.add('Step count cannot be negative (got $stepCount).');
    }
    if (distanceKm != null && distanceKm! < 0) {
      errors.add('Distance cannot be negative (got $distanceKm km).');
    }
    if (governanceLevel == GovernanceLevel.physicianVerified &&
        (prescribingDoctorName == null ||
            prescribingDoctorName!.trim().isEmpty)) {
      errors.add(
        'A physicianVerified activity must include a prescribingDoctorName.',
      );
    }
    return errors;
  }

  void validateOrThrow() {
    final errors = validate();
    if (errors.isNotEmpty) {
      throw StateError(
        'ActivityModel validation failed:\n  • ${errors.join('\n  • ')}',
      );
    }
  }

  // ── Serialisation ─────────────────────────────────────────────────────────
  factory ActivityModel.fromJson(Map<String, dynamic> json) {
    return ActivityModel(
      id: json['id'] as String?,
      patientId: json['patient_id'] as String,
      activityType: ActivityTypeX.fromJson(json['activity_type'] as String?),
      durationMinutes: json['duration_minutes'] as int,
      caloriesBurned: (json['calories_burned'] as num).toDouble(),
      stepCount: json['step_count'] as int?,
      distanceKm: json['distance_km'] != null
          ? (json['distance_km'] as num).toDouble()
          : null,
      intensity: IntensityLevelX.fromJson(json['intensity'] as String?),
      notes: json['notes'] as String?,
      performedAt: DateTime.parse(json['performed_at'] as String),
      prescribingDoctorName: json['prescribing_doctor_name'] as String?,
      protocolName: json['protocol_name'] as String?,
      isCompleted: json['is_completed'] as bool? ?? false,
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
        'activity_type': activityType.toJson(),
        'duration_minutes': durationMinutes,
        'calories_burned': caloriesBurned,
        if (stepCount != null) 'step_count': stepCount,
        if (distanceKm != null) 'distance_km': distanceKm,
        'intensity': intensity.toJson(),
        if (notes != null) 'notes': notes,
        'performed_at': performedAt.toIso8601String(),
        if (prescribingDoctorName != null)
          'prescribing_doctor_name': prescribingDoctorName,
        if (protocolName != null) 'protocol_name': protocolName,
        'is_completed': isCompleted,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        ...governanceToJson(),
      };

  // ── CopyWith ─────────────────────────────────────────────────────────────────
  /// NOTE: [isCompleted] IS included in copyWith — patients are allowed to
  /// mark a prescribed activity as done (adherence logging).
  /// [isVerified] and [governanceLevel] are excluded as always.
  ActivityModel copyWith({
    String? id,
    String? patientId,
    ActivityType? activityType,
    int? durationMinutes,
    double? caloriesBurned,
    int? stepCount,
    double? distanceKm,
    IntensityLevel? intensity,
    String? notes,
    DateTime? performedAt,
    String? prescribingDoctorName,
    String? protocolName,
    bool? isCompleted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ActivityModel(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      activityType: activityType ?? this.activityType,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      caloriesBurned: caloriesBurned ?? this.caloriesBurned,
      stepCount: stepCount ?? this.stepCount,
      distanceKm: distanceKm ?? this.distanceKm,
      intensity: intensity ?? this.intensity,
      notes: notes ?? this.notes,
      performedAt: performedAt ?? this.performedAt,
      prescribingDoctorName:
          prescribingDoctorName ?? this.prescribingDoctorName,
      protocolName: protocolName ?? this.protocolName,
      isCompleted: isCompleted ?? this.isCompleted,
      // Governance preserved.
      isVerified: isVerified,
      governanceLevel: governanceLevel,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'ActivityModel(id: $id, type: ${activityType.label}, '
      'duration: ${durationMinutes}min, verified: $isVerified, '
      'completed: $isCompleted)';
}
