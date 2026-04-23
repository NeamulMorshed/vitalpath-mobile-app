/// activity_screen.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Activity & Wellness — main screen with split Steps / Workouts view.
///
/// Blueprint §1.1 / §1.2 / §4 / §7:
///   "Create the main Activity screen with a split view: 'Daily Steps'
///    (Passive) and 'Workouts/GPS Walks' (Active)."
///
/// Layout (NestedScrollView — shared momentum with inner tab content):
///   ┌──────────────────────────────────────────────┐
///   │  SliverAppBar: dark gradient, collapsible     │
///   │    Step ring (120fps) + quick stats           │
///   ├──────────────────────────────────────────────┤
///   │  Pinned TabBar: Steps │ Workouts              │
///   ├──────────────────────────────────────────────┤
///   │  TabBarView                                   │
///   │   Steps tab:                                  │
///   │     • 15-min sync status                      │
///   │     • 4-stat metric row                       │
///   │     • 7-day bar chart                         │
///   │   Workouts tab:                               │
///   │     • Prescribed pinned cards (isVerified)    │
///   │     • Start Walk CTA                          │
///   │     • Walk history cards                      │
///   └──────────────────────────────────────────────┘
///
/// 120fps strategy:
///   • [NestedScrollView] with [BouncingScrollPhysics] for natural deceleration.
///   • Step ring: [RepaintBoundary] + [AnimatedBuilder] inside [StepGoalWidget].
///   • Weekly bar chart: [CustomPainter] + [shouldRepaint] value check.
///   • Each walk history card in a [RepaintBoundary].
///   • [Consumer<ActivityProvider>] scoped tightly — only the widget that
///     needs to repaint rebuilds.
///   • Celebration overlay: [OverlayEntry] above the entire nav stack — does
///     not trigger any rebuild in the screen widget tree.
/// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import 'package:vitalpath/models/activity_model.dart';
import 'package:vitalpath/models/gps_walk_session.dart';
import 'package:vitalpath/providers/activity_provider.dart';
import 'package:vitalpath/screens/walk_screen.dart';
import 'package:vitalpath/services/haptic_service.dart';
import 'package:vitalpath/services/health_service.dart';
import 'package:vitalpath/widgets/celebration_overlay.dart';
import 'package:vitalpath/widgets/step_goal_widget.dart';

class ActivityScreen extends StatefulWidget {
  final String patientId;
  final Stream<int>? stepsStreamOverride; // for testing

  const ActivityScreen({
    super.key,
    required this.patientId,
    this.stepsStreamOverride,
  });

  static PageRoute<void> route(String patientId) {
    return PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => ChangeNotifierProvider(
        create: (_) => ActivityProvider(),
        child: ActivityScreen(patientId: patientId),
      ),
      transitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    );
  }

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _tabCtrl;
  late final HealthService _healthService;
  late final Stream<int> _stepsStream;
  OverlayEntry? _celebrationEntry;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _healthService = HealthService();

    _stepsStream = widget.stepsStreamOverride ??
        _healthService.stepsStream;
    _healthService.requestPermissions();

    // Start step tracking + 15-min background refresh.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ActivityProvider>();
      provider.startStepTracking();
      provider.loadData(widget.patientId);
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _celebrationEntry?.remove();
    super.dispose();
  }

  // ── Celebration trigger ────────────────────────────────────────────────────
  void _triggerCelebration() {
    if (_celebrationEntry != null) return;
    HapticService().goalSuccess();

    _celebrationEntry = CelebrationOverlay.show(context);

    // Entry removes itself after animation; null our reference.
    Future.delayed(const Duration(milliseconds: 2700), () {
      _celebrationEntry = null;
    });

    context.read<ActivityProvider>().markGoalCelebrated();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Watch for goal celebration — fires at most once per session.
    final provider = context.watch<ActivityProvider>();
    if (provider.shouldCelebrate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _triggerCelebration();
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: NestedScrollView(
        physics: const BouncingScrollPhysics(),
        headerSliverBuilder: (context, innerScrolled) => [
          _buildSliverHeader(context, innerScrolled),
        ],
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            _StepsTab(
              patientId: widget.patientId,
              stepsStream: _stepsStream,
            ),
            _WorkoutsTab(patientId: widget.patientId),
          ],
        ),
      ),
    );
  }

  SliverAppBar _buildSliverHeader(
      BuildContext context, bool innerScrolled) {
    return SliverAppBar(
      expandedHeight: 260,
      collapsedHeight: 60,
      pinned: true,
      backgroundColor: const Color(0xFF1A1A2E),
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            size: 20, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: AnimatedOpacity(
        opacity: innerScrolled ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 180),
        child: const Text(
          'Activity',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: _buildHeaderBackground(),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(46),
        child: _buildTabBar(),
      ),
    );
  }

  Widget _buildHeaderBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 60),
          child: StepGoalWidget(
            stepsStream: _stepsStream,
            goal: HealthService.defaultStepGoal,
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: const Color(0xFF1A1A2E),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: TabBar(
          controller: _tabCtrl,
          indicator: BoxDecoration(
            color: const Color(0xFF00897B),
            borderRadius: BorderRadius.circular(8),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'Daily Steps'),
            Tab(text: 'Workouts'),
          ],
        ),
      ),
    );
  }
}

