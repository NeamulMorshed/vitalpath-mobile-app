import 'dart:convert';

enum UserRole { patient, doctor, familyMember }

extension UserRoleX on UserRole {
  String get label {
    switch (this) {
      case UserRole.patient:
        return 'Patient';
      case UserRole.doctor:
        return 'Doctor';
      case UserRole.familyMember:
        return 'Family Member';
    }
  }

  String get key {
    switch (this) {
      case UserRole.patient:
        return 'patient';
      case UserRole.doctor:
        return 'doctor';
      case UserRole.familyMember:
        return 'familyMember';
    }
  }

  static UserRole fromKey(String key) {
    switch (key) {
      case 'doctor':
        return UserRole.doctor;
      case 'familyMember':
        return UserRole.familyMember;
      default:
        return UserRole.patient;
    }
  }
}

class UserProfileModel {
  final UserRole role;
  final String displayName;

  // Patient-specific
  final String? dateOfBirth;
  final String? gender;
  final String? primaryCondition;
  final String? emergencyContactName;
  final String? emergencyContactPhone;

  // Doctor-specific
  final String? specialty;
  final String? clinicName;
  final String? licenseNumber;
  final String? doctorSyncCode;

  // Family member-specific
  final String? relationship;
  final String? linkedPatientName;

  const UserProfileModel({
    required this.role,
    required this.displayName,
    this.dateOfBirth,
    this.gender,
    this.primaryCondition,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.specialty,
    this.clinicName,
    this.licenseNumber,
    this.doctorSyncCode,
    this.relationship,
    this.linkedPatientName,
  });

  Map<String, dynamic> toJson() => {
        'role': role.key,
        'displayName': displayName,
        if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
        if (gender != null) 'gender': gender,
        if (primaryCondition != null) 'primaryCondition': primaryCondition,
        if (emergencyContactName != null)
          'emergencyContactName': emergencyContactName,
        if (emergencyContactPhone != null)
          'emergencyContactPhone': emergencyContactPhone,
        if (specialty != null) 'specialty': specialty,
        if (clinicName != null) 'clinicName': clinicName,
        if (licenseNumber != null) 'licenseNumber': licenseNumber,
        if (doctorSyncCode != null) 'doctorSyncCode': doctorSyncCode,
        if (relationship != null) 'relationship': relationship,
        if (linkedPatientName != null) 'linkedPatientName': linkedPatientName,
      };

  factory UserProfileModel.fromJson(Map<String, dynamic> json) =>
      UserProfileModel(
        role: UserRoleX.fromKey(json['role'] as String? ?? 'patient'),
        displayName: json['displayName'] as String? ?? '',
        dateOfBirth: json['dateOfBirth'] as String?,
        gender: json['gender'] as String?,
        primaryCondition: json['primaryCondition'] as String?,
        emergencyContactName: json['emergencyContactName'] as String?,
        emergencyContactPhone: json['emergencyContactPhone'] as String?,
        specialty: json['specialty'] as String?,
        clinicName: json['clinicName'] as String?,
        licenseNumber: json['licenseNumber'] as String?,
        doctorSyncCode: json['doctorSyncCode'] as String?,
        relationship: json['relationship'] as String?,
        linkedPatientName: json['linkedPatientName'] as String?,
      );

  factory UserProfileModel.fromJsonString(String jsonStr) =>
      UserProfileModel.fromJson(
          jsonDecode(jsonStr) as Map<String, dynamic>);

  String toJsonString() => jsonEncode(toJson());

  UserProfileModel copyWith({
    UserRole? role,
    String? displayName,
    String? dateOfBirth,
    String? gender,
    String? primaryCondition,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? specialty,
    String? clinicName,
    String? licenseNumber,
    String? doctorSyncCode,
    String? relationship,
    String? linkedPatientName,
  }) =>
      UserProfileModel(
        role: role ?? this.role,
        displayName: displayName ?? this.displayName,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        gender: gender ?? this.gender,
        primaryCondition: primaryCondition ?? this.primaryCondition,
        emergencyContactName:
            emergencyContactName ?? this.emergencyContactName,
        emergencyContactPhone:
            emergencyContactPhone ?? this.emergencyContactPhone,
        specialty: specialty ?? this.specialty,
        clinicName: clinicName ?? this.clinicName,
        licenseNumber: licenseNumber ?? this.licenseNumber,
        doctorSyncCode: doctorSyncCode ?? this.doctorSyncCode,
        relationship: relationship ?? this.relationship,
        linkedPatientName: linkedPatientName ?? this.linkedPatientName,
      );
}
