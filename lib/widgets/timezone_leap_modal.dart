/// timezone_leap_modal.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// The Timezone Leap prompt — shown when [TimezoneService] detects a system
/// clock change of ≥ 1 hour (Blueprint §1.2).
///
/// The modal presents two clear paths:
///
///   [Keep Home Timezone]
///     "Your alarms will stay at their original times. If your medicine
///      was due at 08:00 in London, it will still ring at 08:00 London time."
///
///   [Adapt to Local Time]
///     "Your alarms will shift to match your new location. Your 08:00 London
///      alarm will now ring at the equivalent local time."
///
/// The choice is persisted by [TimezoneService] and applied to all scheduled
/// notifications immediately.
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:vitalpath/services/timezone_service.dart';

class TimezoneLeapModal extends StatelessWidget {
  final TimezoneChangeEvent event;
  final TimezoneService timezoneService;

  const TimezoneLeapModal({
    super.key,
    required this.event,
    required this.timezoneService,
  });

  static Future<void> show(
    BuildContext context, {
    required TimezoneChangeEvent event,
    required TimezoneService timezoneService,
  }) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => TimezoneLeapModal(
        event: event,
        timezoneService: timezoneService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDstGain = event.delta.isNegative; // moved to earlier timezone
    final deltaHours = event.delta.inHours.abs();

    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle ──────────────────────────────────────────────────────
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

            // ── Icon ─────────────────────────────────────────────────────────
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F4FD),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.public_rounded,
                size: 30,
                color: Color(0xFF1565C0),
              ),
            ),
            const SizedBox(height: 16),

            // ── Title ─────────────────────────────────────────────────────────
            const Text(
              'Timezone Change Detected',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),

            // ── Change summary ────────────────────────────────────────────────
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(
                    fontSize: 14, color: Colors.grey[600], height: 1.5),
                children: [
                  const TextSpan(text: 'Your device moved from '),
                  TextSpan(
                    text: event.homeLabel,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E)),
                  ),
                  const TextSpan(text: ' to '),
                  TextSpan(
                    text: event.newLabel,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E)),
                  ),
                  TextSpan(
                    text:
                        ' (${isDstGain ? '-' : '+'}$deltaHours hour${deltaHours == 1 ? '' : 's'}).',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Question ──────────────────────────────────────────────────────
            Text(
              'How should your medication alarms respond?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 16),

            // ── Option A: Keep Home ───────────────────────────────────────────
            _TimezoneOption(
              icon: Icons.home_rounded,
              iconColor: const Color(0xFF00897B),
              iconBg: const Color(0xFFE6F7F4),
              title: 'Keep Home Timezone (${event.homeLabel})',
              description:
                  'Alarms ring at the same clock time as your home. '
                  'Best for short trips.',
              onTap: () async {
                HapticFeedback.lightImpact();
                await timezoneService.applyKeepHomeTimezone();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 10),

            // ── Option B: Adapt to Local ──────────────────────────────────────
            _TimezoneOption(
              icon: Icons.location_on_rounded,
              iconColor: const Color(0xFF1565C0),
              iconBg: const Color(0xFFE8F4FD),
              title: 'Adapt to Local Time (${event.newLabel})',
              description:
                  'Alarms shift to match your current location. '
                  'Best for long-term relocation.',
              onTap: () async {
                HapticFeedback.lightImpact();
                await timezoneService.applyAdaptToLocal(event.newOffset);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),

            const SizedBox(height: 16),
            Text(
              'You can change this later in Notification Settings.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Option tile ───────────────────────────────────────────────────────────────
class _TimezoneOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _TimezoneOption({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: iconColor.withOpacity(0.08),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[200]!),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[500], height: 1.4),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.grey[400], size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