// ── Steps tab ─────────────────────────────────────────────────────────────────
class _StepsTab extends StatelessWidget {
  final String patientId;
  final Stream<int> stepsStream;

  const _StepsTab({
    required this.patientId,
    required this.stepsStream,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ActivityProvider>(
      builder: (context, provider, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          physics: const NeverScrollableScrollPhysics(),
          children: [
            // ── 15-min sync status ───────────────────────────────────────────
            _SyncStatusBar(steps: provider.steps),
            const SizedBox(height: 16),

            // ── 4-stat row ───────────────────────────────────────────────────
            _StepMetricsRow(steps: provider.steps),
            const SizedBox(height: 20),

            // ── Weekly bar chart header ──────────────────────────────────────
            Row(
              children: [
                const Text(
                  'This Week',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('d MMM').format(
                    DateTime.now().subtract(const Duration(days: 6))),
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF9E9E9E)),
                ),
                const Text(
                  ' – ',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
                ),
                Text(
                  DateFormat('d MMM').format(DateTime.now()),
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF9E9E9E)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Weekly bar chart ─────────────────────────────────────────────
            RepaintBoundary(
              child: Container(
                height: 160,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x07000000),
                        blurRadius: 8,
                        offset: Offset(0, 3)),
                  ],
                ),
                child: _WeeklyStepChart(
                  todaySteps: provider.steps,
                  goal: HealthService.defaultStepGoal,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── 15-min sync status bar ────────────────────────────────────────────────────
class _SyncStatusBar extends StatelessWidget {
  final int steps;
  const _SyncStatusBar({required this.steps});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final minsPastQuarter = now.minute % 15;
    final nextRefreshIn = 15 - minsPastQuarter;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8E8EE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_rounded,
              size: 15, color: Color(0xFF00897B)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'HealthKit live · background sync in ${nextRefreshIn}m',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF9E9E9E)),
            ),
          ),
          Text(
            '${_fmt(steps)} today',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF00897B),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }
}

// ── Step metrics row ──────────────────────────────────────────────────────────
class _StepMetricsRow extends StatelessWidget {
  final int steps;
  const _StepMetricsRow({required this.steps});

