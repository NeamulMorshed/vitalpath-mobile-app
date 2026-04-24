import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:vitalpath/models/timeline_entry.dart';
import 'package:vitalpath/providers/dashboard_provider.dart';
import 'package:vitalpath/services/haptic_service.dart';
import 'package:vitalpath/services/health_service.dart';
import 'package:vitalpath/services/medicine_logging_service.dart';
import 'package:vitalpath/theme/vitalpath_theme.dart';
import 'package:vitalpath/widgets/bundle_card_widget.dart';
import 'package:vitalpath/widgets/duplicate_log_modal.dart';
import 'package:vitalpath/widgets/glass_card.dart';
import 'package:vitalpath/widgets/smart_timeline_widget.dart';
import 'package:vitalpath/widgets/success_toast.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HomeScreen — The Living Passbook (2026 Design System)
// ─────────────────────────────────────────────────────────────────────────────
// Layout:
//   SliverAppBar (collapsible, frosted glass)
//   SliverToBoxAdapter → _BentoGrid (5 tiles)
//   SliverToBoxAdapter → BundleCard (conditional)
//   SliverPersistentHeader → "Day at a Glance" sticky header
//   SmartTimelineSliverList (lazy glass cards)
//
// 120fps strategy: every animation runs in an isolated RepaintBoundary.
// The _BentoGrid cells each contain their own AnimationController; the
// timeline SliverList is lazily built and each card is a RepaintBoundary.
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  final Stream<int>? stepsStreamOverride;
  const HomeScreen({super.key, this.stepsStreamOverride});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  late final HealthService _healthService;
  late final Stream<int> _stepsStream;

  static final _dayFmt  = DateFormat('EEEE');
  static final _dateFmt = DateFormat('d MMM');

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _healthService = HealthService();
    _stepsStream = widget.stepsStreamOverride ?? _healthService.stepsStream;
    if (widget.stepsStreamOverride == null) _healthService.requestPermissions();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final now = DateTime.now();

    return Scaffold(
      // Dark gradient fills the whole screen — the Bento tiles float on it.
      backgroundColor: VitalPathTheme.deepCharcoal,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // ── Glass App Bar ───────────────────────────────────────────────────
          _GlassAppBar(now: now),

          // ── Bento Grid ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _BentoGrid(stepsStream: _stepsStream),
            ),
          ),

          // ── Bundle Card (Take All) ──────────────────────────────────────────
          const SliverToBoxAdapter(child: BundleCard()),

          // ── Sticky "Day at a Glance" header ────────────────────────────────
          SliverPersistentHeader(
            pinned: true,
            delegate: _TimelineHeaderDelegate(date: now),
          ),

          // ── Smart Timeline ──────────────────────────────────────────────────
          const SmartTimelineSliverList(),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  static String _greeting(DateTime now) {
    final h = now.hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Glass App Bar
// ─────────────────────────────────────────────────────────────────────────────
class _GlassAppBar extends StatelessWidget {
  final DateTime now;
  static final _dayFmt  = DateFormat('EEEE');
  static final _dateFmt = DateFormat('d MMM');

  const _GlassAppBar({required this.now});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return SliverAppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      pinned: true,
      expandedHeight: 100,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: Container(
          decoration: const BoxDecoration(gradient: VitalPathTheme.darkGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_greeting(now)} 👋',
                        style: VitalPathTheme.bodyMedium.copyWith(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Your Passbook',
                        style: VitalPathTheme.headlineLarge.copyWith(
                          color: Colors.white,
                          fontSize: 24,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Date pill
                  GlassCard.dark(
                    borderRadius: BorderRadius.circular(20),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today_rounded,
                            size: 12,
                            color: VitalPathTheme.electricTeal),
                        const SizedBox(width: 6),
                        Text(
                          '${_dayFmt.format(now)}, ${_dateFmt.format(now)}',
                          style: VitalPathTheme.labelLarge.copyWith(
                            color: VitalPathTheme.electricTeal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      // Collapsed state — frosted glass bar
      title: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Text(
            'Passbook',
            style: VitalPathTheme.headlineMedium.copyWith(
              color: Colors.white,
              fontSize: 18,
            ),
          ),
        ),
      ),
      centerTitle: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined,
              color: Colors.white, size: 22),
          onPressed: () => HapticFeedback.lightImpact(),
        ),
      ],
    );

  }

  static String _greeting(DateTime now) {
    final h = now.hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bento Grid — 5-tile layout
// ─────────────────────────────────────────────────────────────────────────────
class _BentoGrid extends StatelessWidget {
  final Stream<int> stepsStream;
  const _BentoGrid({required this.stepsStream});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Tile 1: Step Progress (Large, full-width) ────────────────────────
        RepaintBoundary(
          child: _StepGaugeTile(stepsStream: stepsStream),
        ),
        const SizedBox(height: 10),

        // ── Tiles 2 & 3: Next Dose + Next Meal (Medium row) ─────────────────
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: RepaintBoundary(child: _NextDoseTile())),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: RepaintBoundary(child: _NextMealTile())),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ── Tiles 4 & 5: Next Appointment + Wellness Score (Small row) ───────
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: RepaintBoundary(child: _NextAppointmentTile()),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RepaintBoundary(
                  child: _WellnessScoreTile(stepsStream: stepsStream),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile 1 — Step Gauge (Large, full-width)
// 120fps: CustomPainter isolated in RepaintBoundary
// ─────────────────────────────────────────────────────────────────────────────
class _StepGaugeTile extends StatefulWidget {
  final Stream<int> stepsStream;
  const _StepGaugeTile({required this.stepsStream});

  @override
  State<_StepGaugeTile> createState() => _StepGaugeTileState();
}

class _StepGaugeTileState extends State<_StepGaugeTile>
    with SingleTickerProviderStateMixin {
  static const _goal = HealthService.defaultStepGoal;
  late final AnimationController _ctrl;
  late Animation<double> _anim;
  double _prev = 0.0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _anim = Tween<double>(begin: 0.0, end: 0.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    _anim = Tween<double>(begin: _prev, end: target)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl
      ..reset()
      ..forward();
    _prev = target;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: widget.stepsStream,
      initialData: 0,
      builder: (_, snap) {
        final steps   = snap.data ?? 0;
        final ratio   = (steps / _goal).clamp(0.0, 1.0);
        final goalMet = steps >= _goal;
        _animateTo(ratio);

        return GlassCard.dark(
          borderRadius: BorderRadius.circular(22),
          padding: const EdgeInsets.all(20),
          boxShadow: VitalPathTheme.tealGlowShadow(intensity: 0.5),
          child: Row(
            children: [
              // Circular gauge
              AnimatedBuilder(
                animation: _anim,
                builder: (_, __) => CustomPaint(
                  size: const Size(110, 110),
                  painter: _GaugePainter(progress: _anim.value, goalMet: goalMet),
                  child: SizedBox(
                    width: 110,
                    height: 110,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _fmt(steps),
                            style: VitalPathTheme.bentoMetric.copyWith(
                              color: Colors.white,
                              fontSize: 22,
                            ),
                          ),
                          Text(
                            'steps',
                            style: VitalPathTheme.bentoLabel.copyWith(
                              color: Colors.white.withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Variable typography: label = light, metric = heavy
                    Text(
                      goalMet ? 'Goal Reached!' : 'Daily Step Goal',
                      style: VitalPathTheme.bodyMedium.copyWith(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w400, // light label
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_fmt(steps)} / ${_fmt(_goal)}',
                      style: VitalPathTheme.headlineMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800, // heavy metric
                      ),
                    ),
                    const SizedBox(height: 12),
                    AnimatedBuilder(
                      animation: _anim,
                      builder: (_, __) => ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _anim.value,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.12),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            goalMet
                                ? Colors.white
                                : VitalPathTheme.electricTeal,
                          ),
                          minHeight: 5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      goalMet
                          ? '+${_fmt(steps - _goal)} bonus steps'
                          : '${_fmt(_goal - steps)} to go',
                      style: VitalPathTheme.bodyMedium.copyWith(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _fmt(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : n.toString();
}

// 120fps CustomPainter for the step arc
class _GaugePainter extends CustomPainter {
  final double progress;
  final bool goalMet;
  const _GaugePainter({required this.progress, required this.goalMet});

  static const _stroke = 9.0;
  static const _start  = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.shortestSide - _stroke) / 2;
    final rect = Rect.fromCircle(center: c, radius: r);

    // Track
    canvas.drawArc(rect, 0, 2 * math.pi, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..color = Colors.white.withValues(alpha: 0.10));

    if (progress <= 0) return;

    final sweep = 2 * math.pi * progress;

    // Arc with gradient
    canvas.drawArc(
      rect, _start, sweep, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          center: Alignment.center,
          startAngle: _start,
          endAngle: _start + sweep,
          colors: goalMet
              ? const [Colors.white, Color(0xFFB2EBF2)]
              : const [VitalPathTheme.electricTeal, VitalPathTheme.clinicalTeal],
        ).createShader(rect),
    );

    // Tip dot
    if (progress > 0.02) {
      final tip = _start + sweep;
      canvas.drawCircle(
        Offset(c.dx + r * math.cos(tip), c.dy + r * math.sin(tip)),
        _stroke / 2,
        Paint()
          ..color = goalMet ? Colors.white : VitalPathTheme.electricTeal,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.progress != progress || old.goalMet != goalMet;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile 2 — Next Dose (Medium)
// Variable typography: dosage = w800 (heavy clinical), label = w400 (light)
// 1-tap Log with glass ripple + celebratory haptic
// ─────────────────────────────────────────────────────────────────────────────
class _NextDoseTile extends StatefulWidget {
  const _NextDoseTile();

  @override
  State<_NextDoseTile> createState() => _NextDoseTileState();
}

class _NextDoseTileState extends State<_NextDoseTile> {
  bool _logging = false;

  Future<void> _log(BuildContext context, TimelineEntry entry) async {
    if (_logging) return;
    setState(() => _logging = true);
    HapticFeedback.selectionClick();

    final provider = context.read<DashboardProvider>();
    try {
      await provider.quickLog(
        entryId: entry.id,
        medicineId: entry.medicineId!,
      );
      if (!mounted) return;
      // Celebratory haptic — the "win" moment
      HapticService().doseLogged();
      SuccessToast.show(
        context,
        medicineName: entry.title,
        dose: entry.subtitle,
      );
    } on DuplicateLogException catch (ex) {
      if (!mounted) return;
      await DuplicateLogModal.show(
        context,
        exception: ex,
        onForceLog: () async {
          await provider.quickLog(
            entryId: entry.id,
            medicineId: entry.medicineId!,
            forceOverride: true,
          );
        },
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not log dose'),
            backgroundColor: VitalPathTheme.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _logging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        // First active medicine entry in today's timeline
        final entry = provider.todayEntries
            .where((e) =>
                e.type == TimelineEntryType.medicine && e.canQuickLog)
            .firstOrNull;

        if (entry == null) {
          return _AllDoneTile();
        }

        final isDueNow = entry.isDueNow;
        final dosage   = entry.subtitle.split('·').first.trim();
        final name     = entry.title;

        return GlassCard.dark(
          borderRadius: BorderRadius.circular(18),
          // Electric teal border glows when the dose is due now
          borderColor: isDueNow
              ? VitalPathTheme.electricTeal.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.12),
          boxShadow: isDueNow
              ? VitalPathTheme.electricGlowShadow(intensity: 0.45)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // State badge
                Row(
                  children: [
                    Icon(
                      Icons.medication_rounded,
                      color: isDueNow
                          ? VitalPathTheme.electricTeal
                          : VitalPathTheme.clinicalTeal,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isDueNow ? 'DUE NOW' : 'NEXT DOSE',
                      style: VitalPathTheme.labelMedium.copyWith(
                        color: isDueNow
                            ? VitalPathTheme.electricTeal
                            : Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                    if (isDueNow) ...[
                      const SizedBox(width: 6),
                      _PulseDot(),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                // Medicine name — light label (w400)
                Text(
                  name,
                  style: VitalPathTheme.bodyMedium.copyWith(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w400, // light = label
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // Dosage — heavy clinical data (w800)
                Text(
                  dosage,
                  style: VitalPathTheme.bentoMetric.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800, // heavy = clinical data
                  ),
                ),
                const Spacer(),
                // 1-tap Log button — glass ripple effect
                _GlassLogButton(
                  logging: _logging,
                  onTap: () => _log(context, entry),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AllDoneTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GlassCard.dark(
      borderRadius: BorderRadius.circular(18),
      borderColor: const Color(0xFF66BB6A).withValues(alpha: 0.4),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_rounded,
              color: Color(0xFF66BB6A), size: 28),
          const SizedBox(height: 8),
          Text(
            'All doses\ntaken!',
            style: VitalPathTheme.headlineMedium.copyWith(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Great job today",
            style: VitalPathTheme.patientData.copyWith(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// Glass Log button: InkWell inside Material creates a localized ripple
// that visually "bounces" off the glass surface on tap.
class _GlassLogButton extends StatelessWidget {
  final bool logging;
  final VoidCallback onTap;

  const _GlassLogButton({required this.logging, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: VitalPathTheme.electricTeal.withValues(alpha: 0.15),
          child: InkWell(
            onTap: logging ? null : onTap,
            // Localized glassmorphic ripple — splashes within the tile bounds
            splashColor: VitalPathTheme.electricTeal.withValues(alpha: 0.35),
            highlightColor: VitalPathTheme.electricTeal.withValues(alpha: 0.1),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: VitalPathTheme.electricTeal.withValues(alpha: 0.35),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: logging
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: VitalPathTheme.electricTeal,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add_circle_rounded,
                              size: 16,
                              color: VitalPathTheme.electricTeal),
                          const SizedBox(width: 6),
                          Text(
                            'Log Dose',
                            // Variable typography: CTA = w900
                            style: VitalPathTheme.ctaPrimary.copyWith(
                              color: VitalPathTheme.electricTeal,
                              fontSize: 14,
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

// Pulse dot for "Due Now" state
class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _a = Tween<double>(begin: 0.3, end: 1.0)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (_, __) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: VitalPathTheme.electricTeal.withValues(alpha: _a.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile 3 — Next Meal (Medium)
// ─────────────────────────────────────────────────────────────────────────────
class _NextMealTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GlassCard.dark(
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant_rounded,
                  color: Color(0xFFFFA726), size: 16),
              const SizedBox(width: 6),
              Text(
                'NEXT MEAL',
                style: VitalPathTheme.labelMedium.copyWith(
                  color: const Color(0xFFFFA726),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Label — light weight
          Text(
            'Lunch',
            style: VitalPathTheme.bodyMedium.copyWith(
              color: Colors.white.withValues(alpha: 0.5),
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 2),
          // Time — heavy metric
          Text(
            '1:00 PM',
            style: VitalPathTheme.bentoMetric.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Text(
            'Food log\ncoming soon',
            style: VitalPathTheme.bodyMedium.copyWith(
              color: Colors.white.withValues(alpha: 0.25),
              fontSize: 10,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile 4 — Next Appointment (Small)
// ─────────────────────────────────────────────────────────────────────────────
class _NextAppointmentTile extends StatelessWidget {
  static final _fmt = DateFormat('h:mm a');

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        final appt = provider.todayEntries
            .where((e) => e.type == TimelineEntryType.appointment && !e.isCompleted)
            .firstOrNull;

        return GlassCard.dark(
          borderRadius: BorderRadius.circular(18),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.event_rounded,
                      color: Color(0xFF40C4FF), size: 14),
                  const SizedBox(width: 5),
                  Text(
                    'APPOINTMENT',
                    style: VitalPathTheme.labelMedium
                        .copyWith(color: const Color(0xFF40C4FF)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (appt != null) ...[
                Text(
                  appt.title,
                  style: VitalPathTheme.bodyMedium.copyWith(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w400, // light label
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _fmt.format(appt.scheduledAt),
                  style: VitalPathTheme.bentoMetric.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800, // heavy metric
                    fontSize: 17,
                  ),
                ),
              ] else ...[
                Text(
                  'No appointments\nscheduled today',
                  style: VitalPathTheme.bodyMedium.copyWith(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile 5 — Daily Wellness Score (Small)
// 120fps mini arc via CustomPainter
// ─────────────────────────────────────────────────────────────────────────────
class _WellnessScoreTile extends StatefulWidget {
  final Stream<int> stepsStream;
  const _WellnessScoreTile({required this.stepsStream});

  @override
  State<_WellnessScoreTile> createState() => _WellnessScoreTileState();
}

class _WellnessScoreTileState extends State<_WellnessScoreTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _anim;
  double _prev = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _anim = Tween<double>(begin: 0, end: 0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _animateTo(double v) {
    _anim = Tween<double>(begin: _prev, end: v)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl..reset()..forward();
    _prev = v;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        return StreamBuilder<int>(
          stream: widget.stepsStream,
          initialData: 0,
          builder: (_, snap) {
            final steps   = snap.data ?? 0;
            final score   = _computeScore(provider, steps);
            _animateTo(score / 100.0);

            return GlassCard.dark(
              borderRadius: BorderRadius.circular(18),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.insights_rounded,
                          color: VitalPathTheme.verifiedGold, size: 14),
                      const SizedBox(width: 5),
                      Text(
                        'WELLNESS',
                        style: VitalPathTheme.labelMedium
                            .copyWith(color: VitalPathTheme.verifiedGold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _anim,
                        builder: (_, __) => CustomPaint(
                          size: const Size(60, 60),
                          painter: _MiniArcPainter(progress: _anim.value),
                          child: SizedBox(
                            width: 60,
                            height: 60,
                            child: Center(
                              child: Text(
                                '${score.round()}',
                                style: VitalPathTheme.bentoMetric.copyWith(
                                  color: Colors.white,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    'out of 100',
                    style: VitalPathTheme.patientData.copyWith(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Composite score: steps (40pts) + medicine adherence (40pts) + base (20pts)
  static double _computeScore(DashboardProvider p, int steps) {
    const goal = HealthService.defaultStepGoal;
    final stepPts = (steps / goal).clamp(0.0, 1.0) * 40;
    final total   = p.totalTodayCount;
    final medPts  = total == 0
        ? 20.0
        : (p.completedTodayCount / total).clamp(0.0, 1.0) * 40;
    return (stepPts + medPts + 20).clamp(0.0, 100.0);
  }
}

class _MiniArcPainter extends CustomPainter {
  final double progress;
  const _MiniArcPainter({required this.progress});

  static const _stroke = 6.0;
  static const _start  = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final c    = Offset(size.width / 2, size.height / 2);
    final r    = (size.shortestSide - _stroke) / 2;
    final rect = Rect.fromCircle(center: c, radius: r);

    canvas.drawArc(rect, 0, 2 * math.pi, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..color = Colors.white.withValues(alpha: 0.08));

    if (progress <= 0) return;
    final sweep = 2 * math.pi * progress;
    canvas.drawArc(
      rect, _start, sweep, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          center: Alignment.center,
          startAngle: _start,
          endAngle: _start + sweep,
          colors: const [VitalPathTheme.verifiedGold, Color(0xFFFFF176)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_MiniArcPainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sticky Timeline Header
// ─────────────────────────────────────────────────────────────────────────────
class _TimelineHeaderDelegate extends SliverPersistentHeaderDelegate {
  final DateTime date;
  static final _fmt = DateFormat('EEEE, d MMM');
  const _TimelineHeaderDelegate({required this.date});

  @override double get minExtent => 52;
  @override double get maxExtent => 52;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          color: VitalPathTheme.deepCharcoal.withValues(alpha: 0.85),
          child: Column(
            children: [
              if (overlapsContent)
                Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        "Day at a Glance",
                        style: VitalPathTheme.headlineMedium.copyWith(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      GlassCard.dark(
                        borderRadius: BorderRadius.circular(20),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        child: Text(
                          _fmt.format(date),
                          style: VitalPathTheme.labelMedium.copyWith(
                            color: VitalPathTheme.electricTeal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_TimelineHeaderDelegate old) => old.date.day != date.day;
}
