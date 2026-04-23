/// celebration_overlay.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Celebratory particle burst shown when the user hits 10,000 steps.
///
/// Blueprint §4 / §7 — "Celebratory Haptics":
///   "Use 'Celebratory Haptics' and a visual burst animation when the user
///    hits their 10,000-step goal."
///
/// Architecture:
///   [CelebrationOverlay.show] injects an [OverlayEntry] above all other
///   widgets — including any bottom sheet or dialog. The caller must also fire
///   [HapticService().goalSuccess()] at the same moment.
///
///   The animation runs once for 2.6 seconds and removes itself. A "Goal
///   Reached!" banner slides down from the top and fades out at 1.8s.
///
/// Performance:
///   • [CustomPaint] + [AnimatedBuilder] — no setState calls during animation.
///   • [RepaintBoundary] isolates particle repaints from the rest of the tree.
///   • Particles are pre-generated in [initState] — zero allocation during
///     the animation loop.
///   • [shouldRepaint] checks only the [_t] value — O(1).
/// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

import 'package:flutter/material.dart';

// ── Entry point ───────────────────────────────────────────────────────────────
class CelebrationOverlay {
  static OverlayEntry show(BuildContext context) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _CelebrationWidget(onDone: () {
        entry.remove();
      }),
    );
    Overlay.of(context).insert(entry);
    return entry;
  }
}

// ── Celebration widget ────────────────────────────────────────────────────────
class _CelebrationWidget extends StatefulWidget {
  final VoidCallback onDone;
  const _CelebrationWidget({required this.onDone});

  @override
  State<_CelebrationWidget> createState() => _CelebrationState();
}

class _CelebrationState extends State<_CelebrationWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Particle> _particles;

  // Banner: slides in from top and fades at 70% through animation.
  late final Animation<Offset> _bannerSlide;
  late final Animation<double> _bannerFade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..forward().whenComplete(widget.onDone);

    _particles = _generateParticles(count: 60);

    _bannerSlide = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.25, curve: Curves.elasticOut),
    ));

    _bannerFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.65, 1.0, curve: Curves.easeIn),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            final t = _ctrl.value;
            return Stack(
              children: [
                // ── Particle layer ───────────────────────────────────────────
                CustomPaint(
                  size: size,
                  painter: _ParticlePainter(
                    particles: _particles,
                    t: t,
                    origin: Offset(size.width / 2, size.height * 0.38),
                  ),
                ),

                // ── Goal banner ──────────────────────────────────────────────
                Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  left: 24,
                  right: 24,
                  child: FadeTransition(
                    opacity: _bannerFade,
                    child: SlideTransition(
                      position: _bannerSlide,
                      child: _GoalBanner(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Goal reached banner ───────────────────────────────────────────────────────
class _GoalBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00897B), Color(0xFF004D40)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00897B).withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '10,000 Steps!',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Daily goal reached — outstanding!',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
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

// ── Particle data ─────────────────────────────────────────────────────────────
class _Particle {
  final double angle;   // radians — direction of travel
  final double speed;   // 0.0–1.0 relative to screen height
  final double size;    // radius in logical pixels
  final Color color;
  final double lifespan; // 0.5–1.0 — when this particle fully fades

  const _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
    required this.lifespan,
  });
}

// ── Particle painter ──────────────────────────────────────────────────────────
class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;           // 0.0 to 1.0
  final Offset origin;      // emission origin (centre of ring widget)

  const _ParticlePainter({
    required this.particles,
    required this.t,
    required this.origin,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      // Age within this particle's lifespan; skip if expired.
      final age = (t / p.lifespan).clamp(0.0, 1.0);
      final opacity = (1.0 - age * age).clamp(0.0, 1.0);
      if (opacity <= 0) continue;

      // Travel: linear trajectory + downward gravity.
      final travel = p.speed * t * size.height * 0.62;
      final gravity = 420 * t * t; // pixels — parabolic drop
      final x = origin.dx + math.cos(p.angle) * travel;
      final y = origin.dy + math.sin(p.angle) * travel + gravity;

      // Shrink as the particle ages.
      final radius = p.size * (1.0 - age * 0.45);

      canvas.drawCircle(
        Offset(x, y),
        radius.clamp(0.5, 20),
        Paint()
          ..color = p.color.withOpacity(opacity)
          ..maskFilter = age < 0.3
              ? const MaskFilter.blur(BlurStyle.normal, 1.5)
              : null,
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.t != t;
}

// ── Particle generator ────────────────────────────────────────────────────────
List<_Particle> _generateParticles({required int count}) {
  final rng = math.Random(42); // fixed seed → deterministic, no jitter
  const colors = [
    Color(0xFF00897B), // primary teal
    Color(0xFF4DB6AC), // mid teal
    Color(0xFFB2DFDB), // light teal
    Color(0xFFFFD54F), // gold
    Color(0xFFFFF176), // pale gold
    Color(0xFFFFFFFF), // white
    Color(0xFF80CBC4), // teal-mint
    Color(0xFFE0F2F1), // very light teal
  ];

  return List.generate(count, (i) {
    // Spread across full 360° with a slight upward bias (more particles
    // launched upward than straight down for a fountain silhouette).
    final raw = rng.nextDouble() * 2 * math.pi;
    // Weight angles toward the upper half-circle.
    final angle = raw < math.pi
        ? -(raw * 0.9 + math.pi * 0.05) // upper hemisphere, tilted
        : raw;

    return _Particle(
      angle: angle,
      speed: 0.15 + rng.nextDouble() * 0.55,
      size: 3.5 + rng.nextDouble() * 9.0,
      color: colors[rng.nextInt(colors.length)],
      lifespan: 0.55 + rng.nextDouble() * 0.45, // 0.55–1.0
    );
  });
}
