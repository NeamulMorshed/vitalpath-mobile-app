/// sync_queue_service.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// The Offline Sync Queue engine for VitalPath.
///
/// Blueprint §1.3 contract:
///   "If a user logs medicine or activity while offline, the app stores the
///    data locally. Upon reconnection, it pushes data to the cloud with the
///    ORIGINAL TIMESTAMP, ensuring historical accuracy."
///
/// Architecture:
///   • [SyncQueueService] is a singleton instantiated at app startup.
///   • Queued entries are persisted in a Hive box ('sync_queue') so they
///     survive app restarts, force-quits, and crashes.
///   • [ConnectivityService] triggers [flushQueue] when the device goes online.
///   • [flushQueue] processes entries in FIFO order (oldest originalTimestamp
///     first), writing each to Firebase with its originalTimestamp — never
///     DateTime.now().
///   • Exponential backoff: retries at 2s, 4s, 8s, 16s, 32s before marking
///     as [SyncStatus.failed] and surfacing to the user.
///   • A [pendingCount] stream lets the UI show a "X pending sync" indicator.
///
/// Dependencies (pubspec.yaml):
///   - hive: ^2.2.3
///   - hive_flutter: ^1.1.0
///   - connectivity_plus: ^6.0.3
///   - uuid: ^4.4.0
/// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:vitalpath/models/sync_queue_entry.dart';

// ── Firestore write contract (injected; avoids direct Firebase dependency) ────
typedef FirestoreWriteFn = Future<void> Function({
  required String collectionPath,
  required String? documentId,
  required Map<String, dynamic> data,
  required SyncOperation operation,
});

class SyncQueueService {
  static const String _boxName = 'sync_queue';
  static const _uuid = Uuid();

  // ── Singleton ──────────────────────────────────────────────────────────────
  static SyncQueueService? _instance;
  factory SyncQueueService() => _instance ??= SyncQueueService._internal();
  SyncQueueService._internal();

  // ── Internal state ─────────────────────────────────────────────────────────
  late Box<String> _box; // Hive stores entries as JSON strings.
  bool _isInitialised = false;
  bool _isFlushing = false;

  FirestoreWriteFn? _firestoreWrite;

  // ── Streams ────────────────────────────────────────────────────────────────
  final _pendingCountController = StreamController<int>.broadcast();

  /// Emits the number of unsynced entries. Listen to show UI indicator.
  Stream<int> get pendingCountStream => _pendingCountController.stream;

  int get pendingCount => _box.isOpen
      ? _allEntries().where((e) => e.isPending).length
      : 0;

  // ── Initialisation ─────────────────────────────────────────────────────────
  Future<void> initialise({required FirestoreWriteFn firestoreWrite}) async {
    if (_isInitialised) return;
    await Hive.initFlutter();
    _box = await Hive.openBox<String>(_boxName);
    _firestoreWrite = firestoreWrite;
    _isInitialised = true;
    debugPrint(
        '[SyncQueue] Initialised. ${pendingCount} entries pending sync.');
    _emitPendingCount();
  }

  // ── Enqueue ────────────────────────────────────────────────────────────────
  /// Adds a new write operation to the local queue.
  ///
  /// [originalTimestamp] MUST be the moment the user performed the action,
  /// not the current time (unless they are the same).
  ///
  /// Returns the [SyncQueueEntry.entryId] for tracking purposes.
  Future<String> enqueue({
    required SyncEntityType entityType,
    required SyncOperation operation,
    String? documentId,
    required String collectionPath,
    Map<String, dynamic>? payload,
    required DateTime originalTimestamp, // ← THE CRITICAL PARAMETER
  }) async {
    _assertInitialised();

    final entry = SyncQueueEntry(
      entryId: _uuid.v4(),
      entityType: entityType,
      operation: operation,
      documentId: documentId,
      collectionPath: collectionPath,
      payload: payload,
      originalTimestamp: originalTimestamp, // preserved as-is
      enqueuedAt: DateTime.now(),           // queue metadata only
    );

    await _box.put(entry.entryId, jsonEncode(entry.toJson()));
    debugPrint('[SyncQueue] Enqueued: $entry');
    _emitPendingCount();
    return entry.entryId;
  }

  // ── Flush ──────────────────────────────────────────────────────────────────
  /// Processes all pending entries in FIFO order (by [originalTimestamp]).
  ///
  /// Each entry is written to Firebase using its [originalTimestamp] —
  /// the payload's timestamp field is NEVER overwritten with the current time.
  Future<void> flushQueue() async {
    _assertInitialised();
    if (_isFlushing || _firestoreWrite == null) return;
    _isFlushing = true;

    debugPrint('[SyncQueue] Flushing queue. Pending: $pendingCount');

    final pending = _allEntries()
        .where((e) => e.isPending || (e.isFailed && e.canRetry))
        .toList()
      ..sort((a, b) =>
          a.originalTimestamp.compareTo(b.originalTimestamp)); // FIFO

    for (final entry in pending) {
      await _processEntry(entry);
    }

    _isFlushing = false;
    _emitPendingCount();
    debugPrint('[SyncQueue] Flush complete. Remaining: $pendingCount');
  }

