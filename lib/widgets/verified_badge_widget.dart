/// verified_badge_widget.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// The "Clinical Lock" visual indicator for doctor-verified health records.
///
/// Design spec (Blueprint §3.1 — Clinical Integrity):
///   • Displays a teal/clinical-green stethoscope icon alongside "Verified".
///   • Available in two sizes: [VerifiedBadgeSize.compact] (inline on cards)
///     and [VerifiedBadgeSize.full] (detail screens and empty state banners).
///   • All constructors are `const` for zero-cost tree inclusion.
///   • The badge is intentionally non-interactive — it is informational only.
///     Tapping to understand WHY a record is locked is handled by the parent
///     card's [ClinicalLockModal], not by this widget.
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

enum VerifiedBadgeSize { compact, full }

class VerifiedBadgeWidget extends StatelessWidget {
  final VerifiedBadgeSize size;

  const VerifiedBadgeWidget({
    super.key,
    this.size = VerifiedBadgeSize.compact,
  });

  /// Shorthand constructor for the compact inline badge used on list cards.
  const VerifiedBadgeWidget.compact({super.key})
      : size = VerifiedBadgeSize.compact;

  /// Shorthand constructor for the larger badge on detail / empty-state views.
  const VerifiedBadgeWidget.full({super.key}) : size = VerifiedBadgeSize.full;

  // ── Sizing constants ──────────────────────────────────────────────────────
  static const _compactIconSize = 13.0;
  static const _fullIconSize = 18.0;
  static const _compactFontSize = 10.5;
  static const _fullFontSize = 13.0;
  static const _compactPaddingH = 7.0;
  static const _compactPaddingV = 3.0;
  static const _fullPaddingH = 10.0;
  static const _fullPaddingV = 5.0;
  static const _compactRadius = 6.0;
  static const _fullRadius = 8.0;
  static const _compactSpacing = 4.0;
  static const _fullSpacing = 6.0;

  // ── Brand colour — clinical teal ──────────────────────────────────────────
  static const Color _badgeBackground = Color(0xFFE6F7F4);
  static const Color _badgeForeground = Color(0xFF00897B); // teal[600]

  @override
  Widget build(BuildContext context) {
    final isCompact = size == VerifiedBadgeSize.compact;
    final iconSize = isCompact ? _compactIconSize : _fullIconSize;
    final fontSize = isCompact ? _compactFontSize : _fullFontSize;
    final paddingH = isCompact ? _compactPaddingH : _fullPaddingH;
    final paddingV = isCompact ? _compactPaddingV : _fullPaddingV;
    final radius = isCompact ? _compactRadius : _fullRadius;
    final spacing = isCompact ? _compactSpacing : _fullSpacing;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _badgeBackground,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _badgeForeground.withOpacity(0.35), width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.medical_services_rounded,
              size: iconSize,
              color: _badgeForeground,
            ),
            SizedBox(width: spacing),
            Text(
              'Verified',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: _badgeForeground,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
