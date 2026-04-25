/// doctor_portal_screen.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Doctor Portal — testable role-gated view for healthcare providers.
///
/// Provides the doctor-side shell: Overview (activity feed), Patients roster,
/// Verification Queue, and Doctor Profile.  All tabs show demo data so the
/// full UX is testable without a live Firestore backend.
///
/// Route: slides up from bottom (modal pattern) to signal a role switch,
/// distinct from the right-slide pattern used for hierarchical drill-downs.
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:vitalpath/models/user_profile_model.dart';
import 'package:vitalpath/services/user_profile_service.dart';
import 'package:vitalpath/theme/vitalpath_theme.dart';

// ── Demo data ─────────────────────────────────────────────────────────────────

class _DemoPatient {
  final String name;
  final String condition;
  final int adherencePct;
  final String lastSync;
  final Color accentColor;
  const _DemoPatient({
    required this.name,
    required this.condition,
    required this.adherencePct,
    required this.lastSync,
    required this.accentColor,
  });
}

class _DemoActivity {
  final String patient;
  final String action;
  final String time;
  final IconData icon;
  final Color color;
  final bool isAlert;
  const _DemoActivity({
    required this.patient,
    required this.action,
    required this.time,
    required this.icon,
    required this.color,
    this.isAlert = false,
  });
}

class _DemoVerification {
  final String patient;
  final String medicine;
  final String dosage;
  final String reportedAt;
  const _DemoVerification({
    required this.patient,
    required this.medicine,
    required this.dosage,
    required this.reportedAt,
  });
}

const _patients = [
  _DemoPatient(
    name: 'Arif Rahman',
    condition: 'Type 2 Diabetes',
    adherencePct: 87,
    lastSync: '2h ago',
    accentColor: Color(0xFF00897B),
  ),
  _DemoPatient(
    name: 'Fatima Begum',
    condition: 'Hypertension',
    adherencePct: 62,
    lastSync: '4h ago',
    accentColor: Color(0xFFFF8F00),
  ),
  _DemoPatient(
    name: 'Karim Chowdhury',
    condition: 'Asthma',
    adherencePct: 94,
    lastSync: '1d ago',
    accentColor: Color(0xFF3D5AFE),
  ),
];

const _activity = [
  _DemoActivity(
    patient: 'Arif Rahman',
    action: 'Missed Metformin 500mg — 8:00 AM dose',
    time: '2h ago',
    icon: Icons.warning_amber_rounded,
    color: Color(0xFFE53935),
    isAlert: true,
  ),
  _DemoActivity(
    patient: 'Fatima Begum',
    action: 'Blood pressure logged: 128/82 mmHg',
    time: '4h ago',
    icon: Icons.favorite_rounded,
    color: Color(0xFF00897B),
  ),
  _DemoActivity(
    patient: 'Karim Chowdhury',
    action: 'Salbutamol 100mcg added — awaiting verification',
    time: '1d ago',
    icon: Icons.medication_rounded,
    color: Color(0xFFFF8F00),
    isAlert: true,
  ),
];