  @override
  Widget build(BuildContext context) {
    // Rough estimates from step count.
    final distanceKm = steps * 0.000762; // avg stride 0.762 m
    final calories = (steps * 0.04).round();
    final activeMin = (steps / 100).round();
    final progress =
        ((steps / HealthService.defaultStepGoal) * 100).round();

    return Row(
      children: [
        _MetricCard(
          icon: Icons.directions_walk_rounded,
          value: distanceKm < 1
              ? '${(distanceKm * 1000).toInt()} m'
              : '${distanceKm.toStringAsFixed(1)} km',
          label: 'Distance',
          color: const Color(0xFF00897B),
        ),
        const SizedBox(width: 10),
        _MetricCard(
          icon: Icons.local_fire_department_rounded,
          value: '$calories',
          label: 'Calories',
          color: const Color(0xFFE65100),
        ),
        const SizedBox(width: 10),
        _MetricCard(
          icon: Icons.timer_rounded,
          value: '${activeMin}m',
          label: 'Active',
          color: const Color(0xFF1565C0),
        ),
        const SizedBox(width: 10),
        _MetricCard(
          icon: Icons.percent_rounded,
          value: '$progress%',
          label: 'Goal',
          color: const Color(0xFF6A1B9A),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _MetricCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
                color: Color(0x07000000),
                blurRadius: 8,
                offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 10, color: Color(0xFF9E9E9E)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Weekly step bar chart ─────────────────────────────────────────────────────
class _WeeklyStepChart extends StatelessWidget {
  final int todaySteps;
  final int goal;

  const _WeeklyStepChart({
    required this.todaySteps,
    required this.goal,
  });

  @override
  Widget build(BuildContext context) {
    // Simulate a plausible 7-day history seeded from today's steps.
    // Real implementation loads from Firestore health_logs.
    final rng = math.Random(DateTime.now().weekday);
    final days = <int>[
      (goal * (0.4 + rng.nextDouble() * 0.6)).round(),
      (goal * (0.3 + rng.nextDouble() * 0.7)).round(),
      (goal * (0.5 + rng.nextDouble() * 0.5)).round(),
      (goal * (0.2 + rng.nextDouble() * 0.8)).round(),
      (goal * (0.6 + rng.nextDouble() * 0.4)).round(),
      (goal * (0.4 + rng.nextDouble() * 0.6)).round(),
      todaySteps, // today — live value
    ];
    final labels = _last7DayLabels();
    final maxSteps =
        days.reduce(math.max).clamp(goal, goal * 2).toDouble();

    return CustomPaint(
      painter: _BarChartPainter(
        days: days,
        labels: labels,
        goal: goal,
        maxSteps: maxSteps,
      ),
    );
  }

  static List<String> _last7DayLabels() {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return i == 6 ? 'Today' : DateFormat('E').format(d);
    });
  }
}

class _BarChartPainter extends CustomPainter {
  final List<int> days;
  final List<String> labels;
  final int goal;
  final double maxSteps;

  const _BarChartPainter({
    required this.days,
    required this.labels,
    required this.goal,
    required this.maxSteps,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 7;
    final barWidth = size.width / barCount * 0.55;
    final spacing = size.width / barCount;
    const labelH = 20.0;
    final chartH = size.height - labelH;
    final goalY = chartH * (1 - goal / maxSteps);

    // ── Goal line (dashed) ────────────────────────────────────────────────
    _drawDashedLine(
      canvas,
      Offset(0, goalY),
      Offset(size.width, goalY),
      const Color(0xFF00897B),
    );

    final labelPainter = TextPainter(
        textDirection: TextDirection.ltr);

    for (var i = 0; i < barCount; i++) {
      final x = spacing * i + spacing / 2;
      final steps = days[i];
      final barH = (chartH * (steps / maxSteps)).clamp(4.0, chartH);
      final top = chartH - barH;
      final isToday = i == 6;
      final meetsGoal = steps >= goal;

      // ── Bar ───────────────────────────────────────────────────────────
      final rrect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x - barWidth / 2, top, barWidth, barH),
        topLeft: const Radius.circular(6),
        topRight: const Radius.circular(6),
      );

      canvas.drawRRect(
        rrect,
        Paint()
          ..color = isToday
              ? (meetsGoal
                  ? const Color(0xFF00897B)
                  : const Color(0xFF26C6DA))
              : meetsGoal
                  ? const Color(0xFF80CBC4)
                  : const Color(0xFFE0E0E0),
      );

      // ── Day label ─────────────────────────────────────────────────────
      labelPainter
        ..text = TextSpan(
          text: labels[i],
          style: TextStyle(
            fontSize: 10,
            fontWeight:
                isToday ? FontWeight.w700 : FontWeight.w400,
            color: isToday
                ? const Color(0xFF1A1A2E)
                : const Color(0xFF9E9E9E),
          ),
        )
        ..layout();
      labelPainter.paint(
        canvas,
        Offset(x - labelPainter.width / 2, size.height - labelH + 4),
      );
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.days.last != days.last;
}

// ── Workouts tab ──────────────────────────────────────────────────────────────
class _WorkoutsTab extends StatelessWidget {
  final String patientId;
  const _WorkoutsTab({required this.patientId});

  @override
  Widget build(BuildContext context) {
    return Consumer<ActivityProvider>(
      builder: (context, provider, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          physics: const NeverScrollableScrollPhysics(),
          children: [
            // ── Prescribed activities (pinned, locked) ───────────────────────
            if (provider.prescribed.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.verified_rounded,
                label: 'Doctor Prescribed',
                iconColor: const Color(0xFF00897B),
              ),
              const SizedBox(height: 8),
              ...provider.prescribed.map((activity) => RepaintBoundary(
                    child: _PrescribedActivityCard(
                      activity: activity,
                      onMarkComplete: activity.isCompleted
                          ? null
                          : () => provider.markPrescribedComplete(
                              activity.id!),
                    ),
                  )),
              const SizedBox(height: 20),
            ],

            // ── Start walk CTA ───────────────────────────────────────────────
            _SectionHeader(
              icon: Icons.directions_walk_rounded,
              label: 'GPS Walk',
              iconColor: const Color(0xFF1A1A2E),
            ),
            const SizedBox(height: 10),
            _StartWalkCard(
              patientId: patientId,
              isActive: provider.isWalking,
              isStarting: provider.isStartingWalk,
            ),
            const SizedBox(height: 20),

            // ── Walk history ─────────────────────────────────────────────────
            if (provider.walkHistory.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.history_rounded,
                label: 'Recent Walks',
                iconColor: const Color(0xFF1A1A2E),
              ),
              const SizedBox(height: 8),
              ...provider.walkHistory.map((session) => RepaintBoundary(
                    child: _WalkHistoryCard(session: session),
                  )),
            ],

            if (provider.walkHistory.isEmpty &&
                provider.prescribed.isEmpty)
              _EmptyWorkoutsState(patientId: patientId),
          ],
        );
      },
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: iconColor),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
          ),
        ),
      ],
    );
  }
}

