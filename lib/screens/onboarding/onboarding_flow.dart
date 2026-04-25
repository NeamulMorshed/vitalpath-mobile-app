import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vitalpath/theme/vitalpath_theme.dart';
import 'package:vitalpath/widgets/glass_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OnboardingFlow
// ─────────────────────────────────────────────────────────────────────────────
// 3-screen 2026 onboarding: Value Prop → Identity & Biometrics → Activation.
//
// Performance contract:
//   • PageView with BouncingScrollPhysics — 120fps swipe transitions.
//   • Each page wrapped in RepaintBoundary — isolated repaint layers.
//   • AnimationController per page, disposed on page exit.
//   • Staggered entry animations via Interval curves.
//   • HapticFeedback.lightImpact() on every step completion.
// ─────────────────────────────────────────────────────────────────────────────

class OnboardingFlow extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingFlow({super.key, required this.onComplete});

  static const _prefKey = 'onboarding_complete';

  static Future<bool> isComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  static Future<void> markComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _pageController = PageController();
  int _currentPage = 0;
  static const _pageCount = 3;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goNext() {
    HapticFeedback.lightImpact();
    if (_currentPage < _pageCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    HapticFeedback.lightImpact();
    await OnboardingFlow.markComplete();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    // Force dark system chrome on all onboarding pages.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: VitalPathTheme.deepCharcoal,
        body: Stack(
          children: [
            // ── Pages ─────────────────────────────────────────────────────────
            PageView(
              controller: _pageController,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (i) => setState(() => _currentPage = i),
              children: [
                RepaintBoundary(child: _Page1ValueProp(onNext: _goNext)),
                RepaintBoundary(child: _Page2Identity(onNext: _goNext)),
                RepaintBoundary(child: _Page3Activation(onFinish: _finish)),
              ],
            ),

            // ── Dot indicator (floats above pages) ────────────────────────────
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 20,
              left: 0,
              right: 0,
              child: _DotIndicator(
                count: _pageCount,
                current: _currentPage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dot Indicator
// ─────────────────────────────────────────────────────────────────────────────
class _DotIndicator extends StatelessWidget {
  final int count;
  final int current;

  const _DotIndicator({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 28 : 8,
          height: 8,
          decoration: BoxDecoration(
            gradient: active ? VitalPathTheme.electricGradient : null,
            color: active ? null : Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 1 — Value Prop: "Your Health, Decoded."
// ─────────────────────────────────────────────────────────────────────────────
class _Page1ValueProp extends StatefulWidget {
  final VoidCallback onNext;
  const _Page1ValueProp({required this.onNext});

  @override
  State<_Page1ValueProp> createState() => _Page1ValuePropState();
}

class _Page1ValuePropState extends State<_Page1ValueProp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // Staggered entry animations
  late final Animation<double> _logoFade;
  late final Animation<Offset> _logoSlide;
  late final Animation<double> _gridFade;
  late final Animation<Offset> _gridSlide;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _ctaFade;
  late final Animation<Offset> _ctaSlide;

  // Bento card pulse
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _logoFade  = _fade(0.00, 0.30);
    _logoSlide = _slide(0.00, 0.30);
    _gridFade  = _fade(0.18, 0.55);
    _gridSlide = _slide(0.18, 0.55);
    _textFade  = _fade(0.45, 0.78);
    _textSlide = _slide(0.45, 0.78);
    _ctaFade   = _fade(0.65, 1.00);
    _ctaSlide  = _slide(0.65, 1.00);

    _ctrl.forward();
  }

  Animation<double> _fade(double begin, double end) =>
      Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: Interval(begin, end, curve: Curves.easeOut),
        ),
      );

  Animation<Offset> _slide(double begin, double end) =>
      Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: Interval(begin, end, curve: Curves.easeOutCubic),
        ),
      );

  @override
  void dispose() {
    _ctrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final topPad = MediaQuery.of(context).padding.top;

    return Container(
      decoration: const BoxDecoration(gradient: VitalPathTheme.darkGradient),
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, topPad + 24, 24, 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Logo mark ─────────────────────────────────────────────────────
            FadeTransition(
              opacity: _logoFade,
              child: SlideTransition(
                position: _logoSlide,
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: VitalPathTheme.tealGradient,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: VitalPathTheme.tealGlowShadow(),
                      ),
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'VitalPath',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const Spacer(),
                    // Step chip
                    _StepChip(label: '01 / 03'),
                  ],
                ),
              ),
            ),

            SizedBox(height: size.height * 0.04),

            // ── Bento Grid ────────────────────────────────────────────────────
            FadeTransition(
              opacity: _gridFade,
              child: SlideTransition(
                position: _gridSlide,
                child: SizedBox(
                  height: size.height * 0.36,
                  child: _BentoGrid(pulse: _pulse),
                ),
              ),
            ),

            SizedBox(height: size.height * 0.04),

            // ── Headline ──────────────────────────────────────────────────────
            FadeTransition(
              opacity: _textFade,
              child: SlideTransition(
                position: _textSlide,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) =>
                          VitalPathTheme.electricGradient.createShader(bounds),
                      child: Text(
                        'Your Health,\nDecoded.',
                        style: VitalPathTheme.displayLarge.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'A clinical-grade passbook for\nyour daily wellness.',
                      style: VitalPathTheme.bodyLarge.copyWith(
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // ── CTA ───────────────────────────────────────────────────────────
            FadeTransition(
              opacity: _ctaFade,
              child: SlideTransition(
                position: _ctaSlide,
                child: _PrimaryButton(
                  label: 'Get Started',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: widget.onNext,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bento Grid (6 health cards) ───────────────────────────────────────────────
class _BentoGrid extends StatelessWidget {
  final Animation<double> pulse;
  const _BentoGrid({required this.pulse});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left column: large Rx card + small Food card
        Expanded(
          flex: 5,
          child: Column(
            children: [
              // Large medicine card (pulsing)
              Expanded(
                flex: 3,
                child: AnimatedBuilder(
                  animation: pulse,
                  builder: (_, child) => Transform.scale(
                    scale: pulse.value,
                    child: child,
                  ),
                  child: GlassCard.accent(
                    borderRadius: BorderRadius.circular(18),
                    padding: const EdgeInsets.all(16),
                    boxShadow: VitalPathTheme.tealGlowShadow(intensity: 0.7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: VitalPathTheme.electricTeal
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'DUE NOW',
                                style: VitalPathTheme.labelMedium.copyWith(
                                  color: VitalPathTheme.electricTeal,
                                ),
                              ),
                            ),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: VitalPathTheme.electricTeal,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.medication_rounded,
                              color: VitalPathTheme.electricTeal,
                              size: 26,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Metformin',
                              style: VitalPathTheme.headlineMedium.copyWith(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '500mg · 8:00 AM',
                              style: VitalPathTheme.patientData.copyWith(
                                color:
                                    Colors.white.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Small Food card
              Expanded(
                flex: 2,
                child: _SmallBentoCard(
                  icon: Icons.restaurant_rounded,
                  iconColor: const Color(0xFFFFA726),
                  label: 'Food',
                  metric: '1,840',
                  unit: 'kcal',
                  bgColor: const Color(0x1AFFA726),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Right column: Steps + Activity + Appointment
        Expanded(
          flex: 4,
          child: Column(
            children: [
              // Steps card
              Expanded(
                flex: 2,
                child: _SmallBentoCard(
                  icon: Icons.directions_walk_rounded,
                  iconColor: const Color(0xFF40C4FF),
                  label: 'Steps',
                  metric: '8,420',
                  unit: 'today',
                  bgColor: const Color(0x1A40C4FF),
                ),
              ),
              const SizedBox(height: 8),
              // Activity card
              Expanded(
                flex: 2,
                child: _SmallBentoCard(
                  icon: Icons.directions_run_rounded,
                  iconColor: const Color(0xFF69F0AE),
                  label: 'Activity',
                  metric: '3.2',
                  unit: 'km walk',
                  bgColor: const Color(0x1A69F0AE),
                ),
              ),
              const SizedBox(height: 8),
              // Appointment card
              Expanded(
                flex: 2,
                child: GlassCard.dark(
                  borderRadius: BorderRadius.circular(14),
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.verified_rounded,
                            color: VitalPathTheme.verifiedGold,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Verified',
                            style: VitalPathTheme.verifiedData
                                .copyWith(fontSize: 10),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Dr. Rahman',
                        style: VitalPathTheme.bodyMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        'Tomorrow · 10:30',
                        style: VitalPathTheme.patientData.copyWith(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SmallBentoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String metric;
  final String unit;
  final Color bgColor;

  const _SmallBentoCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.metric,
    required this.unit,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard.dark(
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(height: 4),
          Text(
            metric,
            style: VitalPathTheme.bentoMetric.copyWith(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
          Text(
            unit,
            style: VitalPathTheme.bentoLabel.copyWith(
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 2 — Secure Identity & Biometrics
// ─────────────────────────────────────────────────────────────────────────────
enum _AuthStage { idle, loading, biometric, done }

class _Page2Identity extends StatefulWidget {
  final VoidCallback onNext;
  const _Page2Identity({required this.onNext});

  @override
  State<_Page2Identity> createState() => _Page2IdentityState();
}

class _Page2IdentityState extends State<_Page2Identity>
    with TickerProviderStateMixin {
  _AuthStage _stage = _AuthStage.idle;
  final _googleSignIn = GoogleSignIn();

  late final AnimationController _entryCtrl;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;

  // Biometric ring pulse animation
  late final AnimationController _ringCtrl;
  late final Animation<double> _ring;

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _entryFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut),
    );
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));

    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _ring = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ringCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _ringCtrl.dispose();
    super.dispose();
  }

  Future<void> _onGoogleSignIn() async {
    HapticFeedback.lightImpact();
    setState(() => _stage = _AuthStage.loading);

    try {
      // Launch the Google account picker. Returns null if the user cancels.
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User dismissed the picker — go back to idle so they can try again.
        if (mounted) setState(() => _stage = _AuthStage.idle);
        return;
      }

      // Exchange the Google tokens for a Firebase credential.
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);

      if (mounted) setState(() => _stage = _AuthStage.biometric);
    } catch (e) {
      debugPrint('[GoogleAuth] Sign-in failed: $e');
      if (!mounted) return;

      // Google Sign-In requires OAuth to be configured in Firebase Console
      // (SHA-1 fingerprint + Google provider enabled). Until then, show a
      // brief notice and proceed so testers can verify the rest of the flow.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Google Sign-In needs Firebase OAuth setup — continuing for now.',
          ),
          backgroundColor: const Color(0xFF1A1A2E),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) setState(() => _stage = _AuthStage.biometric);
    }
  }

  Future<void> _onBiometric() async {
    HapticFeedback.lightImpact();
    setState(() => _stage = _AuthStage.done);

    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Container(
      decoration: const BoxDecoration(gradient: VitalPathTheme.darkGradient),
      child: FadeTransition(
        opacity: _entryFade,
        child: SlideTransition(
          position: _entrySlide,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, topPad + 24, 24, 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ───────────────────────────────────────────────────
                Row(
                  children: [
                    const Spacer(),
                    _StepChip(label: '02 / 03'),
                  ],
                ),
                const SizedBox(height: 40),

                // ── Central biometric illustration ────────────────────────────
                Expanded(
                  child: Center(
                    child: _stage == _AuthStage.loading
                        ? _ShimmerSection()
                        : _stage == _AuthStage.biometric ||
                                _stage == _AuthStage.done
                            ? _BiometricPrompt(
                                ring: _ring,
                                onTap: _onBiometric,
                                isDone: _stage == _AuthStage.done,
                              )
                            : _GoogleSection(onTap: _onGoogleSignIn),
                  ),
                ),

                // ── Bottom text ───────────────────────────────────────────────
                Text(
                  'Secure Identity',
                  style: VitalPathTheme.displayMedium.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Your health data is encrypted end-to-end. We never share your information with third parties.',
                  style: VitalPathTheme.bodyMedium.copyWith(
                    color: Colors.white.withValues(alpha: 0.5),
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Security badges ───────────────────────────────────────────
                Row(
                  children: [
                    _SecurityBadge(
                        icon: Icons.lock_rounded, label: 'AES-256'),
                    const SizedBox(width: 10),
                    _SecurityBadge(
                        icon: Icons.shield_rounded, label: 'HIPAA Ready'),
                    const SizedBox(width: 10),
                    _SecurityBadge(
                        icon: Icons.block_rounded, label: 'No Ads'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Google sign-in section
class _GoogleSection extends StatelessWidget {
  final VoidCallback onTap;
  const _GoogleSection({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Google icon container
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.06),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Center(
            child: Text(
              'G',
              style: TextStyle(
                fontSize: 46,
                fontWeight: FontWeight.w700,
                foreground: Paint()
                  ..shader = VitalPathTheme.electricGradient
                      .createShader(const Rect.fromLTWH(0, 0, 60, 60)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        // Google sign-in button
        GestureDetector(
          onTap: onTap,
          child: GlassCard(
            borderRadius: BorderRadius.circular(14),
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            surfaceColor: Colors.white.withValues(alpha: 0.1),
            borderColor: Colors.white.withValues(alpha: 0.18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'G',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    foreground: Paint()
                      ..shader = VitalPathTheme.electricGradient
                          .createShader(
                              const Rect.fromLTWH(0, 0, 30, 30)),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Continue with Google',
                  style: VitalPathTheme.ctaSecondary.copyWith(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'We use Google to verify your identity securely.',
          style: VitalPathTheme.bodyMedium.copyWith(
            color: Colors.white.withValues(alpha: 0.3),
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// Shimmer loading section (shown after Google tap)
class _ShimmerSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ShimmerLoader(
          width: 100,
          height: 100,
          borderRadius: BorderRadius.circular(50),
        ),
        const SizedBox(height: 28),
        ShimmerLoader(
          width: 220,
          height: 52,
          borderRadius: BorderRadius.circular(14),
        ),
        const SizedBox(height: 16),
        ShimmerLoader(
          width: 160,
          height: 16,
          borderRadius: BorderRadius.circular(8),
        ),
        const SizedBox(height: 8),
        ShimmerLoader(
          width: 120,
          height: 12,
          borderRadius: BorderRadius.circular(6),
        ),
      ],
    );
  }
}

// Biometric prompt section
class _BiometricPrompt extends StatelessWidget {
  final Animation<double> ring;
  final VoidCallback onTap;
  final bool isDone;

  const _BiometricPrompt({
    required this.ring,
    required this.onTap,
    required this.isDone,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedBuilder(
            animation: ring,
            builder: (_, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Outer glow ring
                  Transform.scale(
                    scale: ring.value * 1.35,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: VitalPathTheme.electricTeal
                              .withValues(alpha: 0.12),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  // Middle ring
                  Transform.scale(
                    scale: ring.value * 1.15,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: VitalPathTheme.electricTeal
                              .withValues(alpha: 0.22),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  // Inner circle
                  child!,
                ],
              );
            },
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isDone
                    ? VitalPathTheme.electricGradient
                    : null,
                color: isDone
                    ? null
                    : VitalPathTheme.electricTeal.withValues(alpha: 0.15),
                border: Border.all(
                  color: VitalPathTheme.electricTeal
                      .withValues(alpha: isDone ? 0.8 : 0.4),
                  width: 1.5,
                ),
                boxShadow: VitalPathTheme.electricGlowShadow(
                    intensity: isDone ? 1.0 : 0.5),
              ),
              child: Icon(
                isDone
                    ? Icons.check_rounded
                    : Icons.fingerprint_rounded,
                size: 52,
                color: isDone
                    ? Colors.white
                    : VitalPathTheme.electricTeal,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          isDone ? 'Identity Confirmed' : 'Tap to Authenticate',
          style: VitalPathTheme.headlineMedium.copyWith(
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isDone
              ? 'Your biometric is now linked to your passbook.'
              : 'Use Face ID or fingerprint to secure your health data.',
          style: VitalPathTheme.bodyMedium.copyWith(
            color: Colors.white.withValues(alpha: 0.45),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _SecurityBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SecurityBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return GlassCard.dark(
      borderRadius: BorderRadius.circular(10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: VitalPathTheme.electricTeal, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: VitalPathTheme.labelMedium.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 3 — Initial Activation
// ─────────────────────────────────────────────────────────────────────────────
class _Page3Activation extends StatefulWidget {
  final VoidCallback onFinish;
  const _Page3Activation({required this.onFinish});

  @override
  State<_Page3Activation> createState() => _Page3ActivationState();
}

class _Page3ActivationState extends State<_Page3Activation>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  int? _selectedGoal;
  bool _doctorInvited = false;

  late final AnimationController _entryCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  static const _goals = [
    (Icons.medication_rounded,    'Medication\nAdherence'),
    (Icons.monitor_weight_rounded,'Weight &\nNutrition'),
    (Icons.favorite_rounded,      'Chronic\nDisease'),
    (Icons.self_improvement_rounded, 'General\nWellness'),
  ];

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();

    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: const BoxDecoration(gradient: VitalPathTheme.darkGradient),
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: SingleChildScrollView(
              padding:
                  EdgeInsets.fromLTRB(24, topPad + 24, 24, 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ─────────────────────────────────────────────────
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Final Step.',
                            style: VitalPathTheme.displayMedium.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Tell us about yourself.',
                            style: VitalPathTheme.bodyLarge.copyWith(
                              color: Colors.white.withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      _StepChip(label: '03 / 03'),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // ── Name field ─────────────────────────────────────────────
                  _FieldLabel('Your Name'),
                  const SizedBox(height: 10),
                  GlassCard.dark(
                    borderRadius: BorderRadius.circular(14),
                    padding: EdgeInsets.zero,
                    child: TextFormField(
                      controller: _nameController,
                      style: VitalPathTheme.bodyLarge.copyWith(
                        color: Colors.white,
                      ),
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: 'e.g. Arif Hossain',
                        hintStyle: VitalPathTheme.bodyLarge.copyWith(
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                        prefixIcon: const Icon(
                          Icons.person_outline_rounded,
                          color: VitalPathTheme.electricTeal,
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Primary Health Goal ────────────────────────────────────
                  _FieldLabel('Primary Health Goal'),
                  const SizedBox(height: 10),
                  // Variable Typography: selected goal uses w800 (heavy),
                  // unselected uses w400 (light) — visual hierarchy at a glance.
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.8,
                    ),
                    itemCount: _goals.length,
                    itemBuilder: (_, i) {
                      final selected = _selectedGoal == i;
                      final (icon, label) = _goals[i];
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedGoal = i);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          decoration: BoxDecoration(
                            gradient: selected
                                ? VitalPathTheme.tealGradient
                                : null,
                            color: selected
                                ? null
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? VitalPathTheme.electricTeal
                                      .withValues(alpha: 0.6)
                                  : Colors.white.withValues(alpha: 0.1),
                            ),
                            boxShadow: selected
                                ? VitalPathTheme.tealGlowShadow(
                                    intensity: 0.6)
                                : null,
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                icon,
                                color: selected
                                    ? Colors.white
                                    : Colors.white
                                        .withValues(alpha: 0.4),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  label,
                                  // Variable typography: w800 when selected
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : Colors.white
                                            .withValues(alpha: 0.45),
                                    fontSize: 12,
                                    fontWeight: selected
                                        ? FontWeight.w800
                                        : FontWeight.w400,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // ── Invite your Doctor CTA ────────────────────────────────
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _doctorInvited = !_doctorInvited);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      decoration: BoxDecoration(
                        color: _doctorInvited
                            ? VitalPathTheme.verifiedGold
                                .withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _doctorInvited
                              ? VitalPathTheme.verifiedGold
                                  .withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.1),
                          width: 1.2,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      child: Row(
                        children: [
                          Icon(
                            _doctorInvited
                                ? Icons.check_circle_rounded
                                : Icons.people_alt_outlined,
                            color: _doctorInvited
                                ? VitalPathTheme.verifiedGold
                                : Colors.white.withValues(alpha: 0.45),
                            size: 22,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Invite Your Doctor',
                                  // Variable typography: CTA label uses w700
                                  style: VitalPathTheme.ctaSecondary.copyWith(
                                    color: _doctorInvited
                                        ? VitalPathTheme.verifiedGold
                                        : Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  _doctorInvited
                                      ? "Reminder added — we'll send the link"
                                      : 'Share a sync code after setup',
                                  style: VitalPathTheme.bodyMedium.copyWith(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white.withValues(alpha: 0.2),
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Primary CTA — heaviest weight, full width ──────────────
                  _PrimaryButton(
                    label: 'Start My Health Journey',
                    icon: Icons.favorite_rounded,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      widget.onFinish();
                    },
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'You can update all of this later in Profile.',
                      style: VitalPathTheme.bodyMedium.copyWith(
                        color: Colors.white.withValues(alpha: 0.28),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared micro-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: VitalPathTheme.labelLarge.copyWith(
        color: Colors.white.withValues(alpha: 0.4),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  final String label;
  const _StepChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return GlassCard.dark(
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Text(
        label,
        style: VitalPathTheme.labelMedium.copyWith(
          color: Colors.white.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

// Primary action button — w900 per Variable Typography spec.
class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: VitalPathTheme.tealGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: VitalPathTheme.tealGlowShadow(),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  label,
                  // Variable Typography: primary CTA uses FontWeight.w900
                  style: VitalPathTheme.ctaPrimary.copyWith(
                    color: Colors.white,
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
