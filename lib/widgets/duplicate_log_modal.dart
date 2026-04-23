/// duplicate_log_modal.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Safety check shown when a patient attempts to re-log a dose within
/// the 15-minute lockout window (Blueprint §1.2 — The Duplicate Log).
///
/// UI contract:
///   • Alert Red colour scheme — high-visibility but not alarming in language.
///   • Supportive, clinical copy — protects without shaming the patient.
///   • Shows medicine name, last-logged time, and a live countdown.
///   • TWO action paths:
///       [Primary]  "Got It — Skip This Log"  → dismisses, no action taken.
///       [Override] "I Need to Log Again" → calls [onForceLog] after a
///                   second deliberate tap (the button changes label on first
///                   press to prevent accidental override).
///   • HapticFeedback.heavyImpact() fires on show — the most insistent
///     haptic available, appropriate for a safety-critical warning.
/// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:vitalpath/services/medicine_logging_service.dart';

class DuplicateLogModal extends StatefulWidget {
  final DuplicateLogException exception;

  /// Called when the patient deliberately overrides the guard.
  final VoidCallback onForceLog;

  const DuplicateLogModal({
    super.key,
    required this.exception,
    required this.onForceLog,
  });

  static Future<void> show(
    BuildContext context, {
    required DuplicateLogException exception,
    required VoidCallback onForceLog,
  }) {
    HapticFeedback.heavyImpact(); // critical safety alert haptic
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false, // patient must make a deliberate choice
      enableDrag: false,
      builder: (_) => DuplicateLogModal(
        exception: exception,
        onForceLog: onForceLog,
      ),
    );
  }

  @override
  State<DuplicateLogModal> createState() => _DuplicateLogModalState();
}

class _DuplicateLogModalState extends State<DuplicateLogModal> {
  late int _remainingSeconds;
  Timer? _countdownTimer;
  bool _overrideArmed = false; // first press arms the override button

  static final _timeFmt = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.exception.remainingLockoutSeconds;
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _remainingSeconds--);
      if (_remainingSeconds <= 0) {
        t.cancel();
        // Auto-dismiss when the lockout window expires.
        if (mounted) Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  String get _formattedRemaining {
    final m = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle ─────────────────────────────────────────────────────
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

            // ── Critical icon ───────────────────────────────────────────────
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.warning_rounded,
                size: 34,
                color: Color(0xFFB71C1C),
              ),
            ),
            const SizedBox(height: 16),

            // ── Title ───────────────────────────────────────────────────────
            const Text(
              'Already Logged Today',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFFB71C1C),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'It looks like ${widget.exception.medicineName} was logged at '
              '${_timeFmt.format(widget.exception.lastLoggedAt)}. '
              'We\'re just making sure you meant to log it again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14.5, color: Colors.grey[700], height: 1.5),
            ),
            const SizedBox(height: 20),

            // ── Countdown chip ──────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: const Color(0xFFE53935).withOpacity(0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.timer_outlined,
                      size: 20, color: Color(0xFFE53935)),
                  const SizedBox(width: 10),
                  Column(
                    children: [
                      Text(
                        _formattedRemaining,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFB71C1C),
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Text(
                        'before the safe re-log window',
                        style: TextStyle(
                            fontSize: 11.5, color: Color(0xFFE57373)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Primary: dismiss (safe path) ────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: const Text(
                  'Got It — Skip This Log',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00897B),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // ── Override path ───────────────────────────────────────────────
            // First press arms the button (label changes to a final confirm).
            // Second press executes the override. Prevents accidental taps.
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  if (!_overrideArmed) {
                    setState(() => _overrideArmed = true);
                  } else {
                    // Second deliberate press — execute override.
                    HapticFeedback.heavyImpact();
                    Navigator.of(context).pop();
                    widget.onForceLog();
                  }
                },
                icon: Icon(
                  _overrideArmed
                      ? Icons.priority_high_rounded
                      : Icons.replay_rounded,
                  size: 17,
                  color: const Color(0xFFE53935),
                ),
                label: Text(
                  _overrideArmed
                      ? 'Confirm — Log Again Now'
                      : 'I Need to Log Again',
                  style: const TextStyle(
                    color: Color(0xFFE53935),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: _overrideArmed
                        ? const Color(0xFFB71C1C)
                        : const Color(0xFFE53935).withOpacity(0.5),
                    width: _overrideArmed ? 2 : 1,
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            const SizedBox(height: 8),
            Text(
              'Only log again if directed by your doctor or care team.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }
}
