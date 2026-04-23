/// nutrition_model.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Represents a single nutrition / meal log entry in VitalPath.
///
/// Governance context:
///   A dietician or physician can push a dietary protocol directly to the
///   patient's app (e.g., a post-surgery meal plan). When pushed, the entry
///   carries [isVerified] = true and [governanceLevel] = physicianVerified,
///   preventing the patient from altering the prescribed regimen.
///
/// Firestore path: `users/{userId}/nutrition_logs/{logId}`
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:vitalpath/models/governance_level.dart';

// ── Meal category vocabulary ──────────────────────────────────────────────────

enum MealCategory { breakfast, lunch, dinner, snack, supplement, other }

extension MealCategoryX on MealCategory {
  String toJson() => name; // uses Dart enum .name (lowercase)

  static MealCategory fromJson(String? value) {
    return MealCategory.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MealCategory.other,
    );
  }

  String get label {
    switch (this) {
      case MealCategory.breakfast:
        return 'Breakfast';
      case MealCategory.lunch:
        return 'Lunch';
      case MealCategory.dinner:
        return 'Dinner';
      case MealCategory.snack:
        return 'Snack';
      case MealCategory.supplement:
        return 'Supplement';
      case MealCategory.other:
        return 'Other';
    }
  }
}

// ── Nutrition model ───────────────────────────────────────────────────────────

class NutritionModel with GovernanceFields {
  // ── Identity ────────────────────────────────────────────────────────────────
  final String? id;
  final String patientId;

  // ── Meal data ────────────────────────────────────────────────────────────────
  /// Human-readable name of the food or meal.
  final String foodName;

  /// Caloric value in kcal. Must be ≥ 0.
  final double calories;

  /// Protein in grams. Must be ≥ 0.
  final double proteinGrams;

  /// Carbohydrates in grams. Must be ≥ 0.
  final double carbsGrams;

  /// Fat in grams. Must be ≥ 0.
  final double fatGrams;

  /// Serving size descriptor (e.g., "1 cup", "200g").
  final String? servingSize;

  /// Category of the meal (breakfast, lunch, etc.).
  final MealCategory mealCategory;

  /// When the meal was consumed. Used for "Latest-First" sorting.
  final DateTime loggedAt;

  // ── Clinical protocol fields ──────────────────────────────────────────────
  /// Present when this entry is part of a physician-prescribed diet plan.
  final String? prescribingDoctorName;

  /// Optional protocol name (e.g., "Post-Op Diet Phase 1").
  final String? protocolName;

  // ── Governance ──────────────────────────────────────────────────────────────
  @override
  final bool isVerified;

  @override
  final GovernanceLevel governanceLevel;

  // ── Timestamps ───────────────────────────────────────────────────────────────
  final DateTime createdAt;
  final DateTime updatedAt;

  // ── Constructor ──────────────────────────────────────────────────────────────
  const NutritionModel({
    this.id,
    required this.patientId,
    required this.foodName,
    required this.calories,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
    this.servingSize,
    required this.mealCategory,
    required this.loggedAt,
    this.prescribingDoctorName,
    this.protocolName,
    this.isVerified = false,
    this.governanceLevel = GovernanceLevel.patientManaged,
    required this.createdAt,
    required this.updatedAt,
  });

  // ── Validation ───────────────────────────────────────────────────────────────
  List<String> validate() {
    final errors = <String>[];

    if (foodName.trim().isEmpty) {
      errors.add('Food name must not be empty.');
    }
    if (calories < 0) {
      errors.add('Calories cannot be negative (got $calories).');
    }
    if (proteinGrams < 0) {
      errors.add('Protein cannot be negative (got $proteinGrams g).');
    }
    if (carbsGrams < 0) {
      errors.add('Carbohydrates cannot be negative (got $carbsGrams g).');
    }
    if (fatGrams < 0) {
      errors.add('Fat cannot be negative (got $fatGrams g).');
    }
    if (governanceLevel == GovernanceLevel.physicianVerified &&
        (prescribingDoctorName == null ||
            prescribingDoctorName!.trim().isEmpty)) {
      errors.add(
        'A physicianVerified nutrition entry must include a prescribingDoctorName.',
      );
    }
    return errors;
  }

  void validateOrThrow() {
    final errors = validate();
    if (errors.isNotEmpty) {
      throw StateError(
        'NutritionModel validation failed:\n  • ${errors.join('\n  • ')}',
      );
    }
  }

  // ── Serialisation ─────────────────────────────────────────────────────────
  factory NutritionModel.fromJson(Map<String, dynamic> json) {
    return NutritionModel(
      id: json['id'] as String?,
      patientId: json['patient_id'] as String,
      foodName: json['food_name'] as String,
      calories: (json['calories'] as num).toDouble(),
      proteinGrams: (json['protein_grams'] as num).toDouble(),
      carbsGrams: (json['carbs_grams'] as num).toDouble(),
      fatGrams: (json['fat_grams'] as num).toDouble(),
      servingSize: json['serving_size'] as String?,
      mealCategory: MealCategoryX.fromJson(json['meal_category'] as String?),
      loggedAt: DateTime.parse(json['logged_at'] as String),
      prescribingDoctorName: json['prescribing_doctor_name'] as String?,
      protocolName: json['protocol_name'] as String?,
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
        'food_name': foodName,
        'calories': calories,
        'protein_grams': proteinGrams,
        'carbs_grams': carbsGrams,
        'fat_grams': fatGrams,
        if (servingSize != null) 'serving_size': servingSize,
        'meal_category': mealCategory.toJson(),
        'logged_at': loggedAt.toIso8601String(),
        if (prescribingDoctorName != null)
          'prescribing_doctor_name': prescribingDoctorName,
        if (protocolName != null) 'protocol_name': protocolName,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        ...governanceToJson(),
      };

  // ── CopyWith ─────────────────────────────────────────────────────────────────
  NutritionModel copyWith({
    String? id,
    String? patientId,
    String? foodName,
    double? calories,
    double? proteinGrams,
    double? carbsGrams,
    double? fatGrams,
    String? servingSize,
    MealCategory? mealCategory,
    DateTime? loggedAt,
    String? prescribingDoctorName,
    String? protocolName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NutritionModel(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      foodName: foodName ?? this.foodName,
      calories: calories ?? this.calories,
      proteinGrams: proteinGrams ?? this.proteinGrams,
      carbsGrams: carbsGrams ?? this.carbsGrams,
      fatGrams: fatGrams ?? this.fatGrams,
      servingSize: servingSize ?? this.servingSize,
      mealCategory: mealCategory ?? this.mealCategory,
      loggedAt: loggedAt ?? this.loggedAt,
      prescribingDoctorName:
          prescribingDoctorName ?? this.prescribingDoctorName,
      protocolName: protocolName ?? this.protocolName,
      // Governance preserved — cannot be changed via copyWith.
      isVerified: isVerified,
      governanceLevel: governanceLevel,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'NutritionModel(id: $id, food: $foodName, '
      'calories: ${calories}kcal, verified: $isVerified)';
}
