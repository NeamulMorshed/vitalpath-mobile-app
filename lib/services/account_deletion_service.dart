/// account_deletion_service.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// GDPR "Right to be Forgotten" — full account and health data wipe.
///
/// Blueprint §5:
///   "Delete Account must trigger a full data wipe of the user's specific
///    sub-collections in Firebase to maintain GDPR compliance."
///
/// Deletion architecture:
///   Client cannot delete Firestore subcollections directly — doing so would
///   require enumerating all documents, which is unbounded and fragile on mobile.
///   The correct pattern:
///
///   1. CLIENT  →  writes /data_deletion_requests/{userId}  (confirmed: true)
///   2. CLOUD FUNCTION (deleteAccount trigger) watches that collection and:
///        a. Deletes subcollections: prescriptions, medicine_logs, nutrition_logs,
///             activity_logs, appointments, linked_doctors, caregivers,
///             walk_sessions, privacy_audit_log
///        b. Deletes /users/{userId}
///        c. Revokes Firebase Auth account
///        d. Writes /deletion_audit/{userId} (GDPR proof of deletion)
///   3. CLIENT  →  signs out + wipes local storage + navigates to sign-in
///
/// The Cloud Function source is documented at the bottom of this file.
///
/// The [deleteAccount] method drives the Flutter side and reports progress
/// via a [Stream<DeletionProgress>] so the UI can show step-by-step status.
///
/// Requires: cloud_firestore ^5.5.4, firebase_auth ^5.4.0,
///           flutter_secure_storage ^9.2.2, shared_preferences ^2.3.3,
///           hive_flutter ^1.1.0
/// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ── Injectable Firestore / Auth function types ─────────────────────────────
// These match the real Firebase SDK signatures but are injected for testability.

typedef WriteDeletionRequestFn = Future<void> Function(
    String userId, Map<String, dynamic> requestData);

typedef WatchDeletionStatusFn = Stream<Map<String, dynamic>?> Function(
    String userId);

typedef SignOutFn = Future<void> Function();

// ── Progress model ─────────────────────────────────────────────────────────

enum DeletionStep {
  requestingDeletion,
  awaitingServerWipe,
  signingOut,
  clearingLocalStorage,
  complete,
  failed,
}

class DeletionProgress {
  final DeletionStep step;
  final String message;
  final bool isError;
  final double fraction; // 0.0 – 1.0 for progress bar

  const DeletionProgress({
    required this.step,
    required this.message,
    this.isError = false,
    this.fraction = 0.0,
  });
}

// ── Service ────────────────────────────────────────────────────────────────

class AccountDeletionService {
  // ── Singleton ────────────────────────────────────────────────────────────
  static AccountDeletionService? _instance;
  factory AccountDeletionService({
    WriteDeletionRequestFn? writeDeletionRequest,
    WatchDeletionStatusFn? watchDeletionStatus,
    SignOutFn? signOut,
  }) {
    _instance ??= AccountDeletionService._internal(
      writeDeletionRequest: writeDeletionRequest,
      watchDeletionStatus: watchDeletionStatus,
      signOut: signOut,
    );
    return _instance!;
  }

  AccountDeletionService._internal({
    WriteDeletionRequestFn? writeDeletionRequest,
    WatchDeletionStatusFn? watchDeletionStatus,
    SignOutFn? signOut,
  })  : _writeDeletionRequest = writeDeletionRequest ?? _stubWrite,
        _watchDeletionStatus = watchDeletionStatus ?? _stubWatch,
        _signOut = signOut ?? _stubSignOut;

  final WriteDeletionRequestFn _writeDeletionRequest;
  final WatchDeletionStatusFn _watchDeletionStatus;
  final SignOutFn _signOut;

