/// success_toast.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Lightweight 1.5-second overlay toast confirming a successful dose log.
///
/// Design:
///   • Slides in from above (200ms easeOutCubic) → holds → fades out (300ms).
///   • Dark pill card (not red/orange — this is a WIN, not a warning).
///   • Shows medicine name + dose + "Logged" confirmation.
///   • IgnorePointer so it never blocks interaction below.
///   • RepaintBoundary isolates the animation from the rest of the tree.
///   • AnimatedBuilder drives all motion — zero setState during animation.
///
/// Usage:
///   SuccessToast.show(context, medicineName: 'Metformin', dose: '500mg');
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

class SuccessToast {
  static OverlayEntry? _current;

  static void show(
    BuildContext context, {
    required String medicineName,
    required String dose,
  }) {
    _current?.remove();
    _current = null;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _SuccessToastWidget(
        medicineName: medicineName,
        dose: dose,
        onDone: () {
          if (entry.mounted) entry.remove();
          if (_current == entry) _current = null;
        },
      ),
    );
    _current = entry;
    Overlay.of(context).insert(entry);
  }
}

// ── Animated toast host ───────────────────────────────────────────────────────
class _SuccessToastWidget extends StatefulWidget {
  final String medicineName;
  final String dose;
  final VoidCallback onDone;

  const _SuccessToastWidget({
    required this.medicineName,
    required this.dose,
    required this.onDone,
  });

  @override
  State<_SuccessToastWidget> createState() => _SuccessToastWidgetState();
}

class _SuccessToastWidgetState extends State<_SuccessToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    // Total lifecycle: 1 500 ms.
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Opacity: fade in 0→200ms, hold 200→1200ms, fade out 1200→1500ms.
    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 13, // 200/1500
      ),
      TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: 67, // 1000/1500
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 20, // 300/1500
      ),
    ]).animate(_ctrl);

    // Slide: enters from above (Offset.y = -1.0) → settles at 0.
    _slide = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween(
          begin: const Offset(0, -1.0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 13, // 200/1500
      ),
      TweenSequenceItem(
        tween: ConstantTween(Offset.zero),
        weight: 87, // 1300/1500
      ),
    ]).animate(_ctrl);

    _ctrl.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;
    return Positioned(
      top: safeTop + 10,
      left: 20,
      right: 20,
      child: RepaintBoundary(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, child) => SlideTransition(
              position: _slide,
              child: Opacity(opacity: _opacity.value, child: child),
            ),
            // Static content pre-built outside the AnimatedBuilder closure —
            // the builder only re-runs layout for opacity/slide, not this tree.
            child: _ToastContent(
              medicineName: widget.medicineName,
              dose: widget.dose,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Visual card ───────────────────────────────────────────────────────────────
class _ToastContent extends StatelessWidget {
  final String medicineName;
  final String dose;

  const _ToastContent({
    required this.medicineName,
    required this.dose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x44000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            // Check icon badge
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF00897B).withOpacity(0.22),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                size: 22,
                color: Color(0xFF4DB6AC),
              ),
            ),
            const SizedBox(width: 13),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    medicineName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$dose · Logged successfully',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF4DB6AC),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Trailing dose icon
            const Icon(
              Icons.medication_rounded,
              size: 18,
              color: Color(0xFF37474F),
            ),
          ],
        ),
      ),
    );
  }
}
