import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:vitalpath/theme/vitalpath_theme.dart';

/// Adaptive GlassCard — 3-layer Glassmorphism component.
///
/// Layer 1 (background): the blurred scene behind the card via [BackdropFilter].
/// Layer 2 (surface): semi-transparent fill — dark, light, or accent variant.
/// Layer 3 (border): 1px white/teal edge that catches light.
///
/// Usage:
///   GlassCard(child: Text('Hello'))
///   GlassCard.light(child: SomeWidget())
///   GlassCard.accent(child: SomeWidget())
class GlassCard extends StatelessWidget {
  final Widget child;
  final double blurSigma;
  final Color surfaceColor;
  final Color borderColor;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? boxShadow;
  final double borderWidth;

  const GlassCard({
    super.key,
    required this.child,
    this.blurSigma = 20.0,
    Color? surfaceColor,
    Color? borderColor,
    BorderRadius? borderRadius,
    this.padding,
    this.boxShadow,
    this.borderWidth = 1.0,
  })  : surfaceColor = surfaceColor ?? const Color(0x12FFFFFF), // ~7% white
        borderColor = borderColor ?? const Color(0x21FFFFFF),   // ~13% white
        borderRadius =
            borderRadius ?? const BorderRadius.all(Radius.circular(20));

  // ── Named constructors ────────────────────────────────────────────────────────

  /// Dark glass — for use on deep-charcoal / gradient dark backgrounds.
  const GlassCard.dark({
    super.key,
    required this.child,
    this.blurSigma = 20.0,
    BorderRadius? borderRadius,
    this.padding,
    this.boxShadow,
    this.borderWidth = 1.0,
  })  : surfaceColor = const Color(0x12FFFFFF),
        borderColor = const Color(0x21FFFFFF),
        borderRadius =
            borderRadius ?? const BorderRadius.all(Radius.circular(20));

  /// Light glass — for use on white / frosted-white backgrounds.
  const GlassCard.light({
    super.key,
    required this.child,
    this.blurSigma = 16.0,
    BorderRadius? borderRadius,
    this.padding,
    this.boxShadow,
    this.borderWidth = 1.0,
  })  : surfaceColor = const Color(0xB3FFFFFF), // 70% white
        borderColor = const Color(0x8CFFFFFF),  // 55% white
        borderRadius =
            borderRadius ?? const BorderRadius.all(Radius.circular(20));

  /// Accent glass — teal-tinted, for highlighted / active cards.
  const GlassCard.accent({
    super.key,
    required this.child,
    this.blurSigma = 20.0,
    BorderRadius? borderRadius,
    this.padding,
    this.boxShadow,
    this.borderWidth = 1.0,
  })  : surfaceColor = const Color(0x2E00897B), // ~18% teal
        borderColor = const Color(0x5900897B),  // ~35% teal
        borderRadius =
            borderRadius ?? const BorderRadius.all(Radius.circular(20));

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: borderRadius,
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: boxShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}

// ── Shimmer loader ─────────────────────────────────────────────────────────────
/// Premium shimmer effect for async loading states.
/// Dark variant for glass/dark-bg screens; light variant for white screens.
class ShimmerLoader extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final bool isDark;

  const ShimmerLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.isDark = true,
  });

  @override
  State<ShimmerLoader> createState() => _ShimmerLoaderState();
}

class _ShimmerLoaderState extends State<ShimmerLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _shimmer = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.isDark
        ? const Color(0xFF1E2D3D)
        : const Color(0xFFE8EDF2);
    final highlight = widget.isDark
        ? const Color(0xFF2E4055)
        : const Color(0xFFF4F7FA);

    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, __) => ClipRRect(
        borderRadius: widget.borderRadius,
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(_shimmer.value - 1, 0),
              end: Alignment(_shimmer.value, 0),
              colors: [base, highlight, base],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
