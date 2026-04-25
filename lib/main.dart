import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'package:vitalpath/firebase_options.dart';
import 'package:vitalpath/models/prescription_model.dart';
import 'package:vitalpath/theme/vitalpath_theme.dart';
import 'package:vitalpath/providers/activity_provider.dart';
import 'package:vitalpath/providers/appointment_provider.dart';
import 'package:vitalpath/providers/dashboard_provider.dart';
import 'package:vitalpath/providers/prescription_provider.dart';
import 'package:vitalpath/screens/activity_screen.dart';
import 'package:vitalpath/screens/care_screen.dart';
import 'package:vitalpath/screens/home_screen.dart';
import 'package:vitalpath/screens/doctor_portal_screen.dart';
import 'package:vitalpath/screens/my_doctors_screen.dart';
import 'package:vitalpath/screens/notification_settings_screen.dart';
import 'package:vitalpath/screens/onboarding/onboarding_flow.dart';
import 'package:vitalpath/screens/privacy_settings_screen.dart';
import 'package:vitalpath/services/auth_gate_service.dart';
import 'package:vitalpath/services/sync_queue_service.dart';

// Incrementing this notifier causes VitalpathApp to rebuild from scratch —
// fresh providers and a new _AppRouter that re-reads SharedPreferences.
// Used by the Developer tile to replay the full onboarding flow.
final _restartNotifier = ValueNotifier<int>(0);

void main() {
  // Zone-level guard: catches any unhandled Dart async exceptions that escape
  // all inner try-catch blocks, preventing silent isolate death that appears
  // to the user as a "stuck on splash" black screen.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Guard each async init step so a single failure can't block runApp().
    try {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
    } catch (e) {
      debugPrint('[Firebase] Initialization failed: $e');
    }

    try {
      await Hive.initFlutter();
      await Hive.openBox('sync_queue');
      await ConnectivityService().initialise(SyncQueueService());
    } catch (e) {
      debugPrint('[Init] Hive/Connectivity setup failed: $e');
    }

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    runApp(const VitalpathApp());
  }, (Object error, StackTrace stack) {
    debugPrint('[UncaughtError] $error');
  });
}

class VitalpathApp extends StatelessWidget {
  const VitalpathApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _restartNotifier,
      builder: (_, __, ___) => MultiProvider(
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
        home: const _AppRouter(),
      ),
    ),
  );
  }

  // Clears the onboarding flag and triggers a full app rebuild so _AppRouter
  // re-reads SharedPreferences and shows the splash + onboarding from scratch.
  static Future<void> restartFromSplash() async {
    await OnboardingFlow.reset();
    _restartNotifier.value++;
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF00897B),
      scaffoldBackgroundColor: VitalPathTheme.lightSurface,
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
        indicatorColor: Color(0xFFE0F2F1),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: VitalPathTheme.deepCharcoal),
        titleTextStyle: TextStyle(
          color: VitalPathTheme.deepCharcoal,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── App router: checks onboarding then auth ───────────────────────────────────
// First visit → OnboardingFlow. Returning user → _AuthGateWrapper.
class _AppRouter extends StatefulWidget {
  const _AppRouter();

  @override
  State<_AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<_AppRouter> {
  bool? _onboardingComplete;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final complete = await OnboardingFlow.isComplete();
    if (mounted) setState(() => _onboardingComplete = complete);
  }

  @override
  Widget build(BuildContext context) {
    if (_onboardingComplete == null) {
      // Brief opaque splash while reading SharedPreferences (~16ms).
      return const Scaffold(
        backgroundColor: Color(0xFF00897B),
        body: Center(
          child: Icon(Icons.favorite_rounded, color: Colors.white, size: 48),
        ),
      );
    }
    if (!_onboardingComplete!) {
      return OnboardingFlow(
        onComplete: () => setState(() => _onboardingComplete = true),
      );
    }
    return const _AuthGateWrapper();
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
  int _failedAttempts = 0;
  DateTime? _backgroundedAt;

  // Only re-challenge auth if the user was away for longer than this threshold.
  // Prevents locking the app during quick notification / multitasking switches.
  static const _resumeGracePeriod = Duration(minutes: 2);

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
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final gone = _backgroundedAt != null
          ? DateTime.now().difference(_backgroundedAt!)
          : null;
      _backgroundedAt = null;
      // Skip the re-challenge if the user was gone for less than the grace period.
      if (gone == null || gone > _resumeGracePeriod) {
        _checkSession();
      }
    }
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
    if (success && mounted) {
      setState(() {
        _isLocked = false;
        _failedAttempts = 0;
      });
    } else if (!success && mounted) {
      setState(() => _failedAttempts++);
    }
  }

  void _showEmergencyInfo(BuildContext context) {
    final prescriptions =
        context.read<PrescriptionProvider>().allPrescriptions;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmergencyInfoSheet(prescriptions: prescriptions),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const _AppShell(),
        if (_isLocked)
          _LockScreen(
            onUnlock: _promptAuth,
            failedAttempts: _failedAttempts,
            onEmergencyInfo: () => _showEmergencyInfo(context),
          ),
      ],
    );
  }
}

// Glass overlay lock screen: blurs the app underneath via BackdropFilter.
// After 3 failed biometric attempts the fallback passcode button appears.
class _LockScreen extends StatelessWidget {
  final VoidCallback onUnlock;
  final int failedAttempts;
  final VoidCallback? onEmergencyInfo;

  const _LockScreen({
    required this.onUnlock,
    this.failedAttempts = 0,
    this.onEmergencyInfo,
  });

