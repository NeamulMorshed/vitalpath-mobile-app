/// home_screen.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// The Living Passbook — VitalPath's primary Home / Dashboard screen.
///
/// Blueprint §3.1 / §7:
///   "A vertical timeline of today's health events.  Pull data from the
///    Medication, Nutrition, and Appointment modules.  Upcoming tasks must be
///    Elevated.  Completed tasks must move to a Faded state.  Real-Time
///    Activity Widget for Step Goals."
///
/// Layout (CustomScrollView — single scroll physics, no nested scrollers):
///   ┌──────────────────────────────────────────┐
///   │  SliverAppBar (greeting + date)           │  ← collapsible, pinned
///   ├──────────────────────────────────────────┤
///   │  SliverToBoxAdapter: StepGoalWidget       │  ← real-time ring
///   ├──────────────────────────────────────────┤
///   │  SliverToBoxAdapter: Summary strip        │  ← completion ratio
///   ├──────────────────────────────────────────┤
///   │  SliverPersistentHeader: "Today's         │  ← sticky section header
///   │    Passbook" + date chip                  │
///   ├──────────────────────────────────────────┤
///   │  SmartTimelineSliverList                  │  ← lazy, RepaintBoundary
///   │    • dueNow cards (pulsing)               │
///   │    • upcoming cards (elevated)            │
///   │    • missed cards (muted)                 │
///   │    • completed cards (faded)              │
///   └──────────────────────────────────────────┘
///
/// 120fps strategy:
///   • [BouncingScrollPhysics] for natural deceleration.
///   • [SliverPersistentHeader] (pinned) — no layout thrashing on scroll.
///   • [SmartTimelineSliverList] uses lazy [SliverChildBuilderDelegate].
///   • [RepaintBoundary] on each timeline card (inside the widget).
///   • [StepGoalWidget] wrapped in its own [RepaintBoundary] (inside widget).
///   • [Consumer<DashboardProvider>] scoped tightly — only timeline rebuilds
///     when entries change; AppBar/step widget do not.
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:vitalpath/providers/dashboard_provider.dart';
import 'package:vitalpath/screens/notification_settings_screen.dart';
import 'package:vitalpath/theme/vitalpath_theme.dart';
import 'package:vitalpath/services/health_service.dart';
import 'package:vitalpath/widgets/bundle_card_widget.dart';
import 'package:vitalpath/widgets/smart_timeline_widget.dart';
import 'package:vitalpath/widgets/step_goal_widget.dart';

class HomeScreen extends StatefulWidget {
  /// Pass a mock stream for dev builds; real stream in production.
  final Stream<int>? stepsStreamOverride;
  final VoidCallback? onNavigateToCare;

  const HomeScreen({super.key, this.stepsStreamOverride, this.onNavigateToCare});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  late final HealthService _healthService;
  late final Stream<int> _stepsStream;

  static final _dayFmt = DateFormat('EEEE');
  static final _dateFmt = DateFormat('d MMMM yyyy');

  @override
  bool get wantKeepAlive => true; // keep alive in bottom-nav tab stack