const _verifications = [
  _DemoVerification(
    patient: 'Arif Rahman',
    medicine: 'Metformin',
    dosage: '500mg · Oral',
    reportedAt: '2d ago',
  ),
  _DemoVerification(
    patient: 'Karim Chowdhury',
    medicine: 'Salbutamol',
    dosage: '100mcg · Inhalation',
    reportedAt: '1d ago',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// DoctorPortalScreen
// ─────────────────────────────────────────────────────────────────────────────
class DoctorPortalScreen extends StatefulWidget {
  // null = modal mode (pop on exit); non-null = main-shell mode (custom action)
  final VoidCallback? onExit;
  const DoctorPortalScreen({super.key, this.onExit});

  static Route<void> route() {
    return PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => const DoctorPortalScreen(),
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1.0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  @override
  State<DoctorPortalScreen> createState() => _DoctorPortalScreenState();
}

class _DoctorPortalScreenState extends State<DoctorPortalScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VitalPathTheme.lightSurface,
      body: IndexedStack(
        index: _tab,
        children: [
          _OverviewTab(onGoToPatients: () => setState(() => _tab = 1)),
          const _PatientsTab(),
          const _VerifyTab(),
          _DoctorProfileTab(
            onExit: widget.onExit ?? () => Navigator.of(context).pop(),
            isMainShell: widget.onExit != null,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          HapticFeedback.selectionClick();
          setState(() => _tab = i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Patients',
          ),
          NavigationDestination(
            icon: Icon(Icons.verified_outlined),
            selectedIcon: Icon(Icons.verified_rounded),
            label: 'Verify',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OVERVIEW TAB — stats + live activity feed
// ─────────────────────────────────────────────────────────────────────────────
class _OverviewTab extends StatelessWidget {
  final VoidCallback onGoToPatients;
  const _OverviewTab({required this.onGoToPatients});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverAppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          pinned: true,
          expandedHeight: 110,
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.pin,
            background: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F4FF),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.local_hospital_rounded,
                                  size: 12, color: Color(0xFF3D5AFE)),
                              SizedBox(width: 5),
                              Text(
                                'Doctor Portal · Demo',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF3D5AFE),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Overview',
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
            ),
          ),
          title: const Text(
            'Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: VitalPathTheme.deepCharcoal,
            ),
          ),
          centerTitle: false,
        ),

        // ── Stats row ──────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.people_rounded,
                    iconColor: const Color(0xFF3D5AFE),
                    bgColor: const Color(0xFFF0F4FF),
                    label: 'Patients',
                    value: '3',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    icon: Icons.pending_actions_rounded,
                    iconColor: const Color(0xFFFF8F00),
                    bgColor: const Color(0xFFFFF8E1),
                    label: 'Pending',
                    value: '2',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    icon: Icons.verified_rounded,
                    iconColor: VitalPathTheme.clinicalTeal,
                    bgColor: const Color(0xFFE6F7F4),
                    label: 'Verified',
                    value: '14',
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Activity feed header ───────────────────────────────────────────
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 10),
            child: Text(
              'RECENT ACTIVITY',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: VitalPathTheme.softGrey,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),

        // ── Activity feed items ────────────────────────────────────────────
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _ActivityCard(item: _activity[i]),
            ),
            childCount: _activity.length,
          ),
        ),

        // ── View all patients CTA ──────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: OutlinedButton.icon(
              onPressed: onGoToPatients,
              icon: const Icon(Icons.people_rounded, size: 18),
              label: const Text('View All Patients'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF3D5AFE),
                side: const BorderSide(color: Color(0xFF3D5AFE)),
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final _DemoActivity item;
  const _ActivityCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: item.isAlert
            ? Border.all(
                color: item.color.withValues(alpha: 0.25), width: 1)
            : null,
        boxShadow: VitalPathTheme.cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(item.icon, size: 18, color: item.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.patient,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: VitalPathTheme.deepCharcoal,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.action,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: item.isAlert
                        ? item.color
                        : VitalPathTheme.softGrey,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            item.time,
            style: const TextStyle(
              fontSize: 11,
              color: VitalPathTheme.softGrey,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PATIENTS TAB — demo roster with adherence bars
// ─────────────────────────────────────────────────────────────────────────────
class _PatientsTab extends StatefulWidget {
  const _PatientsTab();

  @override
  State<_PatientsTab> createState() => _PatientsTabState();
}

class _PatientsTabState extends State<_PatientsTab> {
  bool _codeVisible = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VitalPathTheme.lightSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Patients',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: VitalPathTheme.deepCharcoal,
          ),
        ),
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                setState(() => _codeVisible = !_codeVisible);
              },
              icon: Icon(
                _codeVisible
                    ? Icons.visibility_off_rounded
                    : Icons.qr_code_rounded,
                size: 16,
              ),
              label: Text(_codeVisible ? 'Hide Code' : 'Sync Code'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF3D5AFE),
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        physics: const BouncingScrollPhysics(),
        children: [
          // Sync code card (collapsible)
          AnimatedCrossFade(
            firstChild: const SizedBox(height: 0),
            secondChild: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: const Color(0xFF3D5AFE).withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3D5AFE).withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    'Your Sync Code',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: VitalPathTheme.softGrey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'DR-847291',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                      color: Color(0xFF3D5AFE),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Share this code with patients to link their accounts',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, color: VitalPathTheme.softGrey),
                  ),
                ],
              ),
            ),
            crossFadeState: _codeVisible
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 240),
          ),

          // Patient list
          ...List.generate(_patients.length, (i) {
            final p = _patients[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PatientCard(patient: p),
            );
          }),
        ],
      ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  final _DemoPatient patient;
  const _PatientCard({required this.patient});

  Color get _adherenceColor {
    if (patient.adherencePct >= 80) return const Color(0xFF00897B);
    if (patient.adherencePct >= 60) return const Color(0xFFFF8F00);
    return const Color(0xFFE53935);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: VitalPathTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: patient.accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    patient.name.split(' ').map((w) => w[0]).take(2).join(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: patient.accentColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: VitalPathTheme.deepCharcoal,
                      ),
                    ),
                    Text(
                      patient.condition,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: VitalPathTheme.softGrey,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${patient.adherencePct}%',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _adherenceColor,
                    ),
                  ),
                  const Text(
                    'adherence',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: VitalPathTheme.softGrey,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Adherence progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: patient.adherencePct / 100,
              minHeight: 5,
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(_adherenceColor),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.sync_rounded,
                  size: 13, color: VitalPathTheme.softGrey),
              const SizedBox(width: 4),
              Text(
                'Last sync ${patient.lastSync}',
                style: const TextStyle(
                    fontSize: 12, color: VitalPathTheme.softGrey),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F7F4),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Active',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF00897B),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VERIFICATION QUEUE TAB — interactive verify / reject
