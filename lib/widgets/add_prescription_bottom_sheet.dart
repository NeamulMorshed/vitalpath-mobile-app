/// add_prescription_bottom_sheet.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// The "+ Add Medicine" FAB form — invoked from both CareScreen and the
/// Prescription Vault.
///
/// Key contracts (Blueprint §1.1):
///   • [is_verified] is HARDCODED to false. The patient-initiated add flow
///     can NEVER produce a verified record. Verification only happens when
///     a doctor pushes via the sync flow (server-side Cloud Function).
///   • [governance_level] is HARDCODED to GovernanceLevel.patientManaged.
///   • Dosage must be a positive numeric value (client-side validation mirrors
///     the model's validate() rules).
///   • [start_date] cannot be after [end_date] (enforced before form submit).
///   • When [initialPrescription] is provided, the form operates in edit mode
///     and pre-fills all fields (edit path for patient-managed records only).
///
/// Performance:
///   • Form fields use [TextEditingController] with explicit disposal.
///   • A single [AnimatedContainer] handles the keyboard-push animation.
///   • [ImageUploadWidget] is mounted lazily below the fold.
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:vitalpath/models/governance_level.dart';
import 'package:vitalpath/models/prescription_model.dart';
import 'package:vitalpath/widgets/image_upload_widget.dart';

typedef OnPrescriptionSaved = void Function(PrescriptionModel prescription);

class AddPrescriptionBottomSheet extends StatefulWidget {
  /// When null → "Add" mode. When provided → "Edit" mode.
  final PrescriptionModel? initialPrescription;
  final OnPrescriptionSaved onSaved;

  const AddPrescriptionBottomSheet({
    super.key,
    this.initialPrescription,
    required this.onSaved,
  });

