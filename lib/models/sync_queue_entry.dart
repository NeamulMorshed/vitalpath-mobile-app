/// sync_queue_entry.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// A single queued write operation for the Offline Sync Queue.
///
/// The most critical design invariant (Blueprint §1.3 — Offline Sync Queue):
///   [originalTimestamp] is the moment the user performed the action.
///   [enqueuedAt] is when the entry was written to the local queue.
///   When the queue flushes to Firebase, [originalTimestamp] is used as the
///   document's timestamp — NEVER DateTime.now() — ensuring historical
///   accuracy regardless of how long the device was offline.
///
/// Example: A user logs a dose at 14:00 while offline. The device reconnects
/// at 16:30. The Firestore document is written with timestamp=14:00, not 16:30.
///
/// Persistence: Serialised to JSON and stored in Hive box 'sync_queue'.
/// ─────────────────────────────────────────────────────────────────────────────

// ── Vocabulary enums ──────────────────────────────────────────────────────────
enum SyncEntityType {
  prescription,
  appointment,
  medicineLog,
  nutritionLog,
  activityLog,
}

extension SyncEntityTypeX on SyncEntityType {
  String toJson() => name;
  static SyncEntityType fromJson(String v) =>
      SyncEntityType.values.firstWhere((e) => e.name == v);
}

enum SyncOperation { create, update, delete }

extension SyncOperationX on SyncOperation {
  String toJson() => name;
  static SyncOperation fromJson(String v) =>
      SyncOperation.values.firstWhere((e) => e.name == v);
}

enum SyncStatus { pending, syncing, synced, failed }

extension SyncStatusX on SyncStatus {
  String toJson() => name;
  static SyncStatus fromJson(String v) =>
      SyncStatus.values.firstWhere((e) => e.name == v,
          orElse: () => SyncStatus.pending);
}

// ── SyncQueueEntry ────────────────────────────────────────────────────────────
class SyncQueueEntry {
  /// Unique ID for this queue entry (UUID v4).
  final String entryId;

  /// Type of health entity being synced.
  final SyncEntityType entityType;

  /// The CRUD operation to perform on Firebase.
  final SyncOperation operation;

  /// The Firestore document ID of the entity. Null for new creates.
  final String? documentId;

  /// The Firestore collection path (e.g., "users/uid/prescriptions").
  final String collectionPath;

  /// The serialised entity data (JSON map). Null for delete operations.
  final Map<String, dynamic>? payload;

  /// ════════════════════════════════════════════════════════════════════════
  /// THE ORIGINAL TIMESTAMP — the moment the user performed the action.
  /// This is what gets written to Firebase as the document timestamp.
  /// It is set once at entry creation and NEVER modified.
  /// ════════════════════════════════════════════════════════════════════════
  final DateTime originalTimestamp;

  /// When this entry was added to the local queue. Used for queue ordering
  /// and staleness detection only — NOT written to Firebase.
  final DateTime enqueuedAt;

  // ── Mutable sync state ────────────────────────────────────────────────────
  SyncStatus status;
  int retryCount;
  String? lastErrorMessage;
  DateTime? lastAttemptAt;

  // ── Max retry policy ──────────────────────────────────────────────────────
  static const int maxRetries = 5;

  SyncQueueEntry({
    required this.entryId,
    required this.entityType,
    required this.operation,
    this.documentId,
    required this.collectionPath,
    this.payload,
    required this.originalTimestamp,
    required this.enqueuedAt,
    this.status = SyncStatus.pending,
    this.retryCount = 0,
    this.lastErrorMessage,
    this.lastAttemptAt,
  });

  bool get canRetry => retryCount < maxRetries;
  bool get isPending => status == SyncStatus.pending;
  bool get isFailed => status == SyncStatus.failed;

  // ── Serialisation (stored in Hive as JSON string) ─────────────────────────
  factory SyncQueueEntry.fromJson(Map<String, dynamic> json) {
    return SyncQueueEntry(
      entryId: json['entry_id'] as String,
      entityType: SyncEntityTypeX.fromJson(json['entity_type'] as String),
      operation: SyncOperationX.fromJson(json['operation'] as String),
      documentId: json['document_id'] as String?,
      collectionPath: json['collection_path'] as String,
      payload: json['payload'] as Map<String, dynamic>?,
      originalTimestamp:
          DateTime.parse(json['original_timestamp'] as String),
      enqueuedAt: DateTime.parse(json['enqueued_at'] as String),
      status: SyncStatusX.fromJson(json['status'] as String? ?? 'pending'),
      retryCount: json['retry_count'] as int? ?? 0,
      lastErrorMessage: json['last_error_message'] as String?,
      lastAttemptAt: json['last_attempt_at'] != null
          ? DateTime.parse(json['last_attempt_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'entry_id': entryId,
        'entity_type': entityType.toJson(),
        'operation': operation.toJson(),
        if (documentId != null) 'document_id': documentId,
        'collection_path': collectionPath,
        if (payload != null) 'payload': payload,
        // ── THE CRITICAL FIELD: preserves the original action time ──────────
        'original_timestamp': originalTimestamp.toIso8601String(),
        'enqueued_at': enqueuedAt.toIso8601String(),
        'status': status.toJson(),
        'retry_count': retryCount,
        if (lastErrorMessage != null) 'last_error_message': lastErrorMessage,
        if (lastAttemptAt != null)
          'last_attempt_at': lastAttemptAt!.toIso8601String(),
      };

  @override
  String toString() =>
      'SyncQueueEntry($entryId, ${entityType.name}.${operation.name}, '
      'originalTs: $originalTimestamp, status: ${status.name}, '
      'retries: $retryCount)';
}