  @override
  Widget build(BuildContext context) {
    final showFallback = failedAttempts >= 3;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Blur layer — blurs the _AppShell behind the lock.
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            color: VitalPathTheme.deepCharcoal.withOpacity(0.72),
          ),
        ),
        // Glass card + unlock controls
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.09),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.15),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // App icon
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00897B),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    const Color(0xFF00897B).withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.favorite_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'VitalPath',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          showFallback
                              ? 'Biometric unavailable — use your device passcode'
                              : 'Confirm your identity to continue',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        // Dot-style attempt indicator
                        if (failedAttempts > 0) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(3, (i) {
                              return Container(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 4),
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i < failedAttempts
                                      ? const Color(0xFFEF9A9A)
                                      : Colors.white.withOpacity(0.25),
                                ),
                              );
                            }),
                          ),
                          if (!showFallback) ...[
                            const SizedBox(height: 5),
                            Text(
                              '${3 - failedAttempts} attempt${3 - failedAttempts == 1 ? '' : 's'} remaining',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.55),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ],
                        const SizedBox(height: 24),
                        // Primary action
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: FilledButton.icon(
                            onPressed: onUnlock,
                            icon: Icon(
                              showFallback
                                  ? Icons.dialpad_rounded
                                  : Icons.fingerprint_rounded,
                              size: 22,
                            ),
                            label: Text(
                              showFallback ? 'Use Passcode' : 'Unlock',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF00897B),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Emergency info — always accessible, no auth required
                        TextButton.icon(
                          onPressed: onEmergencyInfo,
                          icon: const Icon(
                            Icons.emergency_share_rounded,
                            size: 15,
                            color: Color(0xFFEF9A9A),
                          ),
                          label: const Text(
                            'View Emergency Info',
                            style: TextStyle(
                              color: Color(0xFFEF9A9A),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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
          HomeScreen(onNavigateToCare: () => setState(() => _tab = 1)),
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
      backgroundColor: VitalPathTheme.lightSurface,
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
                          color: VitalPathTheme.deepCharcoal,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Text(
                        'VitalPath Patient',
                        style: TextStyle(
                          fontSize: 13,
                          color: VitalPathTheme.softGrey,
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
                  const _SectionHeader('My Health'),
                  _ProfileTile(
                    icon: Icons.people_alt_outlined,
                    label: 'My Doctors',
                    subtitle: 'Sync and manage your care team',
                    onTap: () => Navigator.of(context)
                        .push(MyDoctorsScreen.route(patientId)),
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
                  const SizedBox(height: 16),
                  const _SectionHeader('Developer'),
                  _ProfileTile(
                    icon: Icons.replay_rounded,
                    label: 'Restart from Splash',
                    subtitle: 'Replay onboarding → login → profile creation',
                    iconColor: const Color(0xFFE65100),
                    onTap: () async {
                      HapticFeedback.mediumImpact();
                      await VitalpathApp.restartFromSplash();
                    },
                  ),
                  _ProfileTile(
                    icon: Icons.local_hospital_rounded,
                    label: 'Switch to Doctor View',
                    subtitle: 'Test the v3.0.0 doctor portal (preview)',
                    iconColor: const Color(0xFF3D5AFE),
                    onTap: () => Navigator.of(context).push(
                      DoctorPortalScreen.route(),
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

// ── Emergency Info Sheet (no auth required) ───────────────────────────────────
// Shows a read-only list of the patient's current medications.
// Accessible from the lock screen for first-responder / emergency scenarios.
class _EmergencyInfoSheet extends StatelessWidget {
  final List<PrescriptionModel> prescriptions;

  const _EmergencyInfoSheet({required this.prescriptions});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 60),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 2),
              child: Row(
                children: [
                  Icon(Icons.emergency_rounded,
                      color: Color(0xFFE53935), size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Emergency Medical Info',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: VitalPathTheme.deepCharcoal,
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Read-only · No authentication required',
                style: TextStyle(fontSize: 12, color: VitalPathTheme.softGrey),
              ),
            ),
            const Divider(height: 1),
            if (prescriptions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(
                  child: Text(
                    'No medications on record.',
                    style:
                        TextStyle(color: VitalPathTheme.softGrey, fontSize: 14),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: prescriptions.length,
                  separatorBuilder: (_, __) => const Divider(
                      indent: 20, endIndent: 20, height: 1),
                  itemBuilder: (_, i) {
                    final p = prescriptions[i];
                    final dosageStr = p.dosage == p.dosage.roundToDouble()
                        ? p.dosage.toInt().toString()
                        : p.dosage.toString();
                    return ListTile(
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6F7F4),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.medication_rounded,
                            size: 18, color: Color(0xFF00897B)),
                      ),
                      title: Text(
                        p.medicineName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: VitalPathTheme.deepCharcoal),
                      ),
                      subtitle: Text(
                        '$dosageStr ${p.unit.label}'
                        '${p.doctorName.isNotEmpty ? ' · Dr. ${p.doctorName}' : ''}',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF888899)),
                      ),
                      trailing: p.isVerified
                          ? const Icon(Icons.verified_rounded,
                              size: 16, color: Color(0xFF00897B))
                          : null,
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
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
        style: VitalPathTheme.labelLarge.copyWith(
          color: VitalPathTheme.softGrey,
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
  final Color? iconColor;

  const _ProfileTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: VitalPathTheme.cardShadow,
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
                      color: iconColor != null
                          ? iconColor!.withValues(alpha: 0.1)
                          : const Color(0xFFE0F2F1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon,
                        size: 20, color: iconColor ?? const Color(0xFF00897B)),
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
                              color: VitalPathTheme.deepCharcoal,
                            )),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: VitalPathTheme.softGrey,
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
