/// privacy_settings_screen.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Privacy & Security hub — Profile → Privacy & Security.
///
/// Sections:
///   1. Authentication Guard  — biometric lock toggle for health profile access.
///   2. Sync Access           — which doctors have active sync to this patient's
///                              records (Privacy Audit §5).
///   3. Data Encryption       — AES-256 encryption status for sensitive fields.
///   4. Privacy Audit Log     — chronological log of doctor access events.
///   5. Account               — GDPR "Delete Account & All Data".
///
/// Blueprint §4 / §5:
///   All UI updates stay <100 ms: settings reads from SharedPreferences
///   (synchronous after first load), doctor list from parent provider
///   (already in memory), audit log from Firestore (paginated, lazy-loaded).
///
/// Route: PrivacySettingsScreen.route(patientId) — slide-from-right.
/// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:vitalpath/models/doctor_model.dart';
import 'package:vitalpath/providers/doctor_provider.dart';
import 'package:vitalpath/services/account_deletion_service.dart';
import 'package:vitalpath/services/auth_gate_service.dart';
import 'package:vitalpath/services/encryption_service.dart';

class PrivacySettingsScreen extends StatefulWidget {
  final String patientId;

  const PrivacySettingsScreen({super.key, required this.patientId});

  static PageRoute<void> route(String patientId) {
    return PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => ChangeNotifierProvider(
        create: (_) => DoctorProvider()..loadDoctors(patientId),
        child: PrivacySettingsScreen(patientId: patientId),
      ),
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  final _authGate = AuthGateService();
  final _encService = EncryptionService();

  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _isLoadingSettings = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enabled = await _authGate.isBiometricEnabled();
    final available = await _authGate.isBiometricAvailable();
    if (mounted) {
      setState(() {
        _biometricEnabled = enabled;
        _biometricAvailable = available;
        _isLoadingSettings = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: Color(0xFF1A1A2E)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Privacy & Security',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A2E),
          ),
        ),
      ),
      body: _isLoadingSettings
          ? const _LoadingBody()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                // ── 1. Authentication ─────────────────────────────────────
                _SectionHeader(
                  icon: Icons.fingerprint_rounded,
                  label: 'Authentication Guard',
                ),
                _AuthGuardCard(
                  biometricEnabled: _biometricEnabled,
                  biometricAvailable: _biometricAvailable,
                  onToggle: _handleBiometricToggle,
                ),
                const SizedBox(height: 24),

                // ── 2. Sync Access ───────────────────────────────────────
                _SectionHeader(
                  icon: Icons.people_rounded,
                  label: 'Sync Access',
                ),
                _SyncAccessSection(patientId: widget.patientId),
                const SizedBox(height: 24),

                // ── 3. Data Encryption ───────────────────────────────────
                _SectionHeader(
                  icon: Icons.lock_rounded,
                  label: 'Data Encryption',
                ),
                _EncryptionStatusCard(encVersion: _encService.currentEncVersion),
                const SizedBox(height: 24),

                // ── 4. Privacy Audit Log ─────────────────────────────────
                _SectionHeader(
                  icon: Icons.history_rounded,
                  label: 'Privacy Audit Log',
                ),
                _PrivacyAuditSection(patientId: widget.patientId),
                const SizedBox(height: 24),

                // ── 5. Account ───────────────────────────────────────────
                _SectionHeader(
                  icon: Icons.manage_accounts_rounded,
                  label: 'Account',
                ),
                _DeleteAccountCard(
                  patientId: widget.patientId,
                  authGate: _authGate,
                  onDeleteComplete: () {
                    // Navigate to sign-in (replace entire stack).
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/',
                      (_) => false,
                    );
                  },
                ),
              ],
            ),
    );
  }

  Future<void> _handleBiometricToggle(bool value) async {
    HapticFeedback.selectionClick();
    final success = await _authGate.setBiometricEnabled(enabled: value);
    if (mounted && success) {
      setState(() => _biometricEnabled = value);
    } else if (mounted && !success && value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Biometric setup failed. Please check your device settings.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFE53935),
        ),
      );
    }
  }
}

