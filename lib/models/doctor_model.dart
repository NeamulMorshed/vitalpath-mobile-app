/// doctor_model.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Canonical model for a doctor linked to a VitalPath patient.
///
/// Blueprint §1.1 / §7 — "My Doctors":
///   Patients link to doctors via a 6-digit sync code or QR scan.
///   Once linked, the doctor appears in the Profile tab with name, specialty,
///   clinic name, and a sync status badge ('Connected' | 'Pending').
///
/// Firestore paths:
///   Patient side: users/{patientId}/linked_doctors/{doctorId}
///   Doctor side:  doctors/{doctorId}  (read-only from patient app)
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

// ── Sync status vocabulary ────────────────────────────────────────────────────
enum DoctorSyncStatus { connected, pending, disconnected }

extension DoctorSyncStatusX on DoctorSyncStatus {
  String toJson() => name;

  static DoctorSyncStatus fromJson(String? v) {
    return DoctorSyncStatus.values.firstWhere(
      (s) => s.name == v,
      orElse: () => DoctorSyncStatus.pending,
    );
  }

  String get label {
    switch (this) {
      case DoctorSyncStatus.connected:
        return 'Connected';
      case DoctorSyncStatus.pending:
        return 'Pending';
      case DoctorSyncStatus.disconnected:
        return 'Disconnected';
    }
  }

  Color get color {
    switch (this) {
      case DoctorSyncStatus.connected:
        return const Color(0xFF00897B);
      case DoctorSyncStatus.pending:
        return const Color(0xFFF59E0B);
      case DoctorSyncStatus.disconnected:
        return const Color(0xFF9E9E9E);
    }
  }

  Color get backgroundColor {
    switch (this) {
      case DoctorSyncStatus.connected:
        return const Color(0xFFE6F7F4);
      case DoctorSyncStatus.pending:
        return const Color(0xFFFEF3C7);
      case DoctorSyncStatus.disconnected:
        return const Color(0xFFF5F5F5);
    }
  }

  IconData get icon {
    switch (this) {
      case DoctorSyncStatus.connected:
        return Icons.verified_rounded;
      case DoctorSyncStatus.pending:
        return Icons.sync_rounded;
      case DoctorSyncStatus.disconnected:
        return Icons.link_off_rounded;
    }
  }
}

// ── DoctorModel ───────────────────────────────────────────────────────────────
class DoctorModel {
  final String uid;
  final String name;
  final String specialty;
  final String clinicName;
  final String? avatarUrl;
  final DoctorSyncStatus syncStatus;
  final DateTime? syncedAt;

  const DoctorModel({
    required this.uid,
    required this.name,
    required this.specialty,
    required this.clinicName,
    this.avatarUrl,
    this.syncStatus = DoctorSyncStatus.pending,
    this.syncedAt,
  });

  bool get isConnected => syncStatus == DoctorSyncStatus.connected;

  // ── Serialisation ──────────────────────────────────────────────────────────
  factory DoctorModel.fromJson(Map<String, dynamic> json) {
    return DoctorModel(
      uid: json['doctor_id'] as String,
      name: json['name'] as String,
      specialty: json['specialty'] as String,
      clinicName: json['clinic_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      syncStatus: DoctorSyncStatusX.fromJson(json['sync_status'] as String?),
      syncedAt: json['synced_at'] != null
          ? DateTime.parse(json['synced_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'doctor_id': uid,
        'name': name,
        'specialty': specialty,
        'clinic_name': clinicName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'sync_status': syncStatus.toJson(),
        if (syncedAt != null) 'synced_at': syncedAt!.toIso8601String(),
      };

  DoctorModel copyWith({
    DoctorSyncStatus? syncStatus,
    DateTime? syncedAt,
    String? clinicName,
  }) {
    return DoctorModel(
      uid: uid,
      name: name,
      specialty: specialty,
      clinicName: clinicName ?? this.clinicName,
      avatarUrl: avatarUrl,
      syncStatus: syncStatus ?? this.syncStatus,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  @override
  String toString() =>
      'DoctorModel(uid: $uid, name: $name, specialty: $specialty, '
      'clinic: $clinicName, status: ${syncStatus.name})';
}
