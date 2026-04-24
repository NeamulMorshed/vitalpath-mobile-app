import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:vitalpath/models/timeline_entry.dart';
import 'package:vitalpath/providers/dashboard_provider.dart';
import 'package:vitalpath/services/haptic_service.dart';
import 'package:vitalpath/services/medicine_logging_service.dart';
import 'package:vitalpath/theme/vitalpath_theme.dart';
import 'package:vitalpath/widgets/duplicate_log_modal.dart';
import 'package:vitalpath/widgets/glass_card.dart';
import 'package:vitalpath/widgets/success_toast.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Smart Timeline — 2026 Glass Card Edition
// ─────────────────────────────────────────────────────────────────────────────
// Visual states (Elevated vs. Faded logic):
//   dueNow    → GlassCard.dark + Electric Teal border glow  (100% opacity)
//   upcoming  → GlassCard.dark + subtle border              (100% opacity)
//   locked    → GlassCard.accent (teal-tinted)              (100% opacity)
//   missed    → dark card + amber border                    (72% opacity)
//   completed → plain dark card, no border, 40% opacity + checkmark
//
// Performance:
//   • RepaintBoundary per card (SliverList is lazy).
//   • _PulsingCard: pulsing border AnimationController, isolated repaint.
//   • const constructors throughout.
// ─────────────────────────────────────────────────────────────────────────────