// ── Prescribed activity card ──────────────────────────────────────────────────
class _PrescribedActivityCard extends StatelessWidget {
  final ActivityModel activity;
  final VoidCallback? onMarkComplete;

  const _PrescribedActivityCard({
    required this.activity,
    required this.onMarkComplete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFF00897B).withOpacity(0.2), width: 1.5),
        boxShadow: const [
          BoxShadow(
              color: Color(0x07000000),
              blurRadius: 8,
              offset: Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6F7F4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.medical_services_rounded,
                      size: 18, color: Color(0xFF00897B)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activity.protocolName ??
                            activity.activityType.label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      Text(
                        'Dr. ${activity.prescribingDoctorName ?? 'Unknown'}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9E9E9E)),
                      ),
                    ],
                  ),
                ),
                // Lock badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6F7F4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_rounded,
                          size: 10, color: Color(0xFF00897B)),
                      SizedBox(width: 4),
                      Text(
                        'Verified',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF00897B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Details row ───────────────────────────────────────────────────
            Row(
              children: [
                _PrescriptionDetail(
                  icon: Icons.timer_rounded,
                  text: '${activity.durationMinutes} min',
                ),
                const SizedBox(width: 16),
                _PrescriptionDetail(
                  icon: Icons.speed_rounded,
                  text: activity.intensity.name,
                ),
                if (activity.distanceKm != null) ...[
                  const SizedBox(width: 16),
                  _PrescriptionDetail(
                    icon: Icons.straighten_rounded,
                    text:
                        '${activity.distanceKm!.toStringAsFixed(1)} km',
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // ── Complete / Done button ────────────────────────────────────────
            activity.isCompleted
                ? Row(
                    children: const [
                      Icon(Icons.check_circle_rounded,
                          size: 18, color: Color(0xFF00897B)),
                      SizedBox(width: 8),
                      Text(
                        'Marked as done',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF00897B),
                        ),
                      ),
                    ],
                  )
                : SizedBox(
                    width: double.infinity,
                    height: 48, // 48dp minimum touch target
                    child: OutlinedButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        onMarkComplete?.call();
                      },
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text(
                        'Mark as Completed',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00897B),
                        side: const BorderSide(
                            color: Color(0xFF00897B), width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _PrescriptionDetail extends StatelessWidget {
  final IconData icon;
  final String text;
  const _PrescriptionDetail({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: const Color(0xFF9E9E9E)),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF555566))),
      ],
    );
  }
}

