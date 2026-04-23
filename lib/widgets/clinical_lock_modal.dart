/// clinical_lock_modal.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// The double-confirmation bottom-sheet for Clinical Lock interactions.
///
/// Two modes (Blueprint §1.1, §3.2):
///
///   [ClinicalLockModal.explanation]
///     Shown when a PATIENT taps a disabled edit/delete button on a verified
///     record. Explains the Clinical Lock — no destructive action occurs.
///     Contains a "Contact Doctor" CTA for record amendment requests.
///
///   [ClinicalLockModal.deleteConfirm]
///     Shown when a DOCTOR (or admin) initiates deletion of a verified record.
///     Step 1: "Are you sure? This is a verified clinical record."  → Confirm
///     Step 2: Confirmation input / final irreversible delete button.
///     The two-step flow is the "double-confirmation" pattern from the blueprint.
///
/// Usage:
///   ```dart
///   await ClinicalLockModal.show(
///     context,
///     mode: ClinicalLockModalMode.explanation,
///     medicineName: prescription.medicineName,
///     doctorName: prescription.doctorName,
///   );
///   ```
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:vitalpath/widgets/verified_badge_widget.dart';

enum ClinicalLockModalMode { explanation, deleteConfirm }

class ClinicalLockModal extends StatefulWidget {
  final ClinicalLockModalMode mode;
  final String medicineName;
  final String doctorName;

  /// Called only in [deleteConfirm] mode when the user completes both steps.
  final VoidCallback? onConfirmedDelete;

  const ClinicalLockModal({
    super.key,
    required this.mode,
    required this.medicineName,
    required this.doctorName,
    this.onConfirmedDelete,
  });

  // ── Static entry point ────────────────────────────────────────────────────
  static Future<void> show(
    BuildContext context, {
    required ClinicalLockModalMode mode,
    required String medicineName,
    required String doctorName,
    VoidCallback? onConfirmedDelete,
  }) {
    HapticFeedback.mediumImpact(); // immediate 100ms tactile response
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ClinicalLockModal(
        mode: mode,
        medicineName: medicineName,
        doctorName: doctorName,
        onConfirmedDelete: onConfirmedDelete,
      ),
    );
  }

  @override
  State<ClinicalLockModal> createState() => _ClinicalLockModalState();
}

class _ClinicalLockModalState extends State<ClinicalLockModal> {
  // deleteConfirm mode state
  int _confirmStep = 1; // 1 = first warning, 2 = final confirm
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: widget.mode == ClinicalLockModalMode.explanation
            ? _buildExplanationSheet()
            : _buildDeleteConfirmSheet(),
      ),
    );
  }

  // ── Mode 1: Explanation (patient taps locked control) ────────────────────
  Widget _buildExplanationSheet() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Handle bar
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Header row
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFE6F7F4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.lock_rounded,
                color: Color(0xFF00897B),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Clinical Lock Active',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const VerifiedBadgeWidget.compact(),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Medicine info
        _InfoRow(label: 'Medicine', value: widget.medicineName),
        const SizedBox(height: 8),
        _InfoRow(label: 'Prescribed by', value: widget.doctorName),
        const SizedBox(height: 20),

        // Explanation text
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFCC02).withOpacity(0.5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 18, color: Color(0xFFF57F17)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'This prescription was pushed directly by Dr. ${widget.doctorName} '
                  'and is locked to protect your medical plan. '
                  'It cannot be edited or deleted from your device.',
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFF5D4037),
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // CTAs
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.message_rounded, size: 18),
            label: const Text('Request Change from Doctor'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00897B),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Dismiss',
              style: TextStyle(color: Color(0xFF9E9E9E)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Mode 2: Double-confirmation delete (doctor / admin path) ─────────────
  Widget _buildDeleteConfirmSheet() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: _confirmStep == 1
          ? _buildStep1(key: const ValueKey('step1'))
          : _buildStep2(key: const ValueKey('step2')),
    );
  }

  Widget _buildStep1({Key? key}) {
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHandle(),
        const SizedBox(height: 20),
        _buildDeleteHeader(
          icon: Icons.warning_amber_rounded,
          iconColor: const Color(0xFFF57C00),
          bgColor: const Color(0xFFFFF3E0),
          title: 'Delete Verified Record?',
          subtitle: 'Step 1 of 2',
        ),
        const SizedBox(height: 16),
        _InfoRow(label: 'Medicine', value: widget.medicineName),
        const SizedBox(height: 8),
        _InfoRow(label: 'Prescribed by', value: widget.doctorName),
        const SizedBox(height: 20),
        Text(
          'This is a doctor-verified clinical record. Deleting it will '
          'permanently remove it from the patient\'s medical history.',
          style: TextStyle(
              fontSize: 14, color: Colors.grey[700], height: 1.5),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => setState(() => _confirmStep = 2),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('I Understand — Continue'),
          ),
        ),
        const SizedBox(height: 10),
        _buildCancelButton(),
      ],
    );
  }

  Widget _buildStep2({Key? key}) {
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHandle(),
        const SizedBox(height: 20),
        _buildDeleteHeader(
          icon: Icons.delete_forever_rounded,
          iconColor: const Color(0xFFC62828),
          bgColor: const Color(0xFFFFEBEE),
          title: 'Confirm Permanent Deletion',
          subtitle: 'Step 2 of 2 — This cannot be undone',
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFFE53935).withOpacity(0.4)),
          ),
          child: Text(
            '"${widget.medicineName}" — prescribed by Dr. ${widget.doctorName} '
            '— will be permanently removed from the patient\'s Prescription Vault.',
            style: const TextStyle(
                fontSize: 13.5, color: Color(0xFFB71C1C), height: 1.45),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isDeleting ? null : _executeDelete,
            icon: _isDeleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.delete_forever_rounded, size: 18),
            label: Text(_isDeleting ? 'Deleting…' : 'Delete Permanently'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildCancelButton(),
      ],
    );
  }

  Future<void> _executeDelete() async {
    HapticFeedback.heavyImpact();
    setState(() => _isDeleting = true);
    try {
      widget.onConfirmedDelete?.call();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  // ── Shared sub-widgets ────────────────────────────────────────────────────
  Widget _buildHandle() => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _buildDeleteHeader({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E))),
            Text(subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ],
        ),
      ],
    );
  }

  Widget _buildCancelButton() => SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child:
              const Text('Cancel', style: TextStyle(color: Color(0xFF9E9E9E))),
        ),
      );
}

// ── Small helper widget ───────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label: ',
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF9E9E9E))),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E)),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