class SmartTimelineSliverList extends StatelessWidget {
  const SmartTimelineSliverList({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        final entries = provider.todayEntries;

        if (entries.isEmpty) {
          return const SliverToBoxAdapter(child: _EmptyTimelineState());
        }

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final entry = entries[index];
              return RepaintBoundary(
                key: ValueKey(entry.id),
                child: _TimelineCard(entry: entry),
              );
            },
            childCount: entries.length,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timeline Card — routes to pulsing or static variant
// ─────────────────────────────────────────────────────────────────────────────
class _TimelineCard extends StatelessWidget {
  final TimelineEntry entry;
  const _TimelineCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    // Completed entries: 40% opacity, faded appearance
    if (entry.isCompleted) {
      return Opacity(
        opacity: 0.40,
        child: _StaticGlassCard(entry: entry),
      );
    }
    // Missed: 72% opacity, amber tint
    if (entry.isMissed) {
      return Opacity(
        opacity: 0.72,
        child: _StaticGlassCard(entry: entry),
      );
    }
    // Due Now: pulsing electric teal border
    if (entry.isDueNow) {
      return _PulsingGlassCard(entry: entry);
    }
    // Upcoming / Locked: static glass card, full opacity
    return _StaticGlassCard(entry: entry);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pulsing glass card — electric teal border for "Due Now"
// ─────────────────────────────────────────────────────────────────────────────
class _PulsingGlassCard extends StatefulWidget {
  final TimelineEntry entry;
  const _PulsingGlassCard({required this.entry});

  @override
  State<_PulsingGlassCard> createState() => _PulsingGlassCardState();
}

class _PulsingGlassCardState extends State<_PulsingGlassCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _glow = Tween<double>(begin: 0.3, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glow,
      builder: (_, child) => _CardWrapper(
        entry: widget.entry,
        borderColor: VitalPathTheme.electricTeal.withValues(alpha: _glow.value * 0.7),
        glowShadow: [
          BoxShadow(
            color: VitalPathTheme.electricTeal
                .withValues(alpha: 0.15 * _glow.value),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        child: child!,
      ),
      child: _CardBody(entry: widget.entry),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Static glass card — upcoming / locked / missed / completed
// ─────────────────────────────────────────────────────────────────────────────
class _StaticGlassCard extends StatelessWidget {
  final TimelineEntry entry;
  const _StaticGlassCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    Color borderColor;
    switch (entry.state) {
      case TimelineEntryState.upcoming:
        borderColor = Colors.white.withValues(alpha: 0.12);
        break;
      case TimelineEntryState.locked:
        borderColor = VitalPathTheme.clinicalTeal.withValues(alpha: 0.4);
        break;
      case TimelineEntryState.missed:
        borderColor = VitalPathTheme.alertAmber.withValues(alpha: 0.35);
        break;
      default:
        borderColor = Colors.white.withValues(alpha: 0.06);
    }

    return _CardWrapper(
      entry: entry,
      borderColor: borderColor,
      glowShadow: null,
      child: _CardBody(entry: entry),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card wrapper — glass container + left-accent stripe
// ─────────────────────────────────────────────────────────────────────────────
class _CardWrapper extends StatelessWidget {
  final TimelineEntry entry;
  final Color borderColor;
  final List<BoxShadow>? glowShadow;
  final Widget child;

  const _CardWrapper({
    required this.entry,
    required this.borderColor,
    required this.glowShadow,
    required this.child,
  });

  Color get _stripeColor {
    switch (entry.state) {
      case TimelineEntryState.dueNow:
        return VitalPathTheme.electricTeal;
      case TimelineEntryState.upcoming:
        return VitalPathTheme.clinicalTeal;
      case TimelineEntryState.locked:
        return VitalPathTheme.clinicalTeal;
      case TimelineEntryState.missed:
        return VitalPathTheme.alertAmber;
      case TimelineEntryState.completed:
        return Colors.white.withValues(alpha: 0.2);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: GlassCard.dark(
        borderRadius: BorderRadius.circular(16),
        borderColor: borderColor,
        borderWidth: entry.isDueNow ? 1.5 : 1.0,
        boxShadow: glowShadow ?? VitalPathTheme.cardShadow,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left accent stripe
                Container(
                  width: 3,
                  color: _stripeColor,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card body — content, quick-log, variable typography
// ─────────────────────────────────────────────────────────────────────────────
class _CardBody extends StatelessWidget {
  final TimelineEntry entry;
  static final _timeFmt = DateFormat('h:mm a');

  const _CardBody({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon badge
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _iconBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(entry.type.icon, size: 18, color: _accentColor),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Medicine name — light (w400) per variable-typography spec
                  Text(
                    entry.title,
                    style: TextStyle(
                      fontSize: 15,
                      // Upcoming/dueNow: bold for scannability; completed: light
                      fontWeight: entry.isUpcoming || entry.isDueNow
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: entry.isCompleted
                          ? Colors.white.withValues(alpha: 0.5)
                          : Colors.white,
                      decoration: entry.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Dosage — heavy (w700) per variable-typography spec
                  Text(
                    entry.subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: entry.isDueNow || entry.isUpcoming
                          ? FontWeight.w700  // heavy = clinical data
                          : FontWeight.w400, // light = faded label
                      color: entry.isCompleted
                          ? Colors.white.withValues(alpha: 0.3)
                          : _accentColor.withValues(alpha: 0.85),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _StateBadge(state: entry.state),
                const SizedBox(height: 4),
                Text(
                  _timeFmt.format(entry.scheduledAt),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: entry.isCompleted
                        ? Colors.white.withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.5),
                    decoration: entry.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                    decorationColor: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
              ],
            ),
          ],
        ),

        // Doctor name
        if (entry.doctorName != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.verified_rounded,
                  size: 12, color: VitalPathTheme.verifiedGold),
              const SizedBox(width: 5),
              Text(
                'Dr. ${entry.doctorName}',
                style: VitalPathTheme.verifiedData.copyWith(fontSize: 11),
              ),
            ],
          ),
        ],

        // Quick-Log (medicine, active state)
        if (entry.canQuickLog) ...[
          const SizedBox(height: 10),
          _QuickLogChip(entry: entry),
        ],

        // Completed row
        if (entry.isCompleted) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  size: 14, color: Color(0xFF66BB6A)),
              const SizedBox(width: 5),
              Text(
                'Logged',
                style: VitalPathTheme.patientData.copyWith(
                  color: const Color(0xFF66BB6A),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],

        // Clinical lock notice
        if (entry.isLocked) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.lock_rounded,
                  size: 12, color: VitalPathTheme.clinicalTeal),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Confirmed — synced to your passbook',
                  style: VitalPathTheme.patientData.copyWith(
                    color: VitalPathTheme.electricTeal.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Color get _accentColor {
    switch (entry.state) {
      case TimelineEntryState.dueNow:
        return VitalPathTheme.electricTeal;
      case TimelineEntryState.upcoming:
        return VitalPathTheme.clinicalTeal;
      case TimelineEntryState.locked:
        return VitalPathTheme.clinicalTeal;
      case TimelineEntryState.missed:
        return VitalPathTheme.alertAmber;
      case TimelineEntryState.completed:
        return Colors.grey;
    }
  }

  Color get _iconBgColor =>
      _accentColor.withValues(alpha: 0.15);
}

// ─────────────────────────────────────────────────────────────────────────────
// State Badge Chip
// ─────────────────────────────────────────────────────────────────────────────
class _StateBadge extends StatelessWidget {
  final TimelineEntryState state;
  const _StateBadge({required this.state});

  String get _label {
    switch (state) {
      case TimelineEntryState.dueNow:     return 'Due Now';
      case TimelineEntryState.upcoming:   return 'Upcoming';
      case TimelineEntryState.locked:     return 'Confirmed';
      case TimelineEntryState.missed:     return 'Missed';
      case TimelineEntryState.completed:  return 'Done';
    }
  }

  Color get _color {
    switch (state) {
      case TimelineEntryState.dueNow:     return VitalPathTheme.electricTeal;
      case TimelineEntryState.upcoming:   return VitalPathTheme.clinicalTeal;
      case TimelineEntryState.locked:     return VitalPathTheme.clinicalTeal;
      case TimelineEntryState.missed:     return VitalPathTheme.alertAmber;
      case TimelineEntryState.completed:  return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Text(
        _label,
        style: VitalPathTheme.labelMedium.copyWith(color: _color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick-Log chip (timeline card variant — smaller than bento Log button)
// ─────────────────────────────────────────────────────────────────────────────
class _QuickLogChip extends StatefulWidget {
  final TimelineEntry entry;
  const _QuickLogChip({required this.entry});

  @override
  State<_QuickLogChip> createState() => _QuickLogChipState();
}

class _QuickLogChipState extends State<_QuickLogChip> {
  bool _tapping = false;

  Future<void> _onTap(BuildContext context) async {
    if (_tapping) return;
    HapticFeedback.selectionClick();
    setState(() => _tapping = true);

    final provider = context.read<DashboardProvider>();
    try {
      await provider.quickLog(
        entryId: widget.entry.id,
        medicineId: widget.entry.medicineId!,
      );
      if (!mounted) return;
      HapticService().doseLogged();
      SuccessToast.show(
        context,
        medicineName: widget.entry.title,
        dose: widget.entry.subtitle,
      );
    } on DuplicateLogException catch (ex) {
      if (!mounted) return;
      await DuplicateLogModal.show(
        context,
        exception: ex,
        onForceLog: () async {
          await provider.quickLog(
            entryId: widget.entry.id,
            medicineId: widget.entry.medicineId!,
            forceOverride: true,
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not log dose: $e'),
          backgroundColor: VitalPathTheme.errorRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      if (mounted) setState(() => _tapping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Material(
          color: VitalPathTheme.electricTeal.withValues(alpha: 0.10),
          child: InkWell(
            onTap: _tapping ? null : () => _onTap(context),
            splashColor: VitalPathTheme.electricTeal.withValues(alpha: 0.3),
            highlightColor: VitalPathTheme.electricTeal.withValues(alpha: 0.08),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: VitalPathTheme.electricTeal.withValues(alpha: 0.25),
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: _tapping
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: VitalPathTheme.electricTeal,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.medication_rounded,
                              size: 14,
                              color: VitalPathTheme.electricTeal),
                          const SizedBox(width: 6),
                          Text(
                            'Log Dose',
                            style: VitalPathTheme.ctaPrimary.copyWith(
                              color: VitalPathTheme.electricTeal,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty Timeline State
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyTimelineState extends StatelessWidget {
  const _EmptyTimelineState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassCard.dark(
            borderRadius: BorderRadius.circular(20),
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color:
                        VitalPathTheme.clinicalTeal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.event_available_rounded,
                      size: 32, color: VitalPathTheme.electricTeal),
                ),
                const SizedBox(height: 16),
                Text(
                  'All clear for today!',
                  style: VitalPathTheme.headlineMedium.copyWith(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'No medicines, meals, or appointments\nscheduled yet for today.',
                  textAlign: TextAlign.center,
                  style: VitalPathTheme.bodyMedium.copyWith(
                    color: Colors.white.withValues(alpha: 0.4),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
