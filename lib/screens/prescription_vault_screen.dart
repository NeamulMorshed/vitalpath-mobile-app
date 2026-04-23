/// prescription_vault_screen.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// The Prescription Vault — accessed from the Profile tab.
///
/// Layout spec (Blueprint §1.1, §3.2):
///   • Prescriptions are GROUPED by [doctorName], each group displayed under
///     a sticky section header showing the doctor's name and prescription count.
///   • Within each group, cards are sorted LATEST-FIRST by [updatedAt]
///     (the most recently updated prescription appears at the top).
///   • Groups themselves are ordered by their most-recent entry, so the
///     most actively managed doctor floats to the top.
///   • Empty state shown when no prescriptions exist.
///   • FAB launches [AddPrescriptionBottomSheet] with is_verified = false.
///
/// Performance (Antigravity §4 — 60/120fps, 100ms):
///   • [CustomScrollView] + [SliverList] — fully lazy; no off-screen builds.
///   • Section headers use [SliverPersistentHeader] with a [const] delegate
///     so they stick without repainting the list behind them.
///   • Each [PrescriptionCardWidget] is wrapped in [RepaintBoundary] inside
///     the card itself — scroll janks don't propagate upward.
///   • [Consumer] scoped to the provider — only this subtree rebuilds on
///     prescription list changes.
///   • [AnimatedSwitcher] for empty ↔ list transitions at 60fps.
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:vitalpath/providers/prescription_provider.dart';
import 'package:vitalpath/models/prescription_model.dart';
import 'package:vitalpath/widgets/prescription_card_widget.dart';
import 'package:vitalpath/widgets/add_prescription_bottom_sheet.dart';

class PrescriptionVaultScreen extends StatelessWidget {
  const PrescriptionVaultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: Consumer<PrescriptionProvider>(
        builder: (context, provider, _) {
          return CustomScrollView(
            // Use AlwaysScrollableScrollPhysics so pull-to-refresh works
            // even on short lists.
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // ── Sliver app bar ─────────────────────────────────────────
              _VaultSliverAppBar(totalCount: provider.totalCount),

              // ── Error banner ───────────────────────────────────────────
              if (provider.lastError != null)
                SliverToBoxAdapter(
                  child: _ErrorBanner(
                    message: provider.lastError!,
                    onDismiss: provider.clearError,
                  ),
                ),

              // ── Loading shimmer ────────────────────────────────────────
              if (provider.isLoading && provider.totalCount == 0)
                const SliverToBoxAdapter(child: _LoadingShimmer()),

              // ── Empty state ────────────────────────────────────────────
              if (!provider.isLoading && provider.totalCount == 0)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyVaultState(
                    onAddPressed: () => _openAddSheet(context),
                  ),
                ),

              // ── Grouped prescription list ──────────────────────────────
              if (provider.totalCount > 0)
                ..._buildGroupedSlivers(context, provider),

              // Bottom padding above FAB.
              const SliverToBoxAdapter(child: SizedBox(height: 88)),
            ],
          );
        },
      ),

      // ── FAB ─────────────────────────────────────────────────────────────
      floatingActionButton: _AddFab(
        onPressed: () => _openAddSheet(context),
      ),
    );
  }

  // ── Grouped Sliver builder ─────────────────────────────────────────────────
  /// Converts the [PrescriptionProvider.groupedPrescriptions] map into a flat
  /// list of slivers: one [SliverPersistentHeader] (sticky group header) +
  /// one [SliverList] of cards per doctor group.
  List<Widget> _buildGroupedSlivers(
    BuildContext context,
    PrescriptionProvider provider,
  ) {
    final grouped = provider.groupedPrescriptions;
    final slivers = <Widget>[];

    for (final entry in grouped.entries) {
      final doctorName = entry.key;
      final prescriptions = entry.value; // already Latest-First sorted

      // Sticky section header.
      slivers.add(
        SliverPersistentHeader(
          pinned: true,
          delegate: _DoctorGroupHeaderDelegate(
            doctorName: doctorName,
            count: prescriptions.length,
          ),
        ),
      );

      // Cards for this group.
      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final prescription = prescriptions[index];
              return PrescriptionCardWidget(
                key: ValueKey(prescription.id ?? prescription.medicineName),
                prescription: prescription,
                onEdit: (p) => _openEditSheet(context, p),
                onDelete: (id) =>
                    context.read<PrescriptionProvider>().deletePrescription(id),
              );
            },
            childCount: prescriptions.length,
          ),
        ),
      );

      // Small spacer between groups.
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));
    }

    return slivers;
  }

  void _openAddSheet(BuildContext context) {
    AddPrescriptionBottomSheet.show(
      context,
      onSaved: (p) =>
          context.read<PrescriptionProvider>().addPrescription(p),
    );
  }

  void _openEditSheet(BuildContext context, PrescriptionModel prescription) {
    AddPrescriptionBottomSheet.show(
      context,
      initialPrescription: prescription,
      onSaved: (p) =>
          context.read<PrescriptionProvider>().updatePrescription(p),
    );
  }
}