// ─────────────────────────────────────────────────────────────────────────────
class _VerifyTab extends StatefulWidget {
  const _VerifyTab();

  @override
  State<_VerifyTab> createState() => _VerifyTabState();
}

class _VerifyTabState extends State<_VerifyTab> {
  final _verified = <int>{};
  final _rejected = <int>{};

  @override
  Widget build(BuildContext context) {
    final pending = _verifications
        .asMap()
        .entries
        .where((e) => !_verified.contains(e.key) && !_rejected.contains(e.key))
        .toList();

    return Scaffold(
      backgroundColor: VitalPathTheme.lightSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            const Text(
              'Verify',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: VitalPathTheme.deepCharcoal,
              ),
            ),
            const SizedBox(width: 8),
            if (pending.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8F00),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${pending.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        physics: const BouncingScrollPhysics(),
        children: [
          // Clinical lock explainer
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F7F4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_rounded, size: 16, color: Color(0xFF00897B)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Verifying a prescription applies Clinical Lock — the patient '
                    'can view but not edit or delete the record.',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF00897B),
                        height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (pending.isEmpty) ...[
            const SizedBox(height: 40),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6F7F4),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.verified_rounded,
                        size: 32, color: Color(0xFF00897B)),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'All Clear',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: VitalPathTheme.deepCharcoal,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'No pending verifications.',
                    style: TextStyle(
                        fontSize: 13, color: VitalPathTheme.softGrey),
                  ),
                ],
              ),
            ),
          ] else
            ...pending.map((entry) {
              final i = entry.key;
              final v = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _VerifyCard(
                  verification: v,
                  onVerify: () {
                    HapticFeedback.lightImpact();
                    setState(() => _verified.add(i));
                  },
                  onReject: () {
                    HapticFeedback.mediumImpact();
                    setState(() => _rejected.add(i));
                  },
                ),
              );
            }),

          // Verified history
          if (_verified.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                'VERIFIED THIS SESSION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: VitalPathTheme.softGrey,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            ..._verified.map((i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _VerifiedHistoryCard(v: _verifications[i]),
                )),
          ],
        ],
      ),
    );
  }
}