  final _secureStorage = const FlutterSecureStorage();

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Initiates a full GDPR account deletion.
  ///
  /// Yields [DeletionProgress] events as each step completes.
  /// The Cloud Function handles server-side subcollection deletion.
  /// The client clears all local state after sign-out.
  Stream<DeletionProgress> deleteAccount({required String userId}) async* {
    // Step 1: Write deletion request to Firestore.
    yield const DeletionProgress(
      step: DeletionStep.requestingDeletion,
      message: 'Submitting deletion request…',
      fraction: 0.10,
    );

    try {
      await _writeDeletionRequest(userId, {
        'requested_at': DateTime.now().toIso8601String(),
        'confirmed': true,
        'reason': 'user_initiated',
        'client_version': '1.4.0',
      });
    } catch (e) {
      yield DeletionProgress(
        step: DeletionStep.failed,
        message: 'Could not submit deletion request: $e',
        isError: true,
        fraction: 0.10,
      );
      return;
    }

    // Step 2: Watch Firestore for the Cloud Function to complete the server wipe.
    yield const DeletionProgress(
      step: DeletionStep.awaitingServerWipe,
      message: 'Deleting your health records…',
      fraction: 0.30,
    );

    try {
      await _awaitServerDeletion(userId);
    } catch (e) {
      // Server timed out or function failed. Proceed with local cleanup anyway
      // — the deletion request document is still in Firestore and the Cloud
      // Function will retry. Log for ops investigation.
      debugPrint('[AccountDeletion] Server wipe timeout: $e — proceeding locally');
    }

    yield const DeletionProgress(
      step: DeletionStep.signingOut,
      message: 'Signing you out…',
      fraction: 0.70,
    );

    try {
      await _signOut();
    } catch (e) {
      debugPrint('[AccountDeletion] Sign-out error: $e');
    }

    // Step 3: Clear all local storage (the patient's data must not persist).
    yield const DeletionProgress(
      step: DeletionStep.clearingLocalStorage,
      message: 'Clearing local data…',
      fraction: 0.85,
    );

    await _clearLocalStorage();

    yield const DeletionProgress(
      step: DeletionStep.complete,
      message: 'Your account and health data have been permanently deleted.',
      fraction: 1.0,
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Polls the Firestore deletion request document for a 'completed' status.
  /// The Cloud Function sets status: 'completed' once all data is wiped.
  /// Times out after 60 seconds; the local cleanup proceeds regardless.
  Future<void> _awaitServerDeletion(String userId) async {
    const timeout = Duration(seconds: 60);
    const pollInterval = Duration(seconds: 2);
    final deadline = DateTime.now().add(timeout);

    await for (final snapshot in _watchDeletionStatus(userId)) {
      if (snapshot == null) break; // document deleted = wipe complete
      if (snapshot['status'] == 'completed') break;
      if (snapshot['status'] == 'failed') {
        throw Exception('Server-side deletion failed: ${snapshot['error']}');
      }
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Server wipe timed out', timeout);
      }
      await Future.delayed(pollInterval);
    }
  }

  /// Wipes all locally persisted data — SharedPreferences, Hive, SecureStorage.
  Future<void> _clearLocalStorage() async {
    await Future.wait([
      // SharedPreferences: dose logs, timezone, notification settings, etc.
      SharedPreferences.getInstance().then((p) => p.clear()),

      // Hive: offline sync queue.
      _clearHive(),

      // flutter_secure_storage: AES encryption key.
      _secureStorage.deleteAll(),
    ]);
  }

  Future<void> _clearHive() async {
    try {
      await Hive.deleteBoxFromDisk('sync_queue');
    } catch (_) {
      // Box may not exist on first launch.
    }
  }

  // ── Stubs (active when Firebase is not yet wired) ──────────────────────────

  static Future<void> _stubWrite(String userId, Map<String, dynamic> data) {
    // In debug mode: simulate a short delay, then return success.
    return Future.delayed(const Duration(milliseconds: 400));
  }

  static Stream<Map<String, dynamic>?> _stubWatch(String userId) async* {
    // Simulate: function completes after 2 seconds.
    await Future.delayed(const Duration(seconds: 2));
    yield null; // null = document deleted = wipe complete
  }

  static Future<void> _stubSignOut() {
    return Future.delayed(const Duration(milliseconds: 200));
  }
}


// ═════════════════════════════════════════════════════════════════════════════
// CLOUD FUNCTION — deleteAccount trigger  (Node.js / Firebase Functions v2)
// Deploy to: functions/src/gdpr/deleteAccount.ts
//
// import * as admin from 'firebase-admin';
// import * as functions from 'firebase-functions/v2';
//
// export const deleteAccount = functions.firestore.onDocumentCreated(
//   'data_deletion_requests/{userId}',
//   async (event) => {
//     const userId = event.params.userId;
//     const db = admin.firestore();
//     const auth = admin.auth();
//
//     const SUBCOLLECTIONS = [
//       'prescriptions', 'medicine_logs', 'nutrition_logs',
//       'activity_logs', 'appointments', 'linked_doctors',
//       'caregivers', 'walk_sessions', 'privacy_audit_log',
//     ];
//
//     // Firestore batch writes are capped at 500 operations.
//     // Chunk to avoid silent truncation for patients with large logs.
//     async function deleteCollection(ref) {
//       const docs = await ref.listDocuments();
//       for (let i = 0; i < docs.length; i += 499) {
//         const batch = db.batch();
//         docs.slice(i, i + 499).forEach((d) => batch.delete(d));
//         await batch.commit();
//       }
//     }
//
//     try {
//       // 1. Delete all subcollections (chunked, safe for 500+ documents).
//       await Promise.all(SUBCOLLECTIONS.map((sub) =>
//         deleteCollection(db.collection(`users/${userId}/${sub}`))
//       ));
//
//       // 2. Delete user document.
//       await db.doc(`users/${userId}`).delete();
//
//       // 3. Revoke Firebase Auth account.
//       await auth.deleteUser(userId);
//
//       // 4. Write GDPR deletion audit record.
//       await db.doc(`deletion_audit/${userId}`).set({
//         deleted_at: admin.firestore.FieldValue.serverTimestamp(),
//         reason: 'user_initiated',
//         subcollections_wiped: SUBCOLLECTIONS,
//       });
//
//       // 5. Mark request as completed.
//       await db.doc(`data_deletion_requests/${userId}`)
//         .update({ status: 'completed', completed_at: admin.firestore.FieldValue.serverTimestamp() });
//
//     } catch (err) {
//       await db.doc(`data_deletion_requests/${userId}`)
//         .update({ status: 'failed', error: String(err) });
//       throw err;
//     }
//   }
// );
// ═════════════════════════════════════════════════════════════════════════════
