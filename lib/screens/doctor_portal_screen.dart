/// doctor_portal_screen.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Doctor Portal — testable role-gated view for healthcare providers.
///
/// Accessed from Profile → "Switch to Doctor View".
/// Provides the doctor-side shell: Overview, Patients, Verification Queue,
/// and Doctor Profile. Each tab shows a design-system-consistent empty state
/// ready for live data integration when Firestore Auth custom claims are
/// provisioned (v3.0.0 milestone).
///
/// Route: slides up from bottom (modal pattern) to signal a role switch,
/// distinct from the right-slide pattern used for hierarchical drill-downs.
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:vitalpath/theme/vitalpath_theme.dart';

class DoctorPortalScreen extends StatefulWidget {
  const DoctorPortalScreen({super.key});

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
          _DoctorProfileTab(onExit: () => Navigator.of(context).pop()),
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
// OVERVIEW TAB
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
          expandedHeight: 100,
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
                                'Doctor Portal',
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

        // Stats row
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.people_rounded,
                    iconColor: const Color(0xFF3D5AFE),
                    bgColor: const Color(0xFFF0F4FF),
                    label: 'Patients',
                    value: '0',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    icon: Icons.pending_actions_rounded,
                    iconColor: const Color(0xFFFF8F00),
                    bgColor: const Color(0xFFFFF8E1),
                    label: 'Pending',
                    value: '0',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    icon: Icons.verified_rounded,
                    iconColor: VitalPathTheme.clinicalTeal,
                    bgColor: const Color(0xFFE6F7F4),
                    label: 'Verified',
                    value: '0',
                  ),
                ),
              ],
            ),
          ),
        ),

        // Empty feed
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F4FF),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.dashboard_rounded,
                        size: 32, color: Color(0xFF3D5AFE)),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Activity Yet',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: VitalPathTheme.deepCharcoal,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Patient activity, adherence alerts, and prescription '
                    'verification requests will appear here once you link your first patient.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: VitalPathTheme.softGrey,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onGoToPatients,
                    icon: const Icon(Icons.people_rounded, size: 18),
                    label: const Text('Link a Patient'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF3D5AFE),
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PATIENTS TAB
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
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.people_rounded,
                    size: 36, color: Color(0xFF3D5AFE)),
              ),
              const SizedBox(height: 18),
              const Text(
                'No Patients Linked',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: VitalPathTheme.deepCharcoal,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Share your doctor sync code with patients. '
                'When they enter it in their VitalPath app, '
                'they\'ll appear in your roster.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: VitalPathTheme.softGrey,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() => _codeVisible = !_codeVisible);
                },
                icon: Icon(
                  _codeVisible ? Icons.visibility_off_rounded : Icons.qr_code_rounded,
                  size: 18,
                ),
                label: Text(_codeVisible ? 'Hide Code' : 'Show Sync Code'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3D5AFE),
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
              if (_codeVisible) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF3D5AFE).withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3D5AFE).withValues(alpha: 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Column(
                    children: [
                      Text(
                        'DR-847291',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6,
                          color: Color(0xFF3D5AFE),
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Share this code with your patient',
                        style: TextStyle(
                          fontSize: 12,
                          color: VitalPathTheme.softGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VERIFICATION QUEUE TAB
// ─────────────────────────────────────────────────────────────────────────────
class _VerifyTab extends StatelessWidget {
  const _VerifyTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VitalPathTheme.lightSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Verify',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: VitalPathTheme.deepCharcoal,
          ),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
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
                child: const Icon(Icons.verified_rounded,
                    size: 36, color: Color(0xFF00897B)),
              ),
              const SizedBox(height: 18),
              const Text(
                'No Pending Verifications',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: VitalPathTheme.deepCharcoal,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'When a linked patient adds a self-reported prescription, '
                'it appears here for your clinical review. '
                'Verified records are Clinical Locked — patients cannot edit or delete them.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: VitalPathTheme.softGrey,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F7F4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_rounded,
                        size: 18, color: Color(0xFF00897B)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Clinical Lock activates automatically when you verify. '
                        'The patient sees a verified badge but cannot modify the record.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF00897B),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DOCTOR PROFILE TAB
// ─────────────────────────────────────────────────────────────────────────────
class _DoctorProfileTab extends StatelessWidget {
  final VoidCallback onExit;
  const _DoctorProfileTab({required this.onExit});

  @override
  Widget build(BuildContext context) {
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
          // Doctor identity card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: VitalPathTheme.cardShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3D5AFE), Color(0xFF1A237E)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.local_hospital_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Doctor Account',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: VitalPathTheme.deepCharcoal,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Role: Physician · VitalPath Provider',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: VitalPathTheme.softGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Portal info banner
          Container(
            padding: const EdgeInsets.all(16),
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
                    size: 18, color: Color(0xFF3D5AFE)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This is the v3.0.0 Doctor Portal preview. '
                    'Full role provisioning via Firestore Auth custom claims '
                    'is in progress. Data shown is for UI testing only.',
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

          // Exit button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                onExit();
              },
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Back to Patient View'),
              style: OutlinedButton.styleFrom(
                foregroundColor: VitalPathTheme.clinicalTeal,
                side: const BorderSide(color: Color(0xFF00897B)),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
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
