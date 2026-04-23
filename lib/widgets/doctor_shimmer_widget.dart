/// doctor_shimmer_widget.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Shimmer skeleton cards displayed while the doctor list loads from Firebase.
///
/// Blueprint §7 — "Antigravity" high-performance UX:
///   A shimmer effect maintains perceived responsiveness while async data
///   arrives, avoiding blank states that feel broken.
///
/// Architecture:
///   A single [AnimationController] drives the gradient sweep across all
///   shimmer cards simultaneously — one ticker, multiple consumers via
///   [AnimatedBuilder], zero jitter between cards.
///
///   [RepaintBoundary] isolates each card from the scroll tree so the
///   gradient animation never triggers full-screen repaints.
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

class DoctorShimmerList extends StatefulWidget {
  final int count;
  const DoctorShimmerList({super.key, this.count = 4});

  @override
  State<DoctorShimmerList> createState() => _DoctorShimmerListState();
}

class _DoctorShimmerListState extends State<DoctorShimmerList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _anim = Tween<double>(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.count,
      itemBuilder: (_, __) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: _anim,
          builder: (_, __) => _ShimmerDoctorCard(shimmerX: _anim.value),
        ),
      ),
    );
  }
}

// ── Shimmer card skeleton ─────────────────────────────────────────────────────
class _ShimmerDoctorCard extends StatelessWidget {
  final double shimmerX;
  const _ShimmerDoctorCard({required this.shimmerX});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey[200]!, width: 1),
        boxShadow: const [
          BoxShadow(
              color: Color(0x07000000), blurRadius: 8, offset: Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Doctor header row ─────────────────────────────────────────────
          Row(
            children: [
              _shimmerBox(52, 52, shimmerX, borderRadius: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _shimmerBox(140, 14, shimmerX),
                    const SizedBox(height: 8),
                    _shimmerBox(100, 11, shimmerX),
                  ],
                ),
              ),
              _shimmerBox(72, 26, shimmerX, borderRadius: 20),
            ],
          ),
          const SizedBox(height: 14),
          // ── Clinic name row ───────────────────────────────────────────────
          _shimmerBox(double.infinity, 11, shimmerX),
          const SizedBox(height: 16),
          // ── CTA button row ────────────────────────────────────────────────
          const Divider(height: 1),
          const SizedBox(height: 14),
          Center(child: _shimmerBox(180, 14, shimmerX)),
        ],
      ),
    );
  }

  Widget _shimmerBox(
    double width,
    double height,
    double sx, {
    double borderRadius = 6,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment(sx - 1, 0),
          end: Alignment(sx + 1, 0),
          colors: const [
            Color(0xFFECECF0),
            Color(0xFFF8F8FC),
            Color(0xFFECECF0),
          ],
        ),
      ),
    );
  }
}
