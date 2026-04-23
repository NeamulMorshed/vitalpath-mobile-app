/// doctor_sync_service.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Firebase logic for the doctor-patient sync handshake.
///
/// Blueprint §1.1 / §7 — "My Doctors" sync protocol:
///   1. Patient enters a 6-digit numeric code OR scans a QR code.
///   2. [validateCode] queries Firestore `doctors` collection for a matching
///      sync_code field. Returns the matched [DoctorModel] or null.
///   3. On match: [linkDoctor] writes to the patient's linked_doctors
///      sub-collection with status 'connected' and the current timestamp.
///   4. [unlinkDoctor] removes the document from linked_doctors.
///   5. [streamLinkedDoctors] provides a real-time snapshot for the UI.
///
/// ── Firestore schema ─────────────────────────────────────────────────────────
///
///   doctors/{doctorId}                 ← written by doctor-side app / Admin SDK
///     sync_code: "847291"              ← 6-digit numeric code, rotated daily
///     name: "Patel"
///     specialty: "Cardiologist"
///     clinic_name: "City Heart Clinic"
///     avatar_url: null | "https://…"
///
///   users/{patientId}/linked_doctors/{doctorId}
///     doctor_id:   string
///     name:        string
///     specialty:   string
///     clinic_name: string
///     avatar_url:  string | null
///     sync_status: "connected" | "pending" | "disconnected"
///     synced_at:   ISO-8601 timestamp
///
/// ── Add to firestore.rules ───────────────────────────────────────────────────
///
///   match /doctors/{doctorId} {
///     // Any authenticated patient may look up a sync code.
///     allow read: if request.auth != null;
///     // Only doctor-side Admin SDK may write doctor profiles.
///     allow write: if false;
///   }
///
///   match /users/{userId}/linked_doctors/{doctorId} {
///     allow read, write: if request.auth != null
///                        && request.auth.uid == userId;
///   }
///
/// ── QR code format ───────────────────────────────────────────────────────────
///   QR codes encode: "vitalpath://sync/{6-digit-code}"
///   [parseSyncCodeFromQr] extracts the code from this URI scheme.
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

import 'package:vitalpath/models/doctor_model.dart';

// ── Firestore call contracts (injectable; real Firebase shown in comments) ─────

typedef FirestoreQueryFn = Future<List<Map<String, dynamic>>> Function({
  required String collection,
  required String field,
  required String value,
});

typedef FirestoreWriteDoctorFn = Future<void> Function({
  required String path,
  required Map<String, dynamic> data,
});

typedef FirestoreDeleteFn = Future<void> Function({required String path});

typedef FirestoreStreamFn = Stream<List<Map<String, dynamic>>> Function({
  required String collection,
});

// ── DoctorSyncException ───────────────────────────────────────────────────────
class DoctorSyncException implements Exception {
  final String message;
  final DoctorSyncErrorType type;

  const DoctorSyncException(this.message, this.type);

  @override
  String toString() => 'DoctorSyncException(${type.name}): $message';
}

enum DoctorSyncErrorType { invalidCode, alreadyLinked, networkError, unknown }

