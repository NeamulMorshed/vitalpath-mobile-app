/// governance_level.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Defines the clinical authority level of any health record in VitalPath.
///
/// Rules (enforced at both the Firestore security-rules layer AND the UI layer):
///   • [patientManaged]    → Patient has full CRUD rights.
///   • [physicianVerified] → Record is immutable to the patient ("Clinical Lock").
///                           Only a doctor-authenticated write may mutate it.
/// ─────────────────────────────────────────────────────────────────────────────

enum GovernanceLevel {
  /// Patient created and controls this record.
  patientManaged,

  /// Doctor-pushed record. Locked from patient edits/deletes.
  physicianVerified,
}

/// Extension providing JSON serialisation helpers for [GovernanceLevel].
extension GovernanceLevelX on GovernanceLevel {
  /// Converts to the snake_case string stored in Firestore.
  String toJson() {
    switch (this) {
      case GovernanceLevel.patientManaged:
        return 'patient_managed';
      case GovernanceLevel.physicianVerified:
        return 'physician_verified';
    }
  }

  /// Reconstructs a [GovernanceLevel] from a Firestore string value.
  /// Throws [ArgumentError] on unknown values to surface data corruption early.
  static GovernanceLevel fromJson(String? value) {
    switch (value) {
      case 'patient_managed':
        return GovernanceLevel.patientManaged;
      case 'physician_verified':
        return GovernanceLevel.physicianVerified;
      default:
        throw ArgumentError(
          'Unknown GovernanceLevel value: "$value". '
          'Expected "patient_managed" or "physician_verified".',
        );
    }
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// [GovernanceFields] — shared field contract mixed into every health model.
///
/// Any model that participates in the Clinical Lock system must expose:
///   • [isVerified]      — quick boolean guard used in Security Rules & UI.
///   • [governanceLevel] — richer enum for display logic and future extensions.
/// ─────────────────────────────────────────────────────────────────────────────
mixin GovernanceFields {
  /// True when a physician has pushed and locked this record.
  /// Maps to the Firestore field `is_verified`.
  bool get isVerified;

  /// The authority level governing mutation rights on this record.
  /// Maps to the Firestore field `governance_level`.
  GovernanceLevel get governanceLevel;

  /// Convenience guard: returns true when a patient is allowed to mutate
  /// this record. UI layers should gate edit/delete widgets behind this check.
  bool get isPatientEditable =>
      !isVerified && governanceLevel == GovernanceLevel.patientManaged;

  /// Serialises the governance fields shared across all models.
  Map<String, dynamic> governanceToJson() => {
        'is_verified': isVerified,
        'governance_level': governanceLevel.toJson(),
      };
}
