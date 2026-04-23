/// request_appointment_bottom_sheet.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// The appointment request form launched from the "My Doctors" screen.
///
/// Submitted appointments start in [AppointmentStatus.pending] with
/// [isVerified] = false. They become locked only when the doctor confirms.
///
/// Routes through [SyncQueueService] when offline, preserving [requestedAt]
/// as the [originalTimestamp].
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:vitalpath/models/appointment_model.dart';
import 'package:vitalpath/models/doctor_model.dart';
import 'package:vitalpath/models/governance_level.dart';

typedef OnAppointmentSubmit = void Function(AppointmentModel appointment);

class RequestAppointmentBottomSheet extends StatefulWidget {
  final DoctorModel doctor;
  final String patientId;
  final OnAppointmentSubmit onSubmit;

  const RequestAppointmentBottomSheet({
    super.key,
    required this.doctor,
    required this.patientId,
    required this.onSubmit,
  });

  static Future<void> show(
    BuildContext context, {
    required DoctorModel doctor,
    required String patientId,
    required OnAppointmentSubmit onSubmit,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RequestAppointmentBottomSheet(
        doctor: doctor,
        patientId: patientId,
        onSubmit: onSubmit,
      ),
    );
  }

  @override
  State<RequestAppointmentBottomSheet> createState() =>
      _RequestAppointmentBottomSheetState();
}

class _RequestAppointmentBottomSheetState
    extends State<RequestAppointmentBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _reasonCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  DateTime _preferredDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _preferredTime = const TimeOfDay(hour: 10, minute: 0);
  bool _isSubmitting = false;

  static final _dateFmt = DateFormat('EEE, d MMM yyyy');

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  DateTime get _preferredDateTime => DateTime(
        _preferredDate.year,
        _preferredDate.month,
        _preferredDate.day,
        _preferredTime.hour,
        _preferredTime.minute,
      );

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
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, sc) => _buildForm(sc),
      ),
    );
  }

  Widget _buildForm(ScrollController sc) {
    return Form(
      key: _formKey,
      child: ListView(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          // ── Handle ──────────────────────────────────────────────────────
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),

          // ── Doctor info ──────────────────────────────────────────────────
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFE6F7F4),
                child: Text(
                  widget.doctor.name[0],
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF00897B)),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Request Appointment',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E)),
                  ),
                  Text(
                    'Dr. ${widget.doctor.name} · ${widget.doctor.specialty}',
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF9E9E9E)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Reason ──────────────────────────────────────────────────────
          _Label('Reason for Visit *'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _reasonCtrl,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
            decoration: _decoration(
                hint: 'e.g., Follow-up, medication review, new symptoms'),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Please describe your reason for the visit.'
                : null,
          ),
          const SizedBox(height: 16),

          // ── Preferred date ───────────────────────────────────────────────
          _Label('Preferred Date *'),
          const SizedBox(height: 6),
          _DateButton(
            date: _preferredDate,
            onPick: (d) => setState(() => _preferredDate = d),
          ),
          const SizedBox(height: 12),

          // ── Preferred time ───────────────────────────────────────────────
          _Label('Preferred Time'),
          const SizedBox(height: 6),
          _TimeButton(
            time: _preferredTime,
            onPick: (t) => setState(() => _preferredTime = t),
          ),
          const SizedBox(height: 16),

          // ── Notes ────────────────────────────────────────────────────────
          _Label('Additional Notes (optional)'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _notesCtrl,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 3,
            decoration: _decoration(hint: 'Any other details for the doctor'),
          ),
          const SizedBox(height: 28),

          // ── Submit ───────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(
                _isSubmitting ? 'Sending Request…' : 'Send Appointment Request',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    HapticFeedback.lightImpact();

    setState(() => _isSubmitting = true);

    // [requestedAt] captures the exact moment the patient taps Submit.
    // This is the [originalTimestamp] for the SyncQueue.
    final requestedAt = DateTime.now();

    final appointment = AppointmentModel(
      patientId: widget.patientId,
      doctorId: widget.doctor.uid,
      doctorName: widget.doctor.name,
      reason: _reasonCtrl.text.trim(),
      preferredAt: _preferredDateTime,
      patientNotes: _notesCtrl.text.trim().isNotEmpty
          ? _notesCtrl.text.trim()
          : null,
      status: AppointmentStatus.pending,
      isVerified: false,                               // patient request — never pre-verified
      governanceLevel: GovernanceLevel.patientManaged, // locked on doctor confirmation
      requestedAt: requestedAt,                        // ← originalTimestamp
      updatedAt: requestedAt,
    );

    try {
      widget.onSubmit(appointment);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not submit request: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFE53935),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  InputDecoration _decoration({required String hint}) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(fontSize: 14, color: Color(0xFFBDBDBD)),
        filled: true,
        fillColor: const Color(0xFFF8F9FA),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE8E8EE)),
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
      );
}

// ── Small helpers ─────────────────────────────────────────────────────────────
class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF555566)),
      );
}

class _DateButton extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onPick;
  static final _fmt = DateFormat('EEE, d MMM yyyy');

  const _DateButton({required this.date, required this.onPick});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () async {
          HapticFeedback.lightImpact();
          final picked = await showDatePicker(
            context: context,
            initialDate: date,
            firstDate: DateTime.now(),
            lastDate: DateTime.now().add(const Duration(days: 365)),
            builder: (c, child) => Theme(
              data: Theme.of(c).copyWith(
                colorScheme: const ColorScheme.light(
                    primary: Color(0xFF00897B)),
              ),
              child: child!,
            ),
          );
          if (picked != null) onPick(picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE8E8EE)),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 16, color: Color(0xFF9E9E9E)),
              const SizedBox(width: 10),
              Text(
                _fmt.format(date),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E)),
              ),
            ],
          ),
        ),
      );
}

class _TimeButton extends StatelessWidget {
  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onPick;

  const _TimeButton({required this.time, required this.onPick});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () async {
          HapticFeedback.lightImpact();
          final picked = await showTimePicker(
            context: context,
            initialTime: time,
            builder: (c, child) => Theme(
              data: Theme.of(c).copyWith(
                colorScheme: const ColorScheme.light(
                    primary: Color(0xFF00897B)),
              ),
              child: child!,
            ),
          );
          if (picked != null) onPick(picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE8E8EE)),
          ),
          child: Row(
            children: [
              const Icon(Icons.access_time_rounded,
                  size: 16, color: Color(0xFF9E9E9E)),
              const SizedBox(width: 10),
              Text(
                time.format(context),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E)),
              ),
            ],
          ),
        ),
      );
}