  @override
  void initState() {
    super.initState();
    _healthService = HealthService();

    if (widget.stepsStreamOverride != null) {
      _stepsStream = widget.stepsStreamOverride!;
    } else {
      // Request permissions, then expose the live stream.
      _stepsStream = _healthService.stepsStream;
      _healthService.requestPermissions();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: VitalPathTheme.lightSurface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // ── Collapsible App Bar ──────────────────────────────────────────
          SliverAppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            pinned: true,
            expandedHeight: 100,
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Greeting
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _greeting(now),
                              style: const TextStyle(
                                fontSize: 13,
                                color: VitalPathTheme.softGrey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Today',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: VitalPathTheme.deepCharcoal,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Date pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6F7F4),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_today_rounded,
                                size: 13, color: Color(0xFF00897B)),
                            const SizedBox(width: 6),
                            Text(
                              '${_dayFmt.format(now)}, ${now.day} ${DateFormat('MMM').format(now)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF00897B),
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
            // Collapsed title
            title: const Text(
              'Today',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: VitalPathTheme.deepCharcoal,
              ),
            ),
            centerTitle: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined,
                    color: VitalPathTheme.deepCharcoal, size: 22),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(_slideRoute());
                },
                tooltip: 'Notifications',
              ),
            ],
          ),

          // ── Step Goal Widget ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
              child: StepGoalWidget(
                stepsStream: _stepsStream,
                goal: HealthService.defaultStepGoal,
              ),
            ),
          ),

          // ── Bundle Card (appears when 2+ doses are due now) ───────────────
          const SliverToBoxAdapter(child: BundleCard()),

          // ── Summary strip (hidden when no tasks exist) ───────────────────
          SliverToBoxAdapter(
            child: Consumer<DashboardProvider>(
              builder: (_, provider, __) {
                if (provider.totalTodayCount == 0) return const SizedBox.shrink();
                return _SummaryStrip(
                  completed: provider.completedTodayCount,
                  total: provider.totalTodayCount,
                  upcoming: provider.upcomingCount,
                  ratio: provider.todayCompletionRatio,
                );
              },
            ),
          ),

          // ── Sticky "Today's Passbook" header ─────────────────────────────
          SliverPersistentHeader(
            pinned: true,
            delegate: _TimelineHeaderDelegate(date: now),
          ),

          // ── Smart Timeline (lazy SliverList) ─────────────────────────────
          SmartTimelineSliverList(onNavigateToCare: widget.onNavigateToCare),

          // ── Bottom padding ───────────────────────────────────────────────
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  static Route<void> _slideRoute() {
    return PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => const NotificationSettingsScreen(),
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  static String _greeting(DateTime now) {
    final hour = now.hour;
    if (hour < 12) return 'Good morning ☀️';
    if (hour < 17) return 'Good afternoon 🌤';
    return 'Good evening 🌙';
  }
}

// ── Summary strip ─────────────────────────────────────────────────────────────
class _SummaryStrip extends StatelessWidget {
  final int completed;
  final int total;
  final int upcoming;
  final double ratio;

  const _SummaryStrip({
    required this.completed,
    required this.total,
    required this.upcoming,
    required this.ratio,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          _StatPill(
            label: 'Done',
            value: '$completed / $total',
            color: const Color(0xFF66BB6A),
            icon: Icons.check_circle_outline_rounded,
          ),
          const SizedBox(width: 10),
          _StatPill(
            label: 'Upcoming',
            value: '$upcoming',
            color: const Color(0xFF1565C0),
            icon: Icons.schedule_rounded,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ProgressPill(ratio: ratio),
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color),
              ),
              Text(
                label,
                style: const TextStyle(
                    fontSize: 10, color: Color(0xFFAAAAAA)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressPill extends StatelessWidget {
  final double ratio;

  const _ProgressPill({required this.ratio});

  @override
  Widget build(BuildContext context) {
    final pct = (ratio * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: VitalPathTheme.tealGlowShadow(intensity: 0.15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$pct%',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF00897B)),
              ),
              const SizedBox(width: 4),
              const Text(
                'today',
                style: TextStyle(fontSize: 10, color: Color(0xFFAAAAAA)),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF00897B)),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sticky timeline header delegate ──────────────────────────────────────────
class _TimelineHeaderDelegate extends SliverPersistentHeaderDelegate {
  final DateTime date;

  static final _dateFmt = DateFormat('EEEE, d MMM');

  const _TimelineHeaderDelegate({required this.date});

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: VitalPathTheme.lightSurface,
      child: Column(
        children: [
          if (overlapsContent)
            Divider(height: 1, color: Colors.grey.shade300),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Row(
                children: [
                  const Text(
                    "Today's Timeline",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: VitalPathTheme.deepCharcoal,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6F7F4),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _dateFmt.format(date),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF00897B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_TimelineHeaderDelegate old) => old.date.day != date.day;
}