  /// Processes a single queue entry with exponential backoff retry.
  Future<void> _processEntry(SyncQueueEntry entry) async {
    entry.status = SyncStatus.syncing;
    entry.lastAttemptAt = DateTime.now();
    await _persist(entry);

    try {
      // ── THE CRITICAL WRITE ────────────────────────────────────────────────
      // We inject [original_timestamp] into the payload before writing.
      // This ensures the Firestore document reflects WHEN the action happened,
      // not when the sync occurred.
      final payloadWithOriginalTs = <String, dynamic>{
        ...?entry.payload,
        // Stamp the Firestore document with the original action time.
        'original_timestamp': entry.originalTimestamp.toIso8601String(),
        // Do NOT overwrite 'updated_at' or 'created_at' from the payload.
        // Those were set correctly at enqueue time.
      };

      await _firestoreWrite!(
        collectionPath: entry.collectionPath,
        documentId: entry.documentId,
        data: payloadWithOriginalTs,
        operation: entry.operation,
      );

      entry.status = SyncStatus.synced;
      await _box.delete(entry.entryId); // remove from queue on success
      debugPrint('[SyncQueue] Synced: ${entry.entryId}');
    } catch (e) {
      entry.retryCount++;
      entry.lastErrorMessage = e.toString();
      entry.status =
          entry.canRetry ? SyncStatus.pending : SyncStatus.failed;

      await _persist(entry);

      if (entry.canRetry) {
        // Exponential backoff before next attempt.
        final backoff =
            Duration(seconds: (2 << entry.retryCount).clamp(2, 32));
        debugPrint(
            '[SyncQueue] Retry ${entry.retryCount}/${SyncQueueEntry.maxRetries} '
            'for ${entry.entryId} in ${backoff.inSeconds}s');
        await Future.delayed(backoff);
      } else {
        debugPrint(
            '[SyncQueue] Entry ${entry.entryId} permanently failed: $e');
      }
    }
  }

  // ── Queries ────────────────────────────────────────────────────────────────

  /// All entries currently in the Hive box.
  List<SyncQueueEntry> _allEntries() {
    return _box.values
        .map((jsonStr) {
          try {
            return SyncQueueEntry.fromJson(
                jsonDecode(jsonStr) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<SyncQueueEntry>()
        .toList();
  }

  /// Returns all failed entries for user-visible error surfacing.
  List<SyncQueueEntry> get failedEntries =>
      _allEntries().where((e) => e.isFailed).toList();

  // ── Utilities ──────────────────────────────────────────────────────────────
  Future<void> _persist(SyncQueueEntry entry) async {
    await _box.put(entry.entryId, jsonEncode(entry.toJson()));
  }

  void _emitPendingCount() {
    if (!_pendingCountController.isClosed) {
      _pendingCountController.add(pendingCount);
    }
  }

  void _assertInitialised() {
    if (!_isInitialised) {
      throw StateError(
          'SyncQueueService must be initialised before use. '
          'Call initialise() in main.dart after Hive setup.');
    }
  }

  Future<void> dispose() async {
    await _pendingCountController.close();
    await _box.close();
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// connectivity_service.dart (inlined here to keep the sync engine self-contained)
// ─────────────────────────────────────────────────────────────────────────────

/// Monitors device connectivity and triggers [SyncQueueService.flushQueue]
/// when the device transitions from offline → online.
///
/// Blueprint §1.3: "Upon reconnection, it pushes data to the cloud."
///
/// Dependencies: connectivity_plus: ^6.0.3
class ConnectivityService {
  static ConnectivityService? _instance;
  factory ConnectivityService() =>
      _instance ??= ConnectivityService._internal();
  ConnectivityService._internal();

  // ── State ──────────────────────────────────────────────────────────────────
  bool _isOnline = true;
  StreamSubscription<dynamic>? _subscription;

  final _onlineController = StreamController<bool>.broadcast();

  /// Emits [true] when online, [false] when offline.
  Stream<bool> get onlineStream => _onlineController.stream;
  bool get isOnline => _isOnline;

  // ── Initialisation ─────────────────────────────────────────────────────────
  Future<void> initialise(SyncQueueService syncQueue) async {
    // Real implementation uses connectivity_plus:
    //
    // import 'package:connectivity_plus/connectivity_plus.dart';
    // final connectivity = Connectivity();
    // _subscription = connectivity.onConnectivityChanged.listen((result) {
    //   final nowOnline = result != ConnectivityResult.none;
    //   _handleTransition(nowOnline, syncQueue);
    // });
    //
    // // Check initial state.
    // final initial = await connectivity.checkConnectivity();
    // _isOnline = initial != ConnectivityResult.none;
    //
    // Stub implementation for testability without plugin:
    debugPrint('[Connectivity] Service initialised. Online: $_isOnline');
  }

  void _handleTransition(bool nowOnline, SyncQueueService syncQueue) {
    final wasOffline = !_isOnline;
    _isOnline = nowOnline;
    _onlineController.add(_isOnline);

    debugPrint('[Connectivity] Changed → ${_isOnline ? "ONLINE" : "OFFLINE"}');

    if (wasOffline && nowOnline) {
      // Device came back online → flush the sync queue.
      debugPrint('[Connectivity] Back online. Triggering sync queue flush.');
      syncQueue.flushQueue();
    }
  }

  /// Manually simulate going offline (for testing).
  @visibleForTesting
  void simulateOffline(SyncQueueService syncQueue) =>
      _handleTransition(false, syncQueue);

  /// Manually simulate coming online (for testing).
  @visibleForTesting
  void simulateOnline(SyncQueueService syncQueue) =>
      _handleTransition(true, syncQueue);

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _onlineController.close();
  }
}