// ── DoctorSyncService ─────────────────────────────────────────────────────────
class DoctorSyncService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static DoctorSyncService? _instance;
  factory DoctorSyncService({
    FirestoreQueryFn? queryFn,
    FirestoreWriteDoctorFn? writeFn,
    FirestoreDeleteFn? deleteFn,
    FirestoreStreamFn? streamFn,
  }) {
    _instance ??= DoctorSyncService._internal(
      queryFn: queryFn,
      writeFn: writeFn,
      deleteFn: deleteFn,
      streamFn: streamFn,
    );
    return _instance!;
  }

  DoctorSyncService._internal({
    FirestoreQueryFn? queryFn,
    FirestoreWriteDoctorFn? writeFn,
    FirestoreDeleteFn? deleteFn,
    FirestoreStreamFn? streamFn,
  })  : _queryFn = queryFn,
        _writeFn = writeFn,
        _deleteFn = deleteFn,
        _streamFn = streamFn;

  final FirestoreQueryFn? _queryFn;
  final FirestoreWriteDoctorFn? _writeFn;
  final FirestoreDeleteFn? _deleteFn;
  final FirestoreStreamFn? _streamFn;

  // ── Validate a 6-digit sync code ───────────────────────────────────────────
  /// Queries `doctors` collection for a document where `sync_code == code`.
  /// Returns the matched [DoctorModel], or null if the code is invalid.
  ///
  /// Real Firestore implementation:
  /// ```dart
  /// final snap = await FirebaseFirestore.instance
  ///   .collection('doctors')
  ///   .where('sync_code', isEqualTo: code)
  ///   .limit(1)
  ///   .get();
  /// if (snap.docs.isEmpty) return null;
  /// final data = {...snap.docs.first.data(), 'doctor_id': snap.docs.first.id};
  /// return DoctorModel.fromJson(data);
  /// ```
  Future<DoctorModel?> validateCode(String code) async {
    final sanitised = code.trim();
    if (sanitised.length != 6 || int.tryParse(sanitised) == null) {
      throw const DoctorSyncException(
        'Sync code must be exactly 6 digits.',
        DoctorSyncErrorType.invalidCode,
      );
    }

    try {
      if (_queryFn != null) {
        final results = await _queryFn(
          collection: 'doctors',
          field: 'sync_code',
          value: sanitised,
        );
        if (results.isEmpty) return null;
        return DoctorModel.fromJson(results.first);
      }

      // ── Stub: returns a fake doctor in debug for UI testing ────────────────
      if (kDebugMode && sanitised == '123456') {
        await Future.delayed(const Duration(milliseconds: 800));
        return const DoctorModel(
          uid: 'debug-doctor-001',
          name: 'Patel',
          specialty: 'Cardiologist',
          clinicName: 'City Heart Clinic',
          syncStatus: DoctorSyncStatus.connected,
        );
      }

      await Future.delayed(const Duration(milliseconds: 800));
      return null; // invalid code in stub mode
    } catch (e) {
      if (e is DoctorSyncException) rethrow;
      throw DoctorSyncException(
        'Network error while validating code: $e',
        DoctorSyncErrorType.networkError,
      );
    }
  }

  // ── Link a doctor to a patient ─────────────────────────────────────────────
  /// Writes to `users/{patientId}/linked_doctors/{doctorId}`.
  /// Sets `sync_status = connected` and stamps `synced_at`.
  ///
  /// Real Firestore implementation:
  /// ```dart
  /// await FirebaseFirestore.instance
  ///   .doc('users/$patientId/linked_doctors/${doctor.uid}')
  ///   .set({
  ///     ...doctor.toJson(),
  ///     'sync_status': DoctorSyncStatus.connected.toJson(),
  ///     'synced_at': FieldValue.serverTimestamp(),
  ///   }, SetOptions(merge: true));
  /// ```
  Future<DoctorModel> linkDoctor({
    required String patientId,
    required DoctorModel doctor,
    required List<DoctorModel> existingDoctors,
  }) async {
    if (existingDoctors.any((d) => d.uid == doctor.uid && d.isConnected)) {
      throw const DoctorSyncException(
        'This doctor is already connected to your account.',
        DoctorSyncErrorType.alreadyLinked,
      );
    }

    final syncedAt = DateTime.now();
    final linked = doctor.copyWith(
      syncStatus: DoctorSyncStatus.connected,
      syncedAt: syncedAt,
    );

    try {
      if (_writeFn != null) {
        await _writeFn(
          path: 'users/$patientId/linked_doctors/${doctor.uid}',
          data: linked.toJson(),
        );
      } else {
        // Stub: simulate network latency.
        await Future.delayed(const Duration(milliseconds: 400));
        debugPrint('[DoctorSync] Linked doctor ${doctor.uid} to patient $patientId');
      }
      return linked;
    } catch (e) {
      if (e is DoctorSyncException) rethrow;
      throw DoctorSyncException(
        'Failed to link doctor: $e',
        DoctorSyncErrorType.networkError,
      );
    }
  }

  // ── Unlink a doctor from a patient ─────────────────────────────────────────
  /// Deletes `users/{patientId}/linked_doctors/{doctorId}`.
  ///
  /// Real Firestore implementation:
  /// ```dart
  /// await FirebaseFirestore.instance
  ///   .doc('users/$patientId/linked_doctors/$doctorId')
  ///   .delete();
  /// ```
  Future<void> unlinkDoctor({
    required String patientId,
    required String doctorId,
  }) async {
    try {
      if (_deleteFn != null) {
        await _deleteFn(
          path: 'users/$patientId/linked_doctors/$doctorId',
        );
      } else {
        await Future.delayed(const Duration(milliseconds: 300));
        debugPrint('[DoctorSync] Unlinked doctor $doctorId from patient $patientId');
      }
    } catch (e) {
      throw DoctorSyncException(
        'Failed to unlink doctor: $e',
        DoctorSyncErrorType.networkError,
      );
    }
  }

  // ── Real-time stream of linked doctors ─────────────────────────────────────
  /// Listens to `users/{patientId}/linked_doctors` and emits the full list
  /// on every Firestore change.
  ///
  /// Real Firestore implementation:
  /// ```dart
  /// return FirebaseFirestore.instance
  ///   .collection('users/$patientId/linked_doctors')
  ///   .snapshots()
  ///   .map((snap) => snap.docs
  ///       .map((d) => DoctorModel.fromJson({...d.data(), 'doctor_id': d.id}))
  ///       .toList());
  /// ```
  Stream<List<DoctorModel>> streamLinkedDoctors(String patientId) {
    if (_streamFn != null) {
      return _streamFn(
        collection: 'users/$patientId/linked_doctors',
      ).map((docs) => docs.map(DoctorModel.fromJson).toList());
    }

    // Stub: emits an empty list once.
    return Stream.value([]);
  }

  // ── QR code parser ─────────────────────────────────────────────────────────
  /// Extracts the 6-digit sync code from a QR payload.
  /// Expected format: "vitalpath://sync/847291"
  /// Returns null if the payload doesn't match the expected scheme.
  static String? parseSyncCodeFromQr(String qrPayload) {
    final uri = Uri.tryParse(qrPayload);
    if (uri == null) return null;
    if (uri.scheme != 'vitalpath') return null;
    if (uri.host != 'sync') return null;
    final code = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (code == null || code.length != 6 || int.tryParse(code) == null) {
      return null;
    }
    return code;
  }
}
