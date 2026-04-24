import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    if (_page < 2) {
      _goTo(_page + 1);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await OnboardingFlow.markComplete();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _page == 1
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Stack(
          children: [
            PageView(
              controller: _controller,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                _ValuePropPage(onNext: _next),
                _SecurityPage(onNext: _next),
                _ProfilePage(onFinish: _finish),
              ],
            ),
            // Dot indicator — positioned above system nav bar
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 24,
              child: _DotIndicator(count: 3, current: _page),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dot indicator ─────────────────────────────────────────────────────────────
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
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF00897B)
                : const Color(0xFF00897B).withOpacity(0.25),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

// ── PAGE 1: Value Prop ────────────────────────────────────────────────────────
class _ValuePropPage extends StatefulWidget {
  final VoidCallback onNext;
  const _ValuePropPage({required this.onNext});

  @override
  State<_ValuePropPage> createState() => _ValuePropPageState();
}

class _ValuePropPageState extends State<_ValuePropPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF0FBF9), Color(0xFFE6F7F4), Color(0xFFFFFFFF)],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo mark
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00897B),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'VitalPath',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF00897B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              // Animated illustration — bento grid of health cards
              SizedBox(
                height: size.height * 0.32,
                child: _BentoIllustration(pulse: _pulse),
              ),
              const SizedBox(height: 32),
              // Headline
              const Text(
                'Your Health,\nFully Connected',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                  height: 1.15,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'A single secure passbook for medicines, appointments, and wellness — shared with your care team in real time.',
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF6B7280),
                  height: 1.55,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 28),
              // Feature bullets
              const _FeatureBullet(
                icon: Icons.medication_rounded,
                iconColor: Color(0xFF00897B),
                text: 'Never miss a dose — smart reminders that adapt to you',
              ),
              const SizedBox(height: 10),
              const _FeatureBullet(
                icon: Icons.people_alt_rounded,
                iconColor: Color(0xFF1565C0),
                text: 'Doctor Sync — your care team always in the loop',
              ),
              const SizedBox(height: 10),
              const _FeatureBullet(
                icon: Icons.shield_rounded,
                iconColor: Color(0xFFF59E0B),
                text: 'AES-256 encrypted — your data stays yours',
              ),
              const Spacer(),
              // CTA
              _PrimaryButton(
                label: 'Get Started',
                icon: Icons.arrow_forward_rounded,
                onPressed: widget.onNext,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Animated bento grid illustration
class _BentoIllustration extends StatelessWidget {
  final AnimationController pulse;
  const _BentoIllustration({required this.pulse});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, __) {
        final t = pulse.value;
        return Row(
          children: [
            // Left column
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    flex: 3,
                    child: _BentoCard(
                      color: const Color(0xFF00897B),
                      opacity: 0.85 + t * 0.15,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.medication_rounded,
                              color: Colors.white, size: 28),
                          const SizedBox(height: 6),
                          const Text(
                            'Metformin\n500mg',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'DUE NOW',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    flex: 2,
                    child: _BentoCard(
                      color: const Color(0xFFF0FBF9),
                      opacity: 1.0,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.directions_walk_rounded,
                              color: Color(0xFF00897B), size: 22),
                          const SizedBox(height: 4),
                          Text(
                            '${(6200 + (t * 800).round())}',
                            style: const TextStyle(
                              color: Color(0xFF1A1A2E),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Text(
                            'steps',
                            style: TextStyle(
                              color: Color(0xFF9E9E9E),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right column
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    flex: 2,
                    child: _BentoCard(
                      color: const Color(0xFFFFF8E1),
                      opacity: 1.0,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.verified_rounded,
                              color: Color(0xFFF59E0B), size: 22),
                          SizedBox(height: 4),
                          Text(
                            'Dr. Rahman',
                            style: TextStyle(
                              color: Color(0xFF1A1A2E),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Verified',
                            style: TextStyle(
                              color: Color(0xFFF59E0B),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    flex: 3,
                    child: _BentoCard(
                      color: const Color(0xFF1A1A2E),
                      opacity: 1.0,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.event_available_rounded,
                            color: Colors.white.withOpacity(0.85),
                            size: 22,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Appointment',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Tomorrow\n10:30 AM',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF9E9E9E),
                              fontSize: 10,
                              height: 1.3,
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
      },
    );
  }
}

class _BentoCard extends StatelessWidget {
  final Color color;
  final double opacity;
  final Widget child;
  const _BentoCard(
      {required this.color, required this.opacity, required this.child});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

// ── PAGE 2: Security Setup ────────────────────────────────────────────────────
class _SecurityPage extends StatelessWidget {
  final VoidCallback onNext;
  const _SecurityPage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back / step indicator
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Step 2 of 3',
                      style: TextStyle(
                        color: Color(0xFF9E9E9E),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              // Large fingerprint icon with glow ring
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00897B).withOpacity(0.12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00897B).withOpacity(0.3),
                        blurRadius: 32,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.fingerprint_rounded,
                    size: 64,
                    color: Color(0xFF00897B),
                  ),
                ),
              ),
              const SizedBox(height: 36),
              const Text(
                'Secure by\nDesign',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.15,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Your health data is protected end-to-end. Only you — and the care team you authorize — can access it.',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withOpacity(0.6),
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 32),
              // Security feature list
              _SecurityFeature(
                icon: Icons.fingerprint_rounded,
                label: 'Biometric Lock',
                description: 'Face ID or fingerprint secures every session',
              ),
              const SizedBox(height: 12),
              _SecurityFeature(
                icon: Icons.lock_rounded,
                label: 'AES-256 Encryption',
                description: 'Clinical data encrypted on-device before storage',
              ),
              const SizedBox(height: 12),
              _SecurityFeature(
                icon: Icons.block_rounded,
                label: 'Never Sold',
                description: 'Your data is never shared with advertisers',
              ),
              const Spacer(),
              _PrimaryButton(
                label: 'Enable Protection',
                icon: Icons.shield_rounded,
                onPressed: onNext,
                backgroundColor: const Color(0xFF00897B),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: onNext,
                  child: Text(
                    'Set up later in Privacy Settings',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecurityFeature extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;

  const _SecurityFeature({
    required this.icon,
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF00897B).withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF00897B), size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── PAGE 3: Profile Setup ─────────────────────────────────────────────────────
class _ProfilePage extends StatefulWidget {
  final VoidCallback onFinish;
  const _ProfilePage({required this.onFinish});

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage> {
  final _nameController = TextEditingController();
  final _syncCodeController = TextEditingController();
  int _roleIndex = 0; // 0 = Patient, 1 = Caregiver

  @override
  void dispose() {
    _nameController.dispose();
    _syncCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        color: const Color(0xFFF6F7FB),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Step chip
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2F1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Step 3 of 3',
                    style: TextStyle(
                      color: Color(0xFF00897B),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Set Up Your\nPassbook',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E),
                    height: 1.15,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tell us a little about yourself. You can update this anytime in Profile.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF9E9E9E),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                // Name field
                const _FieldLabel('Your Name'),
                const SizedBox(height: 8),
                _TextField(
                  controller: _nameController,
                  hint: 'e.g. Arif Hossain',
                  icon: Icons.person_outline_rounded,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 20),
                // Role selector
                const _FieldLabel('I am a'),
                const SizedBox(height: 8),
                _RoleSelector(
                  selectedIndex: _roleIndex,
                  onChanged: (i) => setState(() => _roleIndex = i),
                ),
                const SizedBox(height: 20),
                // Doctor sync code
                const _FieldLabel('Doctor Sync Code  (optional)'),
                const SizedBox(height: 8),
                _TextField(
                  controller: _syncCodeController,
                  hint: 'Ask your doctor for their 6-digit code',
                  icon: Icons.qr_code_rounded,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                ),
                const SizedBox(height: 8),
                const Text(
                  'You can always add this later from My Doctors.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFFAAAAAA),
                  ),
                ),
                const SizedBox(height: 40),
                _PrimaryButton(
                  label: 'Start My VitalPath',
                  icon: Icons.favorite_rounded,
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    widget.onFinish();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF6B7280),
        letterSpacing: 0.1,
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;
  final int? maxLength;

  const _TextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      maxLength: maxLength,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 14),
        prefixIcon: Icon(icon, color: const Color(0xFF00897B), size: 20),
        counterText: '',
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00897B), width: 1.5),
        ),
      ),
    );
  }
}

class _RoleSelector extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _RoleSelector(
      {required this.selectedIndex, required this.onChanged});

  static const _roles = [
    ('Patient', Icons.person_rounded),
    ('Caregiver', Icons.favorite_border_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_roles.length, (i) {
        final selected = i == selectedIndex;
        final (label, icon) = _roles[i];
        return Expanded(
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(i);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(right: i == 0 ? 8 : 0),
              padding:
                  const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF00897B)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF00897B)
                      : Colors.grey.shade200,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    icon,
                    color:
                        selected ? Colors.white : const Color(0xFF9E9E9E),
                    size: 22,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color:
                          selected ? Colors.white : const Color(0xFF9E9E9E),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────
class _FeatureBullet extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;

  const _FeatureBullet({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFF374151),
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? backgroundColor;

  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor:
              backgroundColor ?? const Color(0xFF00897B),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        icon: Icon(icon, size: 20, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