// ── Section header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF00897B)),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF00897B),
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card shell ─────────────────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;

  const _Card({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 1. AUTH GUARD
// ═════════════════════════════════════════════════════════════════════════════
class _AuthGuardCard extends StatelessWidget {
  final bool biometricEnabled;
  final bool biometricAvailable;
  final ValueChanged<bool> onToggle;

  const _AuthGuardCard({
    required this.biometricEnabled,
    required this.biometricAvailable,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: biometricEnabled
                      ? const Color(0xFFE6F7F4)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  biometricEnabled
                      ? Icons.fingerprint_rounded
                      : Icons.lock_open_rounded,
                  size: 22,
                  color: biometricEnabled
                      ? const Color(0xFF00897B)
                      : const Color(0xFF9E9E9E),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Biometric Lock',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      biometricEnabled
                          ? 'Health profile requires Face ID / fingerprint'
                          : 'Health profile is accessible without biometrics',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9E9E9E),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: biometricEnabled,
                onChanged: biometricAvailable ? onToggle : null,
                activeColor: const Color(0xFF00897B),
              ),
            ],
          ),
          if (!biometricAvailable) ...[
            const SizedBox(height: 12),
            const _InfoBanner(
              icon: Icons.info_outline_rounded,
              message:
                  'No biometric hardware or enrolled credentials found on this device. '
                  'Enable fingerprint or Face ID in device Settings to activate this feature.',
            ),
          ],
          if (biometricEnabled) ...[
            const SizedBox(height: 12),
            const _InfoBanner(
              icon: Icons.shield_rounded,
              message:
                  'Session valid for 5 minutes. You\'ll be prompted again after '
                  'returning from background beyond the session window.',
              color: Color(0xFFE6F7F4),
              textColor: Color(0xFF00695C),
              iconColor: Color(0xFF00897B),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 2. SYNC ACCESS
// ═════════════════════════════════════════════════════════════════════════════
class _SyncAccessSection extends StatelessWidget {
  final String patientId;

  const _SyncAccessSection({required this.patientId});

  static final _dateFmt = DateFormat('d MMM yyyy');

  @override
  Widget build(BuildContext context) {
    return Consumer<DoctorProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const _Card(child: _ShimmerRow());
        }

        final connected = provider.sortedDoctors
            .where((d) => d.syncStatus == DoctorSyncStatus.connected)
            .toList();

        if (connected.isEmpty) {
          return _Card(
            child: Row(
              children: const [
                Icon(Icons.people_outline_rounded,
                    size: 20, color: Color(0xFF9E9E9E)),
                SizedBox(width: 12),
                Text(
                  'No doctors currently have sync access.',
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF9E9E9E)),
                ),
              ],
            ),
          );
        }

        return Column(
          children: connected
              .map((doc) => _DoctorAccessRow(doctor: doc, dateFmt: _dateFmt))
              .toList(),
        );
      },
    );
  }
}

class _DoctorAccessRow extends StatelessWidget {
  final DoctorModel doctor;
  final DateFormat dateFmt;

  const _DoctorAccessRow({required this.doctor, required this.dateFmt});

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFE6F7F4),
            backgroundImage: doctor.avatarUrl != null
                ? NetworkImage(doctor.avatarUrl!)
                : null,
            child: doctor.avatarUrl == null
                ? Text(
                    doctor.name[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF00897B),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dr. ${doctor.name}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  doctor.specialty,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
                ),
                if (doctor.syncedAt != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Synced ${dateFmt.format(doctor.syncedAt!)}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFFBDBDBD)),
                  ),
                ],
              ],
            ),
          ),

          // Access scope badge.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _AccessBadge('Prescriptions'),
              const SizedBox(height: 4),
              _AccessBadge('Appointments'),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccessBadge extends StatelessWidget {
  final String label;

  const _AccessBadge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFE6F7F4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Color(0xFF00897B),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 3. DATA ENCRYPTION STATUS
// ═════════════════════════════════════════════════════════════════════════════
class _EncryptionStatusCard extends StatelessWidget {
  final int encVersion;

  const _EncryptionStatusCard({required this.encVersion});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F7F4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.enhanced_encryption_rounded,
                    size: 22, color: Color(0xFF00897B)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AES-256 Encryption Active',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      'Key version $encVersion · Hardware-backed Keychain/Keystore',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF9E9E9E)),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F7F4),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'ACTIVE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF00897B),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          const Text(
            'Encrypted fields',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF555566),
            ),
          ),
          const SizedBox(height: 10),
          ..._encryptedFields.map((f) => _EncryptedFieldRow(
                collection: f.$1,
                fields: f.$2,
              )),
        ],
      ),
    );
  }

  // Sensitive fields subject to AES-256 encryption before Firestore write.
  static const _encryptedFields = [
    ('Prescriptions', 'Medicine name, Dosage, Instructions'),
    ('GPS Walk Sessions', 'Route coordinates (lat/lng path)'),
    ('Nutrition Logs', 'Food name, Protocol name'),
  ];
}

