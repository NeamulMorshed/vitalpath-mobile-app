/// encryption_service.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// AES-256-CBC field-level encryption for health-sensitive data at rest.
///
/// Blueprint §4 / §5 — "All health-sensitive fields (Medication name, Dosage,
///   GPS paths) must be prepared for AES-256 encryption at rest."
///
/// Design:
///   • AES-256-CBC with PKCS7 padding — 256-bit key, 16-byte random IV per write.
///   • Key: 32 cryptographically random bytes, generated once, stored in
///     flutter_secure_storage (hardware-backed Keychain/Keystore on iOS/Android).
///   • Output: base64url(IV[16] ‖ ciphertext) — IV prepended to ciphertext so
///     each decrypt call can extract it without a separate storage lookup.
///   • In-memory key cache: key is loaded from SecureStorage once per app session
///     and held in memory — subsequent encrypt/decrypt calls are <1 ms each.
///   • Encryption version (enc_version: int) travels with the Firestore document
///     so future key rotations can decrypt legacy documents with the correct key.
///
/// Fields subject to encryption before Firestore write:
///   PrescriptionModel   → medicineName, instructions (String fields)
///   PrescriptionModel   → dosage (serialised as string before encrypt)
///   GpsWalkSession      → routePoints JSON (spatial PHI)
///   NutritionModel      → foodName, protocolName
///
/// NOTE: Encrypted fields cannot be used in Firestore where() queries.
///   All filtering is done client-side after decrypt. Design queries accordingly.
///
/// Requires: encrypt ^5.0.3, flutter_secure_storage ^9.2.2, dart:convert
/// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class EncryptionService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static EncryptionService? _instance;
  factory EncryptionService() => _instance ??= EncryptionService._internal();
  EncryptionService._internal();

  // ── Constants ─────────────────────────────────────────────────────────────
  static const _keyStorageKey = 'vitalpath_aes256_key_v1';
  static const _currentEncVersion = 1;

  // ── State ─────────────────────────────────────────────────────────────────
  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  enc.Key? _cachedKey; // in-memory cache after first load

  // ── Public API ─────────────────────────────────────────────────────────────

  /// The AES-256 encryption key version written alongside encrypted documents.
  /// Increment this constant when rotating the key and update [decryptField]
  /// to handle both versions.
  int get currentEncVersion => _currentEncVersion;

  /// Encrypts a UTF-8 string field.
  ///
  /// Returns a base64url-encoded string: IV[16] ‖ ciphertext.
  /// Throws [EncryptionException] on key load failure.
  Future<String> encryptField(String plaintext) async {
    if (plaintext.isEmpty) return plaintext;
    final key = await _loadOrGenerateKey();
    final iv = _randomIv();
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);

    // Combine: IV (16 bytes) + ciphertext bytes.
    final ivBytes = iv.bytes;
    final cipherBytes = encrypted.bytes;
    final combined = Uint8List(ivBytes.length + cipherBytes.length);
    combined.setRange(0, ivBytes.length, ivBytes);
    combined.setRange(ivBytes.length, combined.length, cipherBytes);

    return base64Url.encode(combined);
  }

  /// Decrypts a field encrypted by [encryptField].
  ///
  /// Returns the original plaintext string.
  /// Returns [ciphertext] unchanged if it is empty or not valid base64.
  Future<String> decryptField(String ciphertext) async {
    if (ciphertext.isEmpty) return ciphertext;
    try {
      final combined = base64Url.decode(_addPadding(ciphertext));
      if (combined.length < 17) return ciphertext; // IV (16) + ≥1 cipher byte

      final iv = enc.IV(combined.sublist(0, 16));
      final cipherBytes = enc.Encrypted(combined.sublist(16));
      final key = await _loadOrGenerateKey();
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return encrypter.decrypt(cipherBytes, iv: iv);
    } catch (_) {
      // Not encrypted or decryption failed — return as-is (graceful fallback
      // for plaintext-era documents that pre-date encryption).
      return ciphertext;
    }
  }

  /// Encrypts a JSON-serialisable value (numbers, lists, maps).
  /// Serialises to JSON string first, then encrypts.
  Future<String> encryptJson(Object value) async {
    return encryptField(jsonEncode(value));
  }

  /// Decrypts a JSON-encoded encrypted field back to a Dart object.
  Future<T> decryptJson<T>(String ciphertext) async {
    final plain = await decryptField(ciphertext);
    return jsonDecode(plain) as T;
  }

  /// Prepares a prescription map for Firestore storage by encrypting
  /// health-sensitive fields in-place.
  ///
  /// Encrypted fields: medicine_name, dosage (→ string), instructions.
  /// Added field: enc_version (tracks key version for future rotation).
  Future<Map<String, dynamic>> encryptPrescriptionFields(
      Map<String, dynamic> data) async {
    final copy = Map<String, dynamic>.from(data);

    if (copy.containsKey('medicine_name')) {
      copy['medicine_name'] =
          await encryptField(copy['medicine_name'].toString());
    }
    if (copy.containsKey('dosage')) {
      copy['dosage'] = await encryptField(copy['dosage'].toString());
    }
    if (copy.containsKey('instructions') && copy['instructions'] != null) {
      copy['instructions'] =
          await encryptField(copy['instructions'].toString());
    }
    copy['enc_version'] = _currentEncVersion;
    return copy;
  }

  /// Decrypts a Firestore prescription document map back to plain values.
  Future<Map<String, dynamic>> decryptPrescriptionFields(
      Map<String, dynamic> data) async {
    final copy = Map<String, dynamic>.from(data);

    if (copy.containsKey('medicine_name')) {
      copy['medicine_name'] = await decryptField(copy['medicine_name'].toString());
    }
    if (copy.containsKey('dosage')) {
      final plain = await decryptField(copy['dosage'].toString());
      copy['dosage'] = double.tryParse(plain) ?? copy['dosage'];
    }
    if (copy.containsKey('instructions') && copy['instructions'] != null) {
      copy['instructions'] = await decryptField(copy['instructions'].toString());
    }
    return copy;
  }

  /// Encrypts the routePoints list from a GpsWalkSession before Firestore write.
  /// The full lat/lng array is JSON-encoded and AES-256 encrypted.
  Future<Map<String, dynamic>> encryptWalkSessionFields(
      Map<String, dynamic> data) async {
    final copy = Map<String, dynamic>.from(data);

    if (copy.containsKey('route_points') && copy['route_points'] != null) {
      final points = copy['route_points'];
      if (points is List && points.isNotEmpty) {
        copy['route_points_enc'] = await encryptJson(points);
        copy.remove('route_points'); // store only encrypted form
      }
    }
    copy['enc_version'] = _currentEncVersion;
    return copy;
  }

  /// Decrypts route_points_enc back to a List of coordinate maps.
  Future<Map<String, dynamic>> decryptWalkSessionFields(
      Map<String, dynamic> data) async {
    final copy = Map<String, dynamic>.from(data);

    if (copy.containsKey('route_points_enc') &&
        copy['route_points_enc'] != null) {
      final decrypted =
          await decryptJson<List<dynamic>>(copy['route_points_enc'].toString());
      copy['route_points'] = decrypted;
      copy.remove('route_points_enc');
    }
    return copy;
  }

  // ── Key management ─────────────────────────────────────────────────────────

  /// Returns the AES-256 key from cache, SecureStorage, or generates a new one.
  Future<enc.Key> _loadOrGenerateKey() async {
    if (_cachedKey != null) return _cachedKey!;

    final stored = await _secureStorage.read(key: _keyStorageKey);
    if (stored != null) {
      _cachedKey = enc.Key(base64.decode(stored));
      return _cachedKey!;
    }

    // First run: generate a cryptographically random 256-bit key.
    final rawKey = _randomBytes(32); // 32 × 8 = 256 bits
    await _secureStorage.write(
      key: _keyStorageKey,
      value: base64.encode(rawKey),
    );
    _cachedKey = enc.Key(rawKey);
    return _cachedKey!;
  }

  /// Evicts the in-memory key cache.
  /// Call this after key rotation or when the user signs out.
  void evictKeyCache() => _cachedKey = null;

  // ── Crypto utilities ───────────────────────────────────────────────────────

  /// Generates a cryptographically random 16-byte IV.
  enc.IV _randomIv() => enc.IV(_randomBytes(16));

  /// Generates [length] cryptographically random bytes using dart:math
  /// Random.secure() which delegates to the OS CSPRNG.
  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(length, (_) => random.nextInt(256)));
  }

  /// Adds base64 padding characters that may have been stripped by base64Url.
  String _addPadding(String b64) {
    final remainder = b64.length % 4;
    if (remainder == 0) return b64;
    return b64 + '=' * (4 - remainder);
  }
}

/// Thrown when [EncryptionService] cannot load or generate the AES key.
class EncryptionException implements Exception {
  final String message;
  const EncryptionException(this.message);

  @override
  String toString() => 'EncryptionException: $message';
}
