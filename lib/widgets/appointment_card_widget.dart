/// appointment_card_widget.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Displays an appointment record in the My Doctors screen and dashboard.
///
/// Visual states:
///   • Confirmed (isVerified=true): teal left-border, lock badge, immutable.
///   • Pending:                     amber left-border, "Awaiting" chip.
///   • Rescheduled:                 blue left-border, shows previous time.
///   • Cancelled:                   grey, crossed-out time.
///   • Completed:                   green checkmark, muted styling.
///
/// The [compact] flag renders a condensed inline version for the doctor card.
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:vitalpath/models/appointment_model.dart';
import 'package:vitalpath/widgets/verified_badge_widget.dart';

class AppointmentCardWidget extends StatelessWidget {
  final AppointmentModel appointment;
  final bool compact;
  final VoidCallback? onCancel;

  const AppointmentCardWidget({
    super.key,
    required this.appointment,
    this.compact = false,
    this.onCancel,
  });

  static final _dateFmt = DateFormat('EEE, d MMM yyyy');
  static final _timeFmt = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: compact ? _buildCompact(context) : _buildFull(context),
    );
  }

  // ── Colour mapping by status ──────────────────────────────────────────────
  Color get _accentColor {
    switch (appointment.status) {
      case AppointmentStatus.confirmed:
        return const Color(0xFF00897B);
      case AppointmentStatus.pending:
        return const Color(0xFFF57C00);
      case AppointmentStatus.rescheduled:
        return const Color(0xFF1565C0);
      case AppointmentStatus.cancelled:
        return Colors.grey;
      case AppointmentStatus.completed:
        return const Color(0xFF2E7D32);
    }
  }

  Color get _bgColor {
    switch (appointment.status) {
      case AppointmentStatus.confirmed:
        return const Color(0xFFE6F7F4);
      case AppointmentStatus.pending:
        return const Color(0xFFFFF8E1);
      case AppointmentStatus.rescheduled:
        return const Color(0xFFE8F4FD);
      case AppointmentStatus.cancelled:
        return Colors.grey[100]!;
      case AppointmentStatus.completed:
        return const Color(0xFFE8F5E9);
    }
  }

  // ── Full card ─────────────────────────────────────────────────────────────
  Widget _buildFull(BuildContext context) {
    final displayTime = appointment.displayTime;
    final isLocked = appointment.isVerified;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: _accentColor, width: 4),
          top: BorderSide(color: Colors.grey[200]!, width: 1),
          right: BorderSide(color: Colors.grey[200]!, width: 1),
          bottom: BorderSide(color: Colors.grey[200]!, width: 1),
        ),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Dr. ${appointment.doctorName}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ),
                if (isLocked)
                  const VerifiedBadgeWidget.compact()
                else
                  _StatusChip(status: appointment.status, color: _accentColor),
              ],
            ),
            const SizedBox(height: 8),

            // ── Appointment time ────────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.access_time_rounded,
                    size: 14, color: _accentColor),
                const SizedBox(width: 6),
                Text(
                  '${_dateFmt.format(displayTime)}  •  ${_timeFmt.format(displayTime)}',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: appointment.status == AppointmentStatus.cancelled
                        ? Colors.grey[400]
                        : const Color(0xFF1A1A2E),
                    decoration:
                        appointment.status == AppointmentStatus.cancelled
                            ? TextDecoration.lineThrough
                            : null,
                  ),
                ),
              ],
            ),

            // ── Rescheduled: show previous time ────────────────────────────
            if (appointment.status == AppointmentStatus.rescheduled &&
                appointment.previousAppointedAt != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.history_rounded,
                      size: 13, color: Color(0xFF9E9E9E)),
                  const SizedBox(width: 6),
                  Text(
                    'Was: ${_dateFmt.format(appointment.previousAppointedAt!)}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9E9E9E),
                        decoration: TextDecoration.lineThrough),
                  ),
                ],
              ),
            ],

            // ── Reason ─────────────────────────────────────────────────────
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.notes_rounded,
                    size: 14, color: Color(0xFF9E9E9E)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    appointment.reason,
                    style: const TextStyle(
                        fontSize: 12.5, color: Color(0xFF666680)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            // ── Cancel button for pending appointments ──────────────────────
            if (appointment.status == AppointmentStatus.pending &&
                !isLocked &&
                onCancel != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE0E0E0)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text(
                    'Cancel Request',
                    style: TextStyle(
                        fontSize: 13, color: Color(0xFF9E9E9E)),
                  ),
                ),
              ),
            ],

            // ── Clinical Lock notice ────────────────────────────────────────
            if (isLocked) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F7F4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_rounded,
                        size: 12, color: Color(0xFF00897B)),
                    SizedBox(width: 6),
                    Text(
                      'This appointment is locked and synced to your dashboard.',
                      style: TextStyle(
                          fontSize: 11.5, color: Color(0xFF00695C)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Compact card (shown inline in doctor list) ────────────────────────────
  Widget _buildCompact(BuildContext context) {
    final displayTime = appointment.displayTime;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.event_available_rounded, size: 16, color: _accentColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_dateFmt.format(displayTime)}  •  ${_timeFmt.format(displayTime)}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _accentColor,
              ),
            ),
          ),
          if (appointment.isVerified)
            const Icon(Icons.lock_rounded,
                size: 13, color: Color(0xFF00897B)),
        ],
      ),
    );
  }
}

// ── Status chip ───────────────────────────────────────────────────────────────
class _StatusChip extends StatelessWidget {
  final AppointmentStatus status;
  final Color color;

  const _StatusChip({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
