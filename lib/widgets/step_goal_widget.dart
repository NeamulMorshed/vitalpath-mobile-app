/// step_goal_widget.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Real-time circular step-progress ring for the Home dashboard.
///
/// Blueprint §3.1 — "Implement a high-performance circular progress bar for
/// 'Step Goals' (10,000 steps default).  Use a StreamBuilder pattern to ensure
/// the bar fills in real-time as background data arrives from HealthKit /
/// Google Fit."
///
/// Architecture:
///   [StepGoalWidget]
///     └─ StreamBuilder<int>               listens to HealthService.stepsStream
///          └─ _AnimatedRingWrapper         holds AnimationController
///               └─ AnimatedBuilder
///                    └─ CustomPaint(_RingPainter)   draws the arc at 120fps
///
/// 120fps strategy:
///   • [RepaintBoundary] isolates the ring from the rest of the scroll tree.
///   • [_RingPainter] overrides [shouldRepaint] with a value comparison —
///     no unnecessary repaints.
///   • [AnimationController] drives a [Tween<double>] that smoothly interpolates
///     between the previous progress value and the new stream value over 600ms,
///     so step count "fills in" rather than snapping.
///   • All layout is fixed-size; no layout passes occur during animation.
/// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:vitalpath/services/health_service.dart';

// ── Public entry point ────────────────────────────────────────────────────────
class StepGoalWidget extends StatelessWidget {
  final Stream<int> stepsStream;
  final int goal;

  const StepGoalWidget({
    super.key,
    required this.stepsStream,
    this.goal = HealthService.defaultStepGoal,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: StreamBuilder<int>(
        stream: stepsStream,
        initialData: 0,
        builder: (context, snapshot) {
          final steps = snapshot.data ?? 0;
          final progress = (steps / goal).clamp(0.0, 1.0);
          final goalMet = steps >= goal;

          return _AnimatedRingWrapper(
            progress: progress,
            steps: steps,
            goal: goal,
            goalMet: goalMet,
            hasError: snapshot.hasError,
          );
        },
      ),
    );
  }
}

// ── Animated wrapper (holds AnimationController) ──────────────────────────────
class _AnimatedRingWrapper extends StatefulWidget {
  final double progress;
  final int steps;
  final int goal;
  final bool goalMet;
  final bool hasError;

  const _AnimatedRingWrapper({
    required this.progress,
    required this.steps,
    required this.goal,
    required this.goalMet,
    required this.hasError,
  });

  @override
  State<_AnimatedRingWrapper> createState() => _AnimatedRingWrapperState();
}

class _AnimatedRingWrapperState extends State<_AnimatedRingWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _progressAnim;
  double _previousProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _progressAnim = Tween<double>(
      begin: 0.0,
      end: widget.progress,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    _controller.forward();
    _previousProgress = widget.progress;
  }

  @override
  void didUpdateWidget(_AnimatedRingWrapper old) {
    super.didUpdateWidget(old);
    if (old.progress != widget.progress) {
      // Tween from wherever the animation currently is.
      _progressAnim = Tween<double>(
        begin: _previousProgress,
        end: widget.progress,
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ));
      _controller
        ..reset()
        ..forward();
      _previousProgress = widget.progress;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.goalMet
              ? [const Color(0xFF00897B), const Color(0xFF004D40)]
              : [const Color(0xFF1A1A2E), const Color(0xFF16213E)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (widget.goalMet
                    ? const Color(0xFF00897B)
                    : const Color(0xFF1A1A2E))
                .withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── Ring ──────────────────────────────────────────────────────────
          AnimatedBuilder(
            animation: _progressAnim,
            builder: (_, __) => CustomPaint(
              size: const Size(110, 110),
              painter: _RingPainter(
                progress: _progressAnim.value,
                goalMet: widget.goalMet,
              ),
              child: SizedBox(
                width: 110,
                height: 110,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatSteps(widget.steps),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Text(
                        'steps',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 20),

          // ── Stats column ──────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Goal label
                Text(
                  widget.goalMet ? '🎯 Goal Reached!' : 'Daily Step Goal',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: widget.goalMet
                        ? Colors.white
                        : Colors.white.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 6),

                // Step count large
                Text(
                  '${_formatSteps(widget.steps)} / ${_formatSteps(widget.goal)}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),

                // Remaining bar
                AnimatedBuilder(
                  animation: _progressAnim,
                  builder: (_, __) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _progressAnim.value,
                      backgroundColor: Colors.white.withOpacity(0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.goalMet
                            ? Colors.white
                            : const Color(0xFF4DB6AC),
                      ),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Remaining steps
                Text(
                  widget.goalMet
                      ? '+${_formatSteps(widget.steps - widget.goal)} bonus steps'
                      : '${_formatSteps(widget.goal - widget.steps)} steps to go',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.55),
                    fontWeight: FontWeight.w500,
                  ),
                ),

                // Error nudge
                if (widget.hasError) ...[
                  const SizedBox(height: 6),
                  const Text(
                    '⚠ Health data unavailable',
                    style: TextStyle(fontSize: 11, color: Color(0xFFFF8A65)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatSteps(int n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
    }
    return n.toString();
  }
}

// ── CustomPainter — the arc ring ──────────────────────────────────────────────
class _RingPainter extends CustomPainter {
  final double progress; // 0.0 → 1.0
  final bool goalMet;

  const _RingPainter({required this.progress, required this.goalMet});

  static const double _strokeWidth = 9.0;
  static const double _startAngle = -math.pi / 2; // 12 o'clock

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - _strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // ── Background track ───────────────────────────────────────────────────
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..color = Colors.white.withOpacity(0.12),
    );

    if (progress <= 0) return;

    // ── Progress arc ───────────────────────────────────────────────────────
    final sweepAngle = 2 * math.pi * progress;

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: _startAngle,
        endAngle: _startAngle + sweepAngle,
        colors: goalMet
            ? const [Color(0xFFB2EBF2), Colors.white]
            : const [Color(0xFF26C6DA), Color(0xFF00897B)],
      ).createShader(rect);

    canvas.drawArc(
      rect,
      _startAngle,
      sweepAngle,
      false,
      progressPaint,
    );

    // ── Tip dot ────────────────────────────────────────────────────────────
    if (progress > 0.02) {
      final tipAngle = _startAngle + sweepAngle;
      final tipX = center.dx + radius * math.cos(tipAngle);
      final tipY = center.dy + radius * math.sin(tipAngle);
      canvas.drawCircle(
        Offset(tipX, tipY),
        _strokeWidth / 2,
        Paint()..color = goalMet ? Colors.white : const Color(0xFF4DB6AC),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.goalMet != goalMet;
}