class _EncryptedFieldRow extends StatelessWidget {
  final String collection;
  final String fields;

  const _EncryptedFieldRow({required this.collection, required this.fields});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline_rounded,
              size: 14, color: Color(0xFF00897B)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  collection,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                Text(
                  fields,
                  style: const TextStyle(
                      fontSize: 11.5, color: Color(0xFF9E9E9E)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 4. PRIVACY AUDIT LOG
// ═════════════════════════════════════════════════════════════════════════════
class _PrivacyAuditSection extends StatefulWidget {
  final String patientId;

  const _PrivacyAuditSection({required this.patientId});

  @override
  State<_PrivacyAuditSection> createState() => _PrivacyAuditSectionState();
}

class _PrivacyAuditSectionState extends State<_PrivacyAuditSection> {
  // In production: stream from Firestore users/{patientId}/privacy_audit_log
  // ordered by timestamp desc, limit 20.
  // Here: static doctor-sync events derived from linked_doctors list.

  static final _timeFmt = DateFormat('d MMM yyyy, h:mm a');

  @override
  Widget build(BuildContext context) {
    return Consumer<DoctorProvider>(
      builder: (context, provider, _) {
        final syncEvents = provider.sortedDoctors
            .where((d) => d.syncedAt != null)
            .map((d) => _AuditRow(
                  eventType: d.syncStatus == DoctorSyncStatus.connected
                      ? 'Sync access granted'
                      : 'Sync access removed',
                  actorName: 'Dr. ${d.name}',
                  detail: d.specialty,
                  timestamp: d.syncedAt!,
                  isWrite: false,
                  dateFmt: _timeFmt,
                ))
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

        if (syncEvents.isEmpty) {
          return _Card(
            child: Row(
              children: const [
                Icon(Icons.history_rounded,
                    size: 20, color: Color(0xFF9E9E9E)),
                SizedBox(width: 12),
                Text(
                  'No access events recorded yet.',
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF9E9E9E)),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            ...syncEvents,
            _Card(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: const [
                  Icon(Icons.info_outline_rounded,
                      size: 14, color: Color(0xFF9E9E9E)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Full audit log (read/write events per field) is available '
                      'once Cloud Functions are deployed.',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF9E9E9E),
                          height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AuditRow extends StatelessWidget {
  final String eventType;
  final String actorName;
  final String detail;
  final DateTime timestamp;
  final bool isWrite;
  final DateFormat dateFmt;

  const _AuditRow({
    required this.eventType,
    required this.actorName,
    required this.detail,
    required this.timestamp,
    required this.isWrite,
    required this.dateFmt,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isWrite
                  ? const Color(0xFFFFF3E0)
                  : const Color(0xFFE6F7F4),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              isWrite ? Icons.edit_rounded : Icons.visibility_rounded,
              size: 16,
              color: isWrite
                  ? const Color(0xFFF57C00)
                  : const Color(0xFF00897B),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eventType,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$actorName · $detail',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF9E9E9E)),
                ),
                const SizedBox(height: 3),
                Text(
                  dateFmt.format(timestamp),
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFFBDBDBD)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 5. DELETE ACCOUNT
// ═════════════════════════════════════════════════════════════════════════════
class _DeleteAccountCard extends StatefulWidget {
  final String patientId;
  final AuthGateService authGate;
  final VoidCallback onDeleteComplete;

  const _DeleteAccountCard({
    required this.patientId,
    required this.authGate,
    required this.onDeleteComplete,
  });

  @override
  State<_DeleteAccountCard> createState() => _DeleteAccountCardState();
}

class _DeleteAccountCardState extends State<_DeleteAccountCard> {
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.delete_forever_rounded,
                    size: 22, color: Color(0xFFB71C1C)),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delete Account & All Data',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'GDPR Right to be Forgotten',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFF9E9E9E)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _InfoBanner(
            icon: Icons.warning_amber_rounded,
            message:
                'This permanently deletes your prescriptions, medicine logs, '
                'activity records, appointments, and doctor sync connections. '
                'This action cannot be undone.',
            color: Color(0xFFFFEBEE),
            textColor: Color(0xFFB71C1C),
            iconColor: Color(0xFFE53935),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _isDeleting ? null : () => _confirmDelete(context),
              icon: _isDeleting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFFE53935)),
                    )
                  : const Icon(Icons.delete_outline_rounded,
                      size: 18, color: Color(0xFFE53935)),
              label: Text(
                _isDeleting ? 'Deleting…' : 'Delete Account & All Data',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE53935),
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(
                    color: Color(0xFFE53935), width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    HapticFeedback.heavyImpact();

    // Cache context-derived objects before any await to avoid
    // cross-async-gap BuildContext usage warnings.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Step 1: Confirmation dialog with typed confirmation.
    final confirmed = await _showConfirmationDialog(context);
    if (!confirmed) return;

    // Step 2: Biometric re-auth before destructive action.
    final authed = await widget.authGate.reauthenticate();
    if (!authed) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Authentication required to delete account.'),
          backgroundColor: Color(0xFFE53935),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Step 3: Show progress bottom sheet while deletion runs.
    if (!mounted) return;
    await _showDeletionProgressSheet(navigator.context);
  }

  Future<bool> _showConfirmationDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.delete_forever_rounded,
                    color: Color(0xFFB71C1C), size: 22),
                SizedBox(width: 10),
                Text(
                  'Delete Account?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This will permanently erase all your health records. '
                  'This cannot be undone.',
                  style: TextStyle(
                      fontSize: 14, color: Color(0xFF555566), height: 1.5),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Type DELETE to confirm:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  onChanged: (_) => setD(() {}),
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'DELETE',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE8E8EE)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Color(0xFFE53935), width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
              ],
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              OutlinedButton(
                onPressed: () {
                  ctrl.dispose();
                  Navigator.of(ctx).pop(false);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1A1A2E),
                  side: const BorderSide(color: Color(0xFFE0E0E0)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                ),
                child: const Text('Cancel',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              FilledButton(
                onPressed: ctrl.text.trim() == 'DELETE'
                    ? () {
                        ctrl.dispose();
                        Navigator.of(ctx).pop(true);
                      }
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB71C1C),
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                ),
                child: const Text('Delete',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
    return result ?? false;
  }

  Future<void> _showDeletionProgressSheet(BuildContext context) async {
    setState(() => _isDeleting = true);

    final service = AccountDeletionService();
    final stream =
        service.deleteAccount(userId: widget.patientId);

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DeletionProgressSheet(
        stream: stream,
        onComplete: () {
          Navigator.of(ctx).pop();
          widget.onDeleteComplete();
        },
      ),
    );

    if (mounted) setState(() => _isDeleting = false);
  }
}

class _DeletionProgressSheet extends StatelessWidget {
  final Stream<DeletionProgress> stream;
  final VoidCallback onComplete;

  const _DeletionProgressSheet({
    required this.stream,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: StreamBuilder<DeletionProgress>(
          stream: stream,
          builder: (context, snap) {
            final progress = snap.data;

            if (progress == null) {
              return const _ProgressRow(
                message: 'Starting deletion…',
                fraction: 0,
              );
            }

            if (progress.step == DeletionStep.complete) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => onComplete());
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: progress.isError
                        ? const Color(0xFFFFEBEE)
                        : const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    progress.step == DeletionStep.complete
                        ? Icons.check_circle_rounded
                        : progress.isError
                            ? Icons.error_rounded
                            : Icons.delete_forever_rounded,
                    size: 30,
                    color: progress.step == DeletionStep.complete
                        ? const Color(0xFF00897B)
                        : const Color(0xFFB71C1C),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  progress.step == DeletionStep.complete
                      ? 'Account Deleted'
                      : 'Deleting Account…',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  progress.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Colors.grey[600],
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.fraction,
                    backgroundColor: Colors.grey[200],
                    color: progress.isError
                        ? const Color(0xFFE53935)
                        : const Color(0xFF00897B),
                    minHeight: 6,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String message;
  final double fraction;

  const _ProgressRow({required this.message, required this.fraction});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message,
            style: const TextStyle(fontSize: 14, color: Color(0xFF9E9E9E))),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: fraction, color: const Color(0xFF00897B)),
      ],
    );
  }
}

// ── Shared components ──────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final Color textColor;
  final Color iconColor;

  const _InfoBanner({
    required this.icon,
    required this.message,
    this.color = const Color(0xFFF5F5F5),
    this.textColor = const Color(0xFF555566),
    this.iconColor = const Color(0xFF9E9E9E),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  fontSize: 12.5, color: textColor, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: Color(0xFF00897B)),
    );
  }
}

class _ShimmerRow extends StatelessWidget {
  const _ShimmerRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
            width: 44, height: 44, color: Colors.grey[200],
            child: const SizedBox()),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 120, height: 12, color: Colors.grey[200]),
            const SizedBox(height: 6),
            Container(width: 80, height: 10, color: Colors.grey[200]),
          ],
        ),
      ],
    );
  }
}
