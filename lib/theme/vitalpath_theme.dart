import 'dart:ui';
import 'package:flutter/material.dart';

/// VitalPath 2026 Design System
/// ─────────────────────────────────────────────────────────────────────────────
/// Clinical Calm palette × Adaptive Glassmorphism × Variable Typography
///
/// Usage:
///   Color bg = VitalPathTheme.deepCharcoal;
///   TextStyle headline = VitalPathTheme.displayLarge.copyWith(color: Colors.white);
///   Container(decoration: VitalPathTheme.darkGradient);
class VitalPathTheme {
  VitalPathTheme._();

  // ── Palette ─────────────────────────────────────────────────────────────────
  static const Color deepCharcoal  = Color(0xFF0F1923); // primary dark bg
  static const Color navyDark      = Color(0xFF141E2D); // card dark bg
  static const Color electricTeal  = Color(0xFF00E5CC); // electric accent
  static const Color clinicalTeal  = Color(0xFF00897B); // brand primary
  static const Color frostedWhite  = Color(0xF2FFFFFF); // 95% white
  static const Color verifiedGold  = Color(0xFFF59E0B); // verified data
  static const Color alertAmber    = Color(0xFFFB8C00); // warning
  static const Color softGrey      = Color(0xFF6B7280); // body text
  static const Color lightSurface  = Color(0xFFF6F7FB); // light screen bg
  static const Color errorRed      = Color(0xFFEF5350);

  // ── Semantic aliases ─────────────────────────────────────────────────────────
  static const Color primary   = clinicalTeal;
  static const Color accent    = electricTeal;
  static const Color onDark    = frostedWhite;
  static const Color onLight   = deepCharcoal;

  // ── Glass layer constants ─────────────────────────────────────────────────────
  // Dark glass (on deep-charcoal / gradient backgrounds)
  static Color glassDarkSurface      = Colors.white.withValues(alpha: 0.07);
  static Color glassDarkBorder       = Colors.white.withValues(alpha: 0.13);
  static Color glassDarkSurfaceHover = Colors.white.withValues(alpha: 0.12);

  // Light glass (on light / frosted-white backgrounds)
  static Color glassLightSurface = Colors.white.withValues(alpha: 0.70);
  static Color glassLightBorder  = Colors.white.withValues(alpha: 0.55);

  // Accent glass (teal-tinted card)
  static Color glassAccentSurface = clinicalTeal.withValues(alpha: 0.18);
  static Color glassAccentBorder  = clinicalTeal.withValues(alpha: 0.35);

  // ── Gradients ─────────────────────────────────────────────────────────────────
  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F1923), Color(0xFF141E2D), Color(0xFF0A1628)],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient tealGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00897B), Color(0xFF00695C)],
  );

  static const LinearGradient electricGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00E5CC), Color(0xFF00897B)],
  );

  static const RadialGradient tealGlow = RadialGradient(
    colors: [Color(0x4000E5CC), Color(0x0000897B), Colors.transparent],
    stops: [0.0, 0.5, 1.0],
  );

  // ── Variable Typography ───────────────────────────────────────────────────────
  // Display — 120fps hero titles, ultra-heavy (w900)
  static const TextStyle displayLarge = TextStyle(
    fontSize: 42,
    fontWeight: FontWeight.w900,
    letterSpacing: -2.0,
    height: 1.05,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.2,
    height: 1.1,
  );

  // Headline — section titles
  static const TextStyle headlineLarge = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    height: 1.15,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.2,
  );

  // Body
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    height: 1.6,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    height: 1.5,
  );

  // Labels
  static const TextStyle labelLarge = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
  );

  static const TextStyle labelMedium = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
  );

  // ── Variable weight tokens ─────────────────────────────────────────────────────
  // Primary CTA — heaviest weight to demand attention
  static const TextStyle ctaPrimary = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w900,
    letterSpacing: 0.3,
    height: 1.0,
  );

  // Secondary action — medium weight to recede
  static const TextStyle ctaSecondary = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  // Verified data — gold, w700 (doctor-confirmed)
  static const TextStyle verifiedData = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: verifiedGold,
    letterSpacing: 0.2,
  );

  // Patient data — grey, w500 (self-reported)
  static const TextStyle patientData = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: softGrey,
    letterSpacing: 0.1,
  );

  // Bento card metric — large, bold number
  static const TextStyle bentoMetric = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    height: 1.0,
  );

  static const TextStyle bentoLabel = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
  );

  // ── Shadows ────────────────────────────────────────────────────────────────────
  static List<BoxShadow> tealGlowShadow({double intensity = 1.0}) => [
        BoxShadow(
          color: clinicalTeal.withValues(alpha: 0.35 * intensity),
          blurRadius: 24 * intensity,
          spreadRadius: 0,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> electricGlowShadow({double intensity = 1.0}) => [
        BoxShadow(
          color: electricTeal.withValues(alpha: 0.4 * intensity),
          blurRadius: 32 * intensity,
          spreadRadius: 4 * intensity,
        ),
      ];

  static const List<BoxShadow> cardShadow = [
        BoxShadow(
          color: Color(0x18000000),
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
      ];
}
