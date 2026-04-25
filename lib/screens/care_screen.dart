/// care_screen.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// The Care Hub — the primary daily-use screen with Medicines / Food / Activity
/// tabs. This is where patients interact with their health records most often.
///
/// Blueprint refs (§1.1, §2.2, §3.2):
///   • Medicines tab mirrors the Prescription Vault but in "daily care" context.
///   • Food tab: nutrition log entries with governance UI.
///   • Activity tab: exercise log with the [isCompleted] adherence toggle.
///   • FAB: "+ Add Medicine" — opens [AddPrescriptionBottomSheet] with
///     [is_verified] hardcoded to false and [governance_level] = patientManaged.
///
/// Performance (Antigravity §4):
///   • [AutomaticKeepAliveClientMixin] on each tab page — tab state is
///     preserved; no full rebuilds when switching tabs.
///   • [TabController] with vsync — animations use the render tree's vsync.
///   • [ListView.builder] in every tab — lazy item construction.
///   • All card widgets use [RepaintBoundary] internally.
///   • FAB uses [AnimatedSwitcher] to gracefully hide/show per active tab.
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:vitalpath/providers/prescription_provider.dart';
import 'package:vitalpath/screens/notification_settings_screen.dart';
import 'package:vitalpath/theme/vitalpath_theme.dart';
import 'package:vitalpath/models/prescription_model.dart';
import 'package:vitalpath/widgets/prescription_card_widget.dart';
import 'package:vitalpath/widgets/add_prescription_bottom_sheet.dart';

class CareScreen extends StatefulWidget {
  const CareScreen({super.key});

  @override
  State<CareScreen> createState() => _CareScreenState();
}

class _CareScreenState extends State<CareScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Track the current tab to conditionally show/hide the FAB.
  int _activeTab = 0;

  static const _tabs = ['Medicines', 'Vault', 'Nutrition'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() => _activeTab = _tabController.index);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VitalPathTheme.lightSurface,
      appBar: _buildAppBar(context),
      body: TabBarView(
        controller: _tabController,
        // Disable swipe on small velocity to prevent accidental tab switches
        // while scrolling — keeps 60fps scroll feel intact.
        physics: const ClampingScrollPhysics(),
        children: const [
          _MedicinesTab(),
          _VaultTab(),
          _NutritionTab(),
        ],
      ),
      // FAB is only shown on the Medicines tab (index 0).
      floatingActionButton: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, anim) => ScaleTransition(
          scale: anim,
          child: child,
        ),
        child: _activeTab == 2
            ? _LogNutritionFab(
                key: const ValueKey('nutrition-fab'),
                onPressed: () => _showNutritionComingSoon(context),
              )
            : _AddMedicineFab(
                key: const ValueKey('medicines-fab'),
                onPressed: () => _openAddSheet(context),
              ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Care',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: VitalPathTheme.deepCharcoal,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none_rounded,
              color: VitalPathTheme.softGrey),
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).push(_slideRoute());
          },
        ),
      ],
      bottom: TabBar(
        controller: _tabController,
        labelColor: const Color(0xFF00897B),
        unselectedLabelColor: VitalPathTheme.softGrey,
        indicatorColor: const Color(0xFF00897B),
        indicatorWeight: 2.5,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        tabs: _tabs.map((t) => Tab(text: t)).toList(),
      ),
    );
  }

  static Route<void> _slideRoute() {
    return PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => const NotificationSettingsScreen(),
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  void _showNutritionComingSoon(BuildContext context) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Nutrition logging is coming soon — stay tuned!'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: const Color(0xFF3D5AFE),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _openAddSheet(BuildContext context) {
    AddPrescriptionBottomSheet.show(
      context,
      onSaved: (p) =>
          context.read<PrescriptionProvider>().addPrescription(p),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MEDICINES TAB
// ─────────────────────────────────────────────────────────────────────────────
class _MedicinesTab extends StatefulWidget {
  const _MedicinesTab();

  @override
  State<_MedicinesTab> createState() => _MedicinesTabState();
}

class _MedicinesTabState extends State<_MedicinesTab>
    with AutomaticKeepAliveClientMixin {
  // Keep tab alive so scroll position and data are preserved on tab switches.
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    return Consumer<PrescriptionProvider>(
      builder: (context, provider, _) {
        final prescriptions = provider.activePrescriptions;

        if (provider.isLoading && provider.totalCount == 0) {
          return const _TabLoadingShimmer();
        }

        if (prescriptions.isEmpty) {
          return _EmptyActiveMedicinesState(
            hasHistorical: provider.totalCount > 0,
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 12, bottom: 100),
          physics: const BouncingScrollPhysics(),
          itemCount: prescriptions.length,
          itemBuilder: (context, index) {
            final prescription = prescriptions[index];
            return PrescriptionCardWidget(
              key: ValueKey(prescription.id ?? prescription.medicineName),
              prescription: prescription,
              onEdit: (p) => _openEditSheet(context, p),
              onDelete: (id) =>
                  context.read<PrescriptionProvider>().deletePrescription(id),
            );
          },
        );
      },
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

// ─────────────────────────────────────────────────────────────────────────────
// VAULT TAB — prescriptions grouped by doctor, with sticky section headers
// ─────────────────────────────────────────────────────────────────────────────
class _VaultTab extends StatefulWidget {
  const _VaultTab();

  @override
  State<_VaultTab> createState() => _VaultTabState();
}

class _VaultTabState extends State<_VaultTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<PrescriptionProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.totalCount == 0) {
          return const _TabLoadingShimmer();
        }
        if (provider.totalCount == 0) {
          return const _EmptyMedicinesState();
        }
        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            ..._buildGroupedSlivers(context, provider),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        );
      },
    );
  }

  List<Widget> _buildGroupedSlivers(
      BuildContext context, PrescriptionProvider provider) {
    final grouped = provider.groupedPrescriptions;
    final slivers = <Widget>[];
    for (final entry in grouped.entries) {
      slivers.add(SliverPersistentHeader(
        pinned: true,
        delegate: _VaultDoctorHeaderDelegate(
          doctorName: entry.key,
          count: entry.value.length,
        ),
      ));
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final p = entry.value[index];
            return PrescriptionCardWidget(
              key: ValueKey(p.id ?? p.medicineName),
              prescription: p,
              onEdit: (p) => _openEditSheet(context, p),
              onDelete: (id) =>
                  context.read<PrescriptionProvider>().deletePrescription(id),
            );
          },
          childCount: entry.value.length,
        ),
      ));
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));
    }
    return slivers;
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