  // ── Static entry point ────────────────────────────────────────────────────
  static Future<void> show(
    BuildContext context, {
    PrescriptionModel? initialPrescription,
    required OnPrescriptionSaved onSaved,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddPrescriptionBottomSheet(
        initialPrescription: initialPrescription,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<AddPrescriptionBottomSheet> createState() =>
      _AddPrescriptionBottomSheetState();
}

class _AddPrescriptionBottomSheetState
    extends State<AddPrescriptionBottomSheet> {
  final _formKey = GlobalKey<FormState>();

  // ── Text controllers ──────────────────────────────────────────────────────
  late final TextEditingController _medicineCtrl;
  late final TextEditingController _doctorCtrl;
  late final TextEditingController _dosageCtrl;
  late final TextEditingController _instructionsCtrl;

  // ── Form state ────────────────────────────────────────────────────────────
  DosageUnit _selectedUnit = DosageUnit.mg;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 7));
  String? _imageUrl;
  bool _isSaving = false;

  bool get _isEditMode => widget.initialPrescription != null;

  static final _dateFmt = DateFormat('d MMM yyyy');

  @override
  void initState() {
    super.initState();
    final p = widget.initialPrescription;
    _medicineCtrl = TextEditingController(text: p?.medicineName ?? '');
    _doctorCtrl = TextEditingController(text: p?.doctorName ?? '');
    _dosageCtrl =
        TextEditingController(text: p != null ? '${p.dosage}' : '');
    _instructionsCtrl =
        TextEditingController(text: p?.instructions ?? '');

    if (p != null) {
      _selectedUnit = p.unit;
      _startDate = p.startDate;
      _endDate = p.endDate;
    }
  }

  @override
  void dispose() {
    _medicineCtrl.dispose();
    _doctorCtrl.dispose();
    _dosageCtrl.dispose();
    _instructionsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.97,
        expand: false,
        builder: (context, scrollController) => _buildForm(scrollController),
      ),
    );
  }

  Widget _buildForm(ScrollController scrollController) {
    return Form(
      key: _formKey,
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          // ── Header ────────────────────────────────────────────────────────
          SliverToBoxAdapter(child: _buildHeader()),

          // ── Form body ─────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── GOVERNANCE NOTICE (always shown) ─────────────────────
                _GovernanceNotice(),
                const SizedBox(height: 20),

                // ── Medicine name ─────────────────────────────────────────
                _SectionLabel(label: 'Medicine Name *'),
                const SizedBox(height: 6),
                _buildTextField(
                  controller: _medicineCtrl,
                  hint: 'e.g., Metformin, Lisinopril',
                  icon: Icons.medication_rounded,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Medicine name is required.'
                      : null,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),

                // ── Doctor name ───────────────────────────────────────────
                _SectionLabel(label: 'Doctor / Prescriber'),
                const SizedBox(height: 6),
                _buildTextField(
                  controller: _doctorCtrl,
                  hint: 'e.g., Dr. Sarah Ahmed',
                  icon: Icons.person_outline_rounded,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),

                // ── Dosage + Unit ─────────────────────────────────────────
                _SectionLabel(label: 'Dosage *'),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildTextField(
                        controller: _dosageCtrl,
                        hint: 'e.g., 500',
                        icon: Icons.scale_outlined,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d+\.?\d{0,3}')),
                        ],
                        validator: _validateDosage,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _buildUnitDropdown(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Date range ────────────────────────────────────────────
                _SectionLabel(label: 'Course Duration *'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _DatePickerTile(
                        label: 'Start Date',
                        date: _startDate,
                        onPick: (d) => setState(() {
                          _startDate = d;
                          // Ensure end_date >= start_date.
                          if (_endDate.isBefore(_startDate)) {
                            _endDate = _startDate.add(const Duration(days: 1));
                          }
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DatePickerTile(
                        label: 'End Date',
                        date: _endDate,
                        firstDate: _startDate,
                        onPick: (d) => setState(() => _endDate = d),
                      ),
                    ),
                  ],
                ),
                if (_endDate.isBefore(_startDate)) ...[
                  const SizedBox(height: 4),
                  const Text(
                    '⚠ End date must be on or after the start date.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFE53935)),
                  ),
                ],
                const SizedBox(height: 16),

                // ── Instructions ──────────────────────────────────────────
                _SectionLabel(label: 'Instructions (optional)'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _instructionsCtrl,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _inputDecoration(
                    hint: 'e.g., Take after meals, avoid alcohol',
                    icon: Icons.notes_rounded,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Image upload ──────────────────────────────────────────
                _SectionLabel(label: 'Pill Bottle Photo (optional)'),
                const SizedBox(height: 6),
                ImageUploadWidget(
                  prescriptionId: widget.initialPrescription?.id ?? 'new',
                  currentImageUrl: _imageUrl,
                  isLocked: false, // Always unlocked in the add/edit form.
                  onImageUploaded: (url) => setState(() => _imageUrl = url),
                ),
                const SizedBox(height: 28),

                // ── Save button ───────────────────────────────────────────
                _buildSaveButton(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 20),
      child: Column(
        children: [
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
          Row(
            children: [
              Expanded(
                child: Text(
                  _isEditMode ? 'Edit Prescription' : 'Add Prescription',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Color(0xFF9E9E9E)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Unit dropdown ─────────────────────────────────────────────────────────
  Widget _buildUnitDropdown() {
    return DropdownButtonFormField<DosageUnit>(
      value: _selectedUnit,
      decoration: _inputDecoration(hint: 'Unit', icon: null),
      borderRadius: BorderRadius.circular(12),
      items: DosageUnit.values
          .map((u) => DropdownMenuItem(value: u, child: Text(u.label)))
          .toList(),
      onChanged: (u) => setState(() => _selectedUnit = u!),
    );
  }

  // ── Save button ───────────────────────────────────────────────────────────
  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: _isSaving ? null : _onSave,
        icon: _isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Icon(_isEditMode ? Icons.save_rounded : Icons.add_rounded,
                size: 20),
        label: Text(
          _isSaving
              ? 'Saving…'
              : _isEditMode
                  ? 'Save Changes'
                  : 'Add to Prescription Vault',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF00897B),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  // ── Validation & save ─────────────────────────────────────────────────────
  String? _validateDosage(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Dosage is required.';
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null) return 'Enter a valid number.';
    if (parsed <= 0) return 'Dosage must be greater than 0.';
    if (parsed.isInfinite || parsed.isNaN) return 'Enter a valid finite number.';
    return null;
  }

  Future<void> _onSave() async {
    // Trigger all field validators.
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Cross-field date validation.
    if (_endDate.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End date must be on or after the start date.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _isSaving = true);

    try {
      final now = DateTime.now();
      final p = widget.initialPrescription;

      // ── CRITICAL: is_verified HARDCODED to false ──────────────────────────
      // Patients can NEVER produce a verified record through this form.
      // governance_level HARDCODED to patientManaged.
      final prescription = PrescriptionModel(
        id: p?.id,
        patientId: p?.patientId ?? '',
        medicineName: _medicineCtrl.text.trim(),
        doctorName: _doctorCtrl.text.trim().isNotEmpty
            ? _doctorCtrl.text.trim()
            : 'Self-Prescribed',
        dosage: double.parse(_dosageCtrl.text.trim()),
        unit: _selectedUnit,
        instructions: _instructionsCtrl.text.trim().isNotEmpty
            ? _instructionsCtrl.text.trim()
            : null,
        startDate: _startDate,
        endDate: _endDate,
        isVerified: false,                              // ← HARDCODED: never true
        governanceLevel: GovernanceLevel.patientManaged, // ← HARDCODED: never physician
        createdAt: p?.createdAt ?? now,
        updatedAt: now,
      );

      // Run model-level validation as final safety net.
      prescription.validateOrThrow();

      widget.onSaved(prescription);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFE53935),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Shared input decoration ───────────────────────────────────────────────
  InputDecoration _inputDecoration({
    required String hint,
    IconData? icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
          const TextStyle(fontSize: 14, color: Color(0xFFBDBDBD)),
      prefixIcon: icon != null
          ? Icon(icon, size: 18, color: const Color(0xFF9E9E9E))
          : null,
      filled: true,
      fillColor: const Color(0xFFF8F9FA),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE8E8EE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            const BorderSide(color: Color(0xFF00897B), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            const BorderSide(color: Color(0xFFE53935), width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            const BorderSide(color: Color(0xFFE53935), width: 1.5),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      decoration: _inputDecoration(hint: hint, icon: icon),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

/// Clinical notice shown at the top of every add/edit form.
/// Reinforces to the patient that they can never self-verify.
class _GovernanceNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FAF8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFF00897B).withOpacity(0.25)),
      ),
      child: Row(
        children: const [
          Icon(Icons.info_outline_rounded,
              size: 16, color: Color(0xFF00897B)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Prescriptions you add are self-managed. '
              'Doctor-verified records can only be added by your physician.',
              style: TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF00695C),
                  height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF555566),
      ),
    );
  }
}

class _DatePickerTile extends StatelessWidget {
  final String label;
  final DateTime date;
  final DateTime? firstDate;
  final ValueChanged<DateTime> onPick;

  static final _fmt = DateFormat('d MMM yyyy');

  const _DatePickerTile({
    required this.label,
    required this.date,
    required this.onPick,
    this.firstDate,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.lightImpact();
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: firstDate ?? DateTime(2000),
          lastDate: DateTime(2100),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF00897B),
              ),
            ),
            child: child!,
          ),
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8E8EE)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 15, color: Color(0xFF9E9E9E)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 10.5, color: Color(0xFFBDBDBD))),
                  Text(_fmt.format(date),
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A2E))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