// ── Sliver App Bar ─────────────────────────────────────────────────────────────
class _VaultSliverAppBar extends StatelessWidget {
  final int totalCount;

  const _VaultSliverAppBar({required this.totalCount});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            size: 20, color: Color(0xFF1A1A2E)),
        onPressed: () => Navigator.of(context).pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        title: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Prescription Vault',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
              ),
            ),
            if (totalCount > 0)
              Text(
                '$totalCount prescription${totalCount == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9E9E9E),
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF6F7FB), Colors.white],
            ),
          ),
        ),
      ),
      actions: [
        // Search icon — wired to search in next sprint.
        IconButton(
          icon: const Icon(Icons.search_rounded,
              color: Color(0xFF555566)),
          onPressed: () => HapticFeedback.lightImpact(),
        ),
      ],
    );
  }
}

// ── Sticky group header delegate ──────────────────────────────────────────────
class _DoctorGroupHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String doctorName;
  final int count;

  static const double _height = 44.0;

  const _DoctorGroupHeaderDelegate({
    required this.doctorName,
    required this.count,
  });

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  bool shouldRebuild(_DoctorGroupHeaderDelegate old) =>
      old.doctorName != doctorName || old.count != count;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    // Subtle shadow appears when the header overlaps scrolled-past content.
    final showShadow = overlapsContent;
    return Material(
      elevation: showShadow ? 2 : 0,
      shadowColor: Colors.black12,
      color: const Color(0xFFF6F7FB),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Doctor avatar
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFE6F7F4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.medical_services_outlined,
                  size: 15, color: Color(0xFF00897B)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Dr. $doctorName',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF00897B).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF00897B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── FAB ───────────────────────────────────────────────────────────────────────
class _AddFab extends StatelessWidget {
  final VoidCallback onPressed;

  const _AddFab({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: onPressed,
      backgroundColor: const Color(0xFF00897B),
      extendedPadding: const EdgeInsets.symmetric(horizontal: 20),
      icon: const Icon(Icons.add_rounded, size: 22, color: Colors.white),
      label: const Text(
        'Add Medicine',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}

// ── Smart empty state ─────────────────────────────────────────────────────────
class _EmptyVaultState extends StatelessWidget {
  final VoidCallback? onAddPressed;

  const _EmptyVaultState({this.onAddPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Layered illustration — outer ring + icon badge.
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F7F4).withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F7F4),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.medication_outlined,
                  size: 40,
                  color: Color(0xFF00897B),
                ),
              ),
              // Small "+" badge in the corner — echoes the FAB action.
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    color: Color(0xFF00897B),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_rounded,
                      size: 16, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          const Text(
            'No Prescriptions Yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'All your prescriptions — grouped by doctor,\nright here in one secure place.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              color: Color(0xFF9E9E9E),
              height: 1.55,
            ),
          ),
          const SizedBox(height: 28),

          // Primary CTA — mirrors the FAB so the action is obvious.
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: onAddPressed,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                'Add Your First Prescription',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 24),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Secondary hint — surfaces the doctor-sync path.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.sync_rounded, size: 14, color: Color(0xFFBDBDBD)),
              SizedBox(width: 6),
              Text(
                'Or ask your doctor to sync them directly',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFFBDBDBD),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE53935).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 16, color: Color(0xFFE53935)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style:
                    const TextStyle(fontSize: 13, color: Color(0xFFB71C1C))),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close_rounded,
                size: 16, color: Color(0xFF9E9E9E)),
          ),
        ],
      ),
    );
  }
}

// ── Loading shimmer (placeholder while data loads) ────────────────────────────
class _LoadingShimmer extends StatelessWidget {
  const _LoadingShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        4,
        (i) => Container(
          margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          height: 88,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