class _VerifyCard extends StatelessWidget {
  final _DemoVerification verification;
  final VoidCallback onVerify;
  final VoidCallback onReject;
  const _VerifyCard(
      {required this.verification,
      required this.onVerify,
      required this.onReject});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFFFF8F00).withValues(alpha: 0.3)),
        boxShadow: VitalPathTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Self-Reported',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFF8F00),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                verification.reportedAt,
                style: const TextStyle(
                    fontSize: 11.5, color: VitalPathTheme.softGrey),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F7F4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.medication_rounded,
                    size: 22, color: Color(0xFF00897B)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      verification.medicine,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: VitalPathTheme.deepCharcoal,
                      ),
                    ),
                    Text(
                      verification.dosage,
                      style: const TextStyle(
                          fontSize: 13, color: VitalPathTheme.softGrey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Reported by ${verification.patient}',
            style: const TextStyle(
                fontSize: 12.5, color: VitalPathTheme.softGrey),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE53935),
                    side: const BorderSide(color: Color(0xFFE53935)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: onVerify,
                  icon: const Icon(Icons.verified_rounded, size: 16),
                  label: const Text('Verify & Lock'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VerifiedHistoryCard extends StatelessWidget {
  final _DemoVerification v;
  const _VerifiedHistoryCard({required this.v});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded,
              size: 18, color: Color(0xFF00897B)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${v.medicine} · ${v.dosage}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: VitalPathTheme.deepCharcoal,
                    )),
                Text(v.patient,
                    style: const TextStyle(
                        fontSize: 12, color: VitalPathTheme.softGrey)),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F7F4),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Verified',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF00897B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DOCTOR PROFILE TAB
// ─────────────────────────────────────────────────────────────────────────────
class _DoctorProfileTab extends StatelessWidget {
  final VoidCallback onExit;
  final bool isMainShell;
  const _DoctorProfileTab(
      {required this.onExit, this.isMainShell = false});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfileModel?>(
      future: UserProfileService().getProfile(),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final name = (profile?.displayName.isNotEmpty == true)
            ? profile!.displayName
            : 'Doctor';
        final specialty = profile?.specialty ?? '';
        final clinic = profile?.clinicName ?? '';
        final license = profile?.licenseNumber ?? '';
        final syncCode = profile?.doctorSyncCode ?? 'DR-847291';

        return Scaffold(
          backgroundColor: VitalPathTheme.lightSurface,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            title: const Text(
              'Doctor Profile',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: VitalPathTheme.deepCharcoal,
              ),
            ),
            automaticallyImplyLeading: false,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            physics: const BouncingScrollPhysics(),
            children: [
              // Identity card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3D5AFE), Color(0xFF1A237E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color:
                          const Color(0xFF3D5AFE).withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.local_hospital_rounded,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            specialty.isNotEmpty
                                ? '$specialty · VitalPath Provider'
                                : 'Physician · VitalPath Provider',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Clinical details
              if (specialty.isNotEmpty || clinic.isNotEmpty ||
                  license.isNotEmpty) ...[
                _DoctorSectionHeader('Clinical Details'),
                if (specialty.isNotEmpty)
                  _InfoRow(
                      icon: Icons.science_outlined,
                      label: 'Specialty',
                      value: specialty),
                if (clinic.isNotEmpty)
                  _InfoRow(
                      icon: Icons.business_outlined,
                      label: 'Clinic / Hospital',
                      value: clinic),
                if (license.isNotEmpty)
                  _InfoRow(
                      icon: Icons.badge_outlined,
                      label: 'License Number',
                      value: license),
                const SizedBox(height: 16),
              ],

              // Sync code card
              _DoctorSectionHeader('Doctor Sync Code'),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color:
                          const Color(0xFF3D5AFE).withValues(alpha: 0.25)),
                  boxShadow: VitalPathTheme.cardShadow,
                ),
                child: Column(
                  children: [
                    Text(
                      'DR-${syncCode.length > 6 ? syncCode.substring(0, 6) : syncCode}',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 6,
                        color: Color(0xFF3D5AFE),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Share this code with patients to link their accounts',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: VitalPathTheme.softGrey),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Portal info banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF3D5AFE).withValues(alpha: 0.2)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 16, color: Color(0xFF3D5AFE)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Portal preview — data is for UI testing. '
                        'Full Firestore Auth provisioning ships in v3.0.0.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF3D5AFE),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Exit / switch account
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onExit();
                  },
                  icon: Icon(
                    isMainShell
                        ? Icons.switch_account_rounded
                        : Icons.arrow_back_rounded,
                    size: 18,
                  ),
                  label: Text(isMainShell
                      ? 'Switch Account'
                      : 'Back to Patient View'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: VitalPathTheme.clinicalTeal,
                    side: const BorderSide(color: Color(0xFF00897B)),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DoctorSectionHeader extends StatelessWidget {
  final String title;
  const _DoctorSectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title.toUpperCase(),
        style: VitalPathTheme.labelLarge.copyWith(
          color: VitalPathTheme.softGrey,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: VitalPathTheme.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2F1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: const Color(0xFF00897B)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11,
                        color: VitalPathTheme.softGrey,
                        fontWeight: FontWeight.w500)),
                Text(value,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: VitalPathTheme.deepCharcoal,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: iconColor,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: VitalPathTheme.softGrey,
            ),
          ),
        ],
      ),
    );
  }
}
