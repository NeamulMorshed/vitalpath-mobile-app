/// prescription_card_widget.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// The primary list card for Prescription Vault and Care screen entries.
///
/// Governance UI contract (Blueprint §1.1 & §3.2):
///
///   is_verified == TRUE  ("Physician Verified" path):
///     • VerifiedBadge displayed prominently.
///     • Edit icon: visually disabled (greyed, opacity 0.35), tap triggers
///       ClinicalLockModal.explanation bottom-sheet.
///     • Delete icon: replaced with a locked-padlock icon; tap triggers
///       ClinicalLockModal.explanation (patient) or deleteConfirm (doctor).
///     • Card has a subtle left-border accent in clinical-teal.
///     • No InkWell ripple on disabled controls — prevents false affordance.
///
///   is_verified == FALSE ("Patient Managed" path):
///     • Full CRUD: edit opens AddPrescriptionBottomSheet pre-filled,
///       delete shows a single standard AlertDialog confirmation.
///     • Card border is neutral grey.
///
/// Performance (Antigravity §4):
///   • `const` constructor — no rebuild overhead at rest.
///   • Wrapped in [RepaintBoundary] — card repaints don't propagate upward.
///   • All icons & badges are `const` — zero allocations on list scroll.
///   • [HapticFeedback.lightImpact()] fires synchronously on tap for <100ms
///     tactile response.
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:vitalpath/models/prescription_model.dart';
import 'package:vitalpath/widgets/clinical_lock_modal.dart';
import 'package:vitalpath/widgets/verified_badge_widget.dart';

// ── Public callback typedefs ──────────────────────────────────────────────────
typedef OnEditPressed = void Function(PrescriptionModel prescription);
typedef OnDeleteConfirmed = void Function(String prescriptionId);

class PrescriptionCardWidget extends StatelessWidget {
  final PrescriptionModel prescription;
  final OnEditPressed? onEdit;
  final OnDeleteConfirmed? onDelete;

  /// When true, the delete path uses [ClinicalLockModal.deleteConfirm]
  /// (doctor / admin view). When false, deletion is blocked with the
  /// explanation sheet (default patient view).
  final bool callerIsDoctor;

  const PrescriptionCardWidget({
    super.key,
    required this.prescription,
    this.onEdit,
    this.onDelete,
    this.callerIsDoctor = false,
  });

  // ── Colour constants ──────────────────────────────────────────────────────
  static const Color _verifiedAccent = Color(0xFF00897B);
  static const Color _unverifiedAccent = Color(0xFFE0E0E0);
  static const Color _disabledColor = Color(0xFFBDBDBD);
  static const Color _deleteColor = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary isolates this card's repaint layer.
    return RepaintBoundary(
      child: prescription.isVerified
          ? _buildVerifiedCard(context)
          : _buildPatientManagedCard(context),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // VERIFIED PATH
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildVerifiedCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: const BorderSide(color: _verifiedAccent, width: 4),
          top: BorderSide(color: Colors.grey[200]!, width: 1),
          right: BorderSide(color: Colors.grey[200]!, width: 1),
          bottom: BorderSide(color: Colors.grey[200]!, width: 1),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A00897B),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Medicine icon ────────────────────────────────────────
                _MedicineIcon(isVerified: true),
                const SizedBox(width: 12),