// Sticky doctor-group section header for the Vault tab.
class _VaultDoctorHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String doctorName;
  final int count;

  static const double _h = 44.0;

  const _VaultDoctorHeaderDelegate({
    required this.doctorName,
    required this.count,
  });

  @override
  double get minExtent => _h;
  @override
  double get maxExtent => _h;

  @override
  bool shouldRebuild(_VaultDoctorHeaderDelegate old) =>
      old.doctorName != doctorName || old.count != count;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      elevation: overlapsContent ? 2 : 0,
      shadowColor: Colors.black12,
      color: VitalPathTheme.lightSurface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
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
                  color: VitalPathTheme.deepCharcoal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF00897B).withValues(alpha: 0.1),
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

// ─────────────────────────────────────────────────────────────────────────────
// NUTRITION TAB
// ─────────────────────────────────────────────────────────────────────────────
class _NutritionTab extends StatefulWidget {
  const _NutritionTab();

  @override
  State<_NutritionTab> createState() => _NutritionTabState();
}

class _NutritionTabState extends State<_NutritionTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return const _NutritionEmptyState();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _LogNutritionFab extends StatelessWidget {
  final VoidCallback onPressed;

  const _LogNutritionFab({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: onPressed,
      backgroundColor: const Color(0xFF3D5AFE),
      extendedPadding: const EdgeInsets.symmetric(horizontal: 20),
      icon: const Icon(Icons.restaurant_menu_rounded, size: 20, color: Colors.white),
      label: const Text(
        'Log Nutrition',
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

class _AddMedicineFab extends StatelessWidget {
  final VoidCallback onPressed;

  const _AddMedicineFab({super.key, required this.onPressed});

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

class _EmptyMedicinesState extends StatelessWidget {
  const _EmptyMedicinesState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFE6F7F4),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.medication_outlined,
                size: 36,
                color: Color(0xFF00897B),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No Medicines Yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: VitalPathTheme.deepCharcoal,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap "+ Add Medicine" to log your first prescription, '
              'or ask your doctor to sync their prescriptions directly.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: VitalPathTheme.softGrey,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyActiveMedicinesState extends StatelessWidget {
  final bool hasHistorical;

  const _EmptyActiveMedicinesState({required this.hasHistorical});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFE6F7F4),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.medication_outlined,
                size: 36,
                color: Color(0xFF00897B),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasHistorical ? 'No Active Medicines' : 'No Medicines Yet',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: VitalPathTheme.deepCharcoal,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasHistorical
                  ? 'All your prescriptions have expired or haven\'t started yet. '
                    'Check the Vault tab to see your full history.'
                  : 'Tap "+ Add Medicine" to log your first prescription, '
                    'or ask your doctor to sync their prescriptions directly.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: VitalPathTheme.softGrey,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NutritionEmptyState extends StatelessWidget {
  const _NutritionEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.restaurant_menu_rounded,
                size: 36,
                color: Color(0xFF3D5AFE),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Nutrition Log',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: VitalPathTheme.deepCharcoal,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Log meals, track macros, and receive doctor-prescribed dietary protocols.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: VitalPathTheme.softGrey,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                        'Nutrition logging is coming soon — stay tuned!'),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    backgroundColor: const Color(0xFF3D5AFE),
                    duration: const Duration(seconds: 3),
                  ),
                );
              },
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add Entry'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3D5AFE),
                foregroundColor: Colors.white,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabLoadingShimmer extends StatelessWidget {
  const _TabLoadingShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 12),
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(
        5,
        (i) => Container(
          margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          height: 90,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

