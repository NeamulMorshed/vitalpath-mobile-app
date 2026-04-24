import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'package:vitalpath/firebase_options.dart';
import 'package:vitalpath/providers/activity_provider.dart';
import 'package:vitalpath/providers/appointment_provider.dart';
import 'package:vitalpath/providers/dashboard_provider.dart';
import 'package:vitalpath/providers/prescription_provider.dart';
import 'package:vitalpath/screens/activity_screen.dart';
import 'package:vitalpath/screens/care_screen.dart';
import 'package:vitalpath/screens/home_screen.dart';
import 'package:vitalpath/screens/my_doctors_screen.dart';
import 'package:vitalpath/screens/notification_settings_screen.dart';
import 'package:vitalpath/screens/prescription_vault_screen.dart';
import 'package:vitalpath/screens/privacy_settings_screen.dart';
import 'package:vitalpath/services/auth_gate_service.dart';
import 'package:vitalpath/services/sync_queue_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await Hive.initFlutter();
  await Hive.openBox('sync_queue');

  // Wire the offline sync queue to connectivity events.
  // ConnectivityService will call flushQueue() automatically when the device
  // comes back online after a Firebase outage or network loss.
  await ConnectivityService().initialise(SyncQueueService());

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  runApp(const VitalpathApp());
}

class VitalpathApp extends StatelessWidget {
  const VitalpathApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PrescriptionProvider()),
        ChangeNotifierProvider(create: (_) => AppointmentProvider()),
        // DashboardProvider projects from the two upstream providers above.
        // update returns the existing instance — listeners are registered once
        // in the constructor and must not be re-added on upstream rebuilds.
        ChangeNotifierProxyProvider2<PrescriptionProvider, AppointmentProvider,
            DashboardProvider>(
          create: (ctx) => DashboardProvider(
            prescriptions: ctx.read<PrescriptionProvider>(),
            appointments: ctx.read<AppointmentProvider>(),
          ),
          update: (_, __, ___, previous) => previous!,
        ),
      ],
      child: MaterialApp(
        title: 'VitalPath',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: const _AuthGateWrapper(),
      ),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF00897B),
      scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
        indicatorColor: Color(0xFFE0F2F1),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFF1A1A2E)),
        titleTextStyle: TextStyle(
          color: Color(0xFF1A1A2E),
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Auth gate wrapper ─────────────────────────────────────────────────────────
// Sits above _AppShell. Checks the biometric session on cold start and every
// time the app returns from background. Shows _LockScreen when session is
// expired and prompts for biometric / device credential.
class _AuthGateWrapper extends StatefulWidget {
  const _AuthGateWrapper();

  @override
  State<_AuthGateWrapper> createState() => _AuthGateWrapperState();
}

class _AuthGateWrapperState extends State<_AuthGateWrapper>
    with WidgetsBindingObserver {
  bool _isLocked = false;
  bool _isPrompting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkSession();
  }

  Future<void> _checkSession() async {
    final valid = await AuthGateService().hasValidSession();
    if (!valid && mounted) {
      setState(() => _isLocked = true);
      _promptAuth();
    }
  }

  Future<void> _promptAuth() async {
    if (_isPrompting) return;
    _isPrompting = true;
    final success = await AuthGateService().authenticate();
    _isPrompting = false;
    if (success && mounted) setState(() => _isLocked = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const _AppShell(),
        if (_isLocked) _LockScreen(onUnlock: _promptAuth),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  final VoidCallback onUnlock;
  const _LockScreen({required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1A2E),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF00897B),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'VitalPath',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Confirm your identity to continue',
                style: TextStyle(
                  color: Color(0xFF9E9E9E),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 48),
              FilledButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.fingerprint_rounded),
                label: const Text('Unlock'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00897B),
                  minimumSize: const Size(160, 48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bottom-nav shell ──────────────────────────────────────────────────────────
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _tab = 0;

  // Replace with the authenticated user's UID once Firebase Auth is wired up.
  static const _patientId = 'debug-patient-001';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          const HomeScreen(),
          const CareScreen(),
          // ActivityProvider is scoped to the Activity tab only.
          ChangeNotifierProvider(
            create: (_) => ActivityProvider(),
            child: ActivityScreen(patientId: _patientId),
          ),
          _ProfileTab(patientId: _patientId),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.medical_services_outlined),
            selectedIcon: Icon(Icons.medical_services_rounded),
            label: 'Care',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_walk_outlined),
            selectedIcon: Icon(Icons.directions_walk_rounded),
            label: 'Activity',
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

// ── Profile tab ───────────────────────────────────────────────────────────────
class _ProfileTab extends StatelessWidget {
  final String patientId;

  const _ProfileTab({required this.patientId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverAppBar(
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
                      const Text(
                        'Profile',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A2E),
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        patientId,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF9E9E9E),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionHeader('Clinical'),
                  _ProfileTile(
                    icon: Icons.people_alt_outlined,
                    label: 'My Doctors',
                    subtitle: 'Sync and manage your care team',
                    onTap: () => Navigator.of(context)
                        .push(MyDoctorsScreen.route(patientId)),
                  ),
                  _ProfileTile(
                    icon: Icons.medication_outlined,
                    label: 'Prescription Vault',
                    subtitle: 'All prescriptions grouped by doctor',
                    onTap: () => Navigator.of(context).push(
                      _slideRoute(const PrescriptionVaultScreen()),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _SectionHeader('Settings'),
                  _ProfileTile(
                    icon: Icons.notifications_outlined,
                    label: 'Notification & Haptics',
                    subtitle: 'Medicine reminders, goal alerts',
                    onTap: () => Navigator.of(context).push(
                      _slideRoute(const NotificationSettingsScreen()),
                    ),
                  ),
                  _ProfileTile(
                    icon: Icons.security_rounded,
                    label: 'Privacy & Security',
                    subtitle: 'Biometric lock, encryption, data access',
                    onTap: () => Navigator.of(context).push(
                      PrivacySettingsScreen.route(patientId),
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

  // Standard right-to-left slide for hierarchical drill-down screens.
  // Reverse (pop) is right-to-left mirror, confirming the user is "going back."
  PageRoute<void> _slideRoute(Widget page) {
    return PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => page,
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

}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF9E9E9E),
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ProfileTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2F1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon,
                        size: 20, color: const Color(0xFF00897B)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1A2E),
                            )),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9E9E9E),
                              fontWeight: FontWeight.w400,
                            )),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: Color(0xFFBDBDBD), size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