                // ── Text content ─────────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Medicine name + badge
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              prescription.medicineName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A1A2E),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const VerifiedBadgeWidget.compact(),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Dosage
                      _DosageChip(
                        dosage: prescription.dosage,
                        unit: prescription.unit,
                      ),
                      const SizedBox(height: 6),

                      // Doctor name
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline_rounded,
                            size: 13,
                            color: Color(0xFF9E9E9E),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Dr. ${prescription.doctorName}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF666680),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),

                      // Date range
                      _DateRange(
                        startDate: prescription.startDate,
                        endDate: prescription.endDate,
                      ),
                    ],
                  ),
                ),

                // ── Disabled action buttons (verified path) ───────────────
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Edit — disabled, tap shows explanation modal.
                    _GovernanceActionButton(
                      icon: Icons.edit_outlined,
                      isEnabled: false,
                      onTap: () => ClinicalLockModal.show(
                        context,
                        mode: ClinicalLockModalMode.explanation,
                        medicineName: prescription.medicineName,
                        doctorName: prescription.doctorName,
                      ),
                      tooltip: 'Locked by doctor',
                    ),
                    const SizedBox(height: 8),
                    // Delete — locked icon, tap shows explanation or confirm.
                    _GovernanceActionButton(
                      icon: Icons.lock_outline_rounded,
                      isEnabled: false,
                      onTap: () => _handleVerifiedDeleteTap(context),
                      tooltip: callerIsDoctor
                          ? 'Delete verified record'
                          : 'Locked by doctor',
                      color: callerIsDoctor ? _deleteColor : _disabledColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleVerifiedDeleteTap(BuildContext context) {
    if (callerIsDoctor) {
      // Doctor path: double-confirmation modal.
      ClinicalLockModal.show(
        context,
        mode: ClinicalLockModalMode.deleteConfirm,
        medicineName: prescription.medicineName,
        doctorName: prescription.doctorName,
        onConfirmedDelete: () => onDelete?.call(prescription.id!),
      );
    } else {
      // Patient path: explanation only — no delete possible.
      ClinicalLockModal.show(
        context,
        mode: ClinicalLockModalMode.explanation,
        medicineName: prescription.medicineName,
        doctorName: prescription.doctorName,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PATIENT-MANAGED PATH
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildPatientManagedCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => HapticFeedback.lightImpact(),
            splashColor: const Color(0xFF00897B).withOpacity(0.06),
            highlightColor: const Color(0xFF00897B).withOpacity(0.03),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MedicineIcon(isVerified: false),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          prescription.medicineName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A2E),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        _DosageChip(
                          dosage: prescription.dosage,
                          unit: prescription.unit,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.person_outline_rounded,
                                size: 13, color: Color(0xFF9E9E9E)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                prescription.doctorName.isNotEmpty
                                    ? 'Dr. ${prescription.doctorName}'
                                    : 'Self-managed',
                                style: const TextStyle(
                                    fontSize: 12.5, color: Color(0xFF666680)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        _DateRange(
                          startDate: prescription.startDate,
                          endDate: prescription.endDate,
                        ),
                      ],
                    ),
                  ),

                  // ── Active action buttons (patient-managed path) ──────────
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _GovernanceActionButton(
                        icon: Icons.edit_outlined,
                        isEnabled: true,
                        onTap: () => onEdit?.call(prescription),
                        tooltip: 'Edit prescription',
                        color: const Color(0xFF546E7A),
                      ),
                      const SizedBox(height: 8),
                      _GovernanceActionButton(
                        icon: Icons.delete_outline_rounded,
                        isEnabled: true,
                        onTap: () => _confirmDelete(context),
                        tooltip: 'Delete prescription',
                        color: _deleteColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Prescription?'),
        content: Text(
          'Remove "${prescription.medicineName}" from your Prescription Vault?\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: _deleteColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && prescription.id != null) {
      onDelete?.call(prescription.id!);
    }
  }
}

// ── Reusable sub-widgets (all const-capable) ─────────────────────────────────

class _MedicineIcon extends StatelessWidget {
  final bool isVerified;

  const _MedicineIcon({required this.isVerified});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: isVerified
            ? const Color(0xFFE6F7F4)
            : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.medication_rounded,
        size: 22,
        color: isVerified
            ? const Color(0xFF00897B)
            : const Color(0xFF78909C),
      ),
    );
  }
}

class _DosageChip extends StatelessWidget {
  final double dosage;
  final DosageUnit unit;

  const _DosageChip({required this.dosage, required this.unit});

  @override
  Widget build(BuildContext context) {
    // Format: drop trailing .0 for whole numbers (e.g., "500 mg" not "500.0 mg")
    final dosageStr = dosage == dosage.roundToDouble()
        ? dosage.toInt().toString()
        : dosage.toString();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$dosageStr ${unit.label}',
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF3D5AFE),
        ),
      ),
    );
  }
}

class _DateRange extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;

  const _DateRange({required this.startDate, required this.endDate});

  static final _fmt = DateFormat('d MMM yy');

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.calendar_today_outlined,
            size: 11, color: Color(0xFF9E9E9E)),
        const SizedBox(width: 4),
        Text(
          '${_fmt.format(startDate)} → ${_fmt.format(endDate)}',
          style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
        ),
      ],
    );
  }
}

/// A tappable icon button that respects governance state.
/// When [isEnabled] == false, it renders dimly but still accepts taps
/// to trigger the Clinical Lock explanation modal.
class _GovernanceActionButton extends StatelessWidget {
  final IconData icon;
  final bool isEnabled;
  final VoidCallback onTap;
  final String tooltip;
  final Color color;

  const _GovernanceActionButton({
    required this.icon,
    required this.isEnabled,
    required this.onTap,
    required this.tooltip,
    this.color = const Color(0xFF9E9E9E),
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact(); // Always fires for <100ms response.
          onTap();
        },
        child: Opacity(
          opacity: isEnabled ? 1.0 : 0.35,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
        ),
      ),
    );
  }
}