// ── Start walk card ───────────────────────────────────────────────────────────
class _StartWalkCard extends StatelessWidget {
  final String patientId;
  final bool isActive;
  final bool isStarting;

  const _StartWalkCard({
    required this.patientId,
    required this.isActive,
    required this.isStarting,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000),
              blurRadius: 14,
              offset: Offset(0, 5)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF00897B).withOpacity(0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.directions_walk_rounded,
                size: 28, color: Color(0xFF00897B)),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GPS Walk',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Real-time map · KM haptics · Auto-logged',
                  style: TextStyle(
                      fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 48, // 48dp minimum touch target
            child: FilledButton(
              onPressed:
                  (isStarting || isActive) ? null : () => _start(context),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
                disabledBackgroundColor:
                    const Color(0xFF00897B).withOpacity(0.4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: isStarting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(
                      isActive ? 'Active' : 'Start',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _start(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final provider = context.read<ActivityProvider>();
    final started = await provider.startWalk(patientId);
    if (started && context.mounted) {
      await Navigator.of(context).push(WalkScreen.route());
    }
  }
}

// ── Walk history card ─────────────────────────────────────────────────────────
class _WalkHistoryCard extends StatelessWidget {
  final GpsWalkSession session;
  static final _dateFmt = DateFormat('EEE d MMM · h:mm a');

  const _WalkHistoryCard({required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!, width: 1),
        boxShadow: const [
          BoxShadow(
              color: Color(0x07000000),
              blurRadius: 8,
              offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE6F7F4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              session.isGpsArchived
                  ? Icons.archive_rounded
                  : Icons.directions_walk_rounded,
              size: 22,
              color: const Color(0xFF00897B),
            ),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.formattedDistance,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${session.formattedDuration} · ${session.formattedPace}',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF9E9E9E)),
                ),
                const SizedBox(height: 2),
                Text(
                  _dateFmt.format(session.startedAt.toLocal()),
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFFBDBDBD)),
                ),
              ],
            ),
          ),

          // KM badges + calories
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (session.kmMilestonesReached > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6F7F4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${session.kmMilestonesReached} km',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF00897B),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                '${session.caloriesBurned.toInt()} kcal',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF9E9E9E)),
              ),
              if (session.isGpsArchived)
                const Text(
                  'path archived',
                  style: TextStyle(
                      fontSize: 10, color: Color(0xFFBDBDBD)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Empty workouts state ──────────────────────────────────────────────────────
class _EmptyWorkoutsState extends StatelessWidget {
  final String patientId;
  const _EmptyWorkoutsState({required this.patientId});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFE6F7F4),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.directions_walk_rounded,
                  size: 36, color: Color(0xFF00897B)),
            ),
            const SizedBox(height: 18),
            const Text(
              'No Workouts Yet',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap \'Start Walk\' to log your first GPS walk.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: Color(0xFF9E9E9E), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dashed line helper ────────────────────────────────────────────────────────
// Flutter's Canvas has no native dash support; we draw individual segments.
void _drawDashedLine(
  Canvas canvas,
  Offset start,
  Offset end,
  Color color, {
  double dashWidth = 4,
  double gapWidth = 4,
  double strokeWidth = 1,
}) {
  final paint = Paint()
    ..color = color.withOpacity(0.35)
    ..strokeWidth = strokeWidth
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  final dx = end.dx - start.dx;
  final dy = end.dy - start.dy;
  final totalLen = math.sqrt(dx * dx + dy * dy);
  final step = dashWidth + gapWidth;
  final count = (totalLen / step).floor();
  final ux = dx / totalLen;
  final uy = dy / totalLen;

  for (var i = 0; i < count; i++) {
    final s = start + Offset(ux, uy) * (i * step);
    final e = s + Offset(ux, uy) * dashWidth;
    canvas.drawLine(s, e, paint);
  }
}
