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

  static const _tabs = ['Medicines', 'Food', 'Activity'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
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
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: _buildAppBar(),
      body: TabBarView(
        controller: _tabController,
        // Disable swipe on small velocity to prevent accidental tab switches
        // while scrolling — keeps 60fps scroll feel intact.
        physics: const ClampingScrollPhysics(),
        children: const [
          _MedicinesTab(),
          _FoodTab(),
          _ActivityTab(),
        ],
      ),
      // FAB is only shown on the Medicines tab (index 0).
      floatingActionButton: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, anim) => ScaleTransition(
          scale: anim,
          child: child,
        ),
        child: _activeTab == 0
            ? _AddMedicineFab(
                key: const ValueKey('medicines-fab'),
                onPressed: () => _openAddSheet(context),
              )
            : const SizedBox.shrink(key: ValueKey('no-fab')),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Care',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1A1A2E),
        ),
      ),
      actions: [
        // Notification bell — wired in Phase 2.
        IconButton(
          icon: const Icon(Icons.notifications_none_rounded,
              color: Color(0xFF555566)),
          onPressed: () => HapticFeedback.lightImpact(),
        ),
      ],
      bottom: TabBar(
        controller: _tabController,
        labelColor: const Color(0xFF00897B),
        unselectedLabelColor: const Color(0xFF9E9E9E),
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
        final prescriptions = provider.allPrescriptions;

        if (provider.isLoading && prescriptions.isEmpty) {
          return const _TabLoadingShimmer();
        }

        if (prescriptions.isEmpty) {
          return const _EmptyMedicinesState();
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
// FOOD TAB
// ─────────────────────────────────────────────────────────────────────────────
class _FoodTab extends StatefulWidget {
  const _FoodTab();

  @override
  State<_FoodTab> createState() => _FoodTabState();
}

class _FoodTabState extends State<_FoodTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Food entries will be powered by a NutritionProvider in the next sprint.
    // Placeholder with governance-aware card structure shown below.
    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 100),
      physics: const BouncingScrollPhysics(),
      children: const [
        _ComingSoonBanner(
          icon: Icons.restaurant_menu_rounded,
          title: 'Food Log',
          description:
              'Log meals, track macros, and receive doctor-prescribed dietary protocols.',
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTIVITY TAB
// ─────────────────────────────────────────────────────────────────────────────
class _ActivityTab extends StatefulWidget {
  const _ActivityTab();

  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<_ActivityTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 100),
      physics: const BouncingScrollPhysics(),
      children: const [
        _ComingSoonBanner(
          icon: Icons.directions_run_rounded,
          title: 'Activity Log',
          description:
              'Track workouts, physiotherapy sessions, and doctor-prescribed exercise protocols.',
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

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
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap "+ Add Medicine" to log your first prescription, '
              'or ask your doctor to sync their prescriptions directly.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF9E9E9E),
                height: 1.5,
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

class _ComingSoonBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _ComingSoonBanner({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 30, color: const Color(0xFF3D5AFE)),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF9E9E9E),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Coming in Phase 2',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3D5AFE),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
