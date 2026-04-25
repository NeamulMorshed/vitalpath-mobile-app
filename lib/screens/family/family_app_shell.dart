import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:vitalpath/models/prescription_model.dart';
import 'package:vitalpath/models/user_profile_model.dart';
import 'package:vitalpath/providers/prescription_provider.dart';
import 'package:vitalpath/services/user_profile_service.dart';
import 'package:vitalpath/theme/vitalpath_theme.dart';

class FamilyAppShell extends StatefulWidget {
  final VoidCallback? onSwitchAccount;
  const FamilyAppShell({super.key, this.onSwitchAccount});

  @override
  State<FamilyAppShell> createState() => _FamilyAppShellState();
}

class _FamilyAppShellState extends State<FamilyAppShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VitalPathTheme.lightSurface,
      body: IndexedStack(
        index: _tab,
        children: [
          const _OverviewTab(),
          const _CareTab(),
          _FamilyProfileTab(onSwitchAccount: widget.onSwitchAccount),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          HapticFeedback.selectionClick();
          setState(() => _tab = i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart_rounded),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.medical_services_outlined),
            selectedIcon: Icon(Icons.medical_services_rounded),
            label: 'Care',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ── Overview Tab ──────────────────────────────────────────────────────────────
class _OverviewTab extends StatelessWidget {
  const _OverviewTab();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfileModel?>(
      future: UserProfileService().getProfile(),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final patientName =
            (profile?.linkedPatientName?.isNotEmpty == true)
                ? profile!.linkedPatientName!
                : 'Your Patient';
        final relationship = profile?.relationship ?? 'Family Member';

        return CustomScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 110,
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Health Overview',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: VitalPathTheme.deepCharcoal,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              Text(
                                'Monitoring $patientName · $relationship',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: VitalPathTheme.softGrey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_outline_rounded,
                                  size: 12, color: Color(0xFFFF6B35)),
                              SizedBox(width: 4),
                              Text('Read Only',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFFF6B35))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PatientSummaryCard(
                      patientName: patientName,
                      relationship: relationship,
                    ),
                    const SizedBox(height: 16),
                    _MedsTodayCard(),
                    const SizedBox(height: 16),
                    _EmergencyCard(profile: profile),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: const Color(0xFFFF6B35)
                                .withValues(alpha: 0.25)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 16, color: Color(0xFFFF6B35)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'You have read-only access. Medication changes and '
                              'appointments must be made by the patient or their doctor.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFBF360C),
                                  height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PatientSummaryCard extends StatelessWidget {
  final String patientName;
  final String relationship;
  const _PatientSummaryCard(
      {required this.patientName, required this.relationship});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B35), Color(0xFFFF8C42)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFFFF6B35).withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.person_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(patientName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    )),
                Text('$relationship · Linked Patient',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12.5,
                    )),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 7, color: Color(0xFF69F0AE)),
                SizedBox(width: 5),
                Text('Active',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MedsTodayCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final count =
        context.watch<PrescriptionProvider>().allPrescriptions.length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: VitalPathTheme.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE6F7F4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.medication_rounded,
                size: 22, color: Color(0xFF00897B)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Medications',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: VitalPathTheme.deepCharcoal,
                    )),
                Text(
                  count == 0
                      ? 'No medications on record'
                      : '$count medication${count == 1 ? '' : 's'} on record',
                  style: const TextStyle(
                      fontSize: 12.5, color: VitalPathTheme.softGrey),
                ),
              ],
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Color(0xFF00897B),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmergencyCard extends StatelessWidget {
  final UserProfileModel? profile;
  const _EmergencyCard({this.profile});

  @override
  Widget build(BuildContext context) {
    final contactName = profile?.emergencyContactName;
    final contactPhone = profile?.emergencyContactPhone;
    final hasContact =
        contactName != null && contactName.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFFE53935).withValues(alpha: 0.2)),
        boxShadow: VitalPathTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.emergency_rounded,
                  color: Color(0xFFE53935), size: 18),
              SizedBox(width: 8),
              Text('Emergency Contact',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: VitalPathTheme.deepCharcoal,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          if (hasContact) ...[
            Text(contactName!,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: VitalPathTheme.deepCharcoal,
                )),
            if (contactPhone != null && contactPhone.isNotEmpty)
              Text(contactPhone,
                  style: const TextStyle(
                      fontSize: 13, color: VitalPathTheme.softGrey)),
          ] else
            const Text('No emergency contact on file.',
                style: TextStyle(
                    fontSize: 13, color: VitalPathTheme.softGrey)),
        ],
      ),
    );
  }
}

// ── Care Tab ──────────────────────────────────────────────────────────────────
class _CareTab extends StatelessWidget {
  const _CareTab();

  @override
  Widget build(BuildContext context) {
    final prescriptions =
        context.watch<PrescriptionProvider>().allPrescriptions;

    return Scaffold(
      backgroundColor: VitalPathTheme.lightSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text('Care',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: VitalPathTheme.deepCharcoal,
            )),
        automaticallyImplyLeading: false,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded,
                    size: 12, color: Color(0xFFFF6B35)),
                SizedBox(width: 4),
                Text('Read Only',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFF6B35))),
              ],
            ),
          ),
        ],
      ),
      body: prescriptions.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.medical_services_outlined,
                        size: 52, color: VitalPathTheme.softGrey),
                    SizedBox(height: 14),
                    Text('No medications on record',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: VitalPathTheme.deepCharcoal,
                        )),
                    SizedBox(height: 6),
                    Text(
                      'When the patient adds medications, they will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, color: VitalPathTheme.softGrey),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: prescriptions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final p = prescriptions[i];
                final dosageStr = p.dosage == p.dosage.roundToDouble()
                    ? p.dosage.toInt().toString()
                    : p.dosage.toString();
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: VitalPathTheme.cardShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6F7F4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.medication_rounded,
                            size: 22, color: Color(0xFF00897B)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.medicineName,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: VitalPathTheme.deepCharcoal,
                                )),
                            Text('$dosageStr ${p.unit.label}',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    color: VitalPathTheme.softGrey)),
                          ],
                        ),
                      ),
                      if (p.isVerified)
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified_rounded,
                                size: 14, color: Color(0xFF00897B)),
                            SizedBox(width: 4),
                            Text('Verified',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF00897B),
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ── Family Profile Tab ────────────────────────────────────────────────────────
class _FamilyProfileTab extends StatelessWidget {
  final VoidCallback? onSwitchAccount;
  const _FamilyProfileTab({this.onSwitchAccount});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfileModel?>(
      future: UserProfileService().getProfile(),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final name =
            (profile?.displayName.isNotEmpty == true)
                ? profile!.displayName
                : 'Family Member';
        final relationship =
            profile?.relationship ?? 'Family Member';
        final linkedPatient = profile?.linkedPatientName ?? '';

        return Scaffold(
          backgroundColor: VitalPathTheme.lightSurface,
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 100,
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.pin,
                  background: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Profile',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: VitalPathTheme.deepCharcoal,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            '$relationship · VitalPath',
                            style: const TextStyle(
                              fontSize: 13,
                              color: VitalPathTheme.softGrey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF6B35), Color(0xFFFF8C42)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                                color: const Color(0xFFFF6B35)
                                    .withValues(alpha: 0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 6)),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.people_rounded,
                                  color: Colors.white, size: 28),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      )),
                                  Text(
                                    linkedPatient.isNotEmpty
                                        ? '$relationship of $linkedPatient'
                                        : relationship,
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.75),
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (linkedPatient.isNotEmpty) ...[
                        _FamilySectionHeader('Linked Patient'),
                        _InfoTile(
                            icon: Icons.person_search_outlined,
                            label: 'Patient Name',
                            value: linkedPatient),
                        const SizedBox(height: 16),
                      ],
                      _FamilySectionHeader('Your Account'),
                      _InfoTile(
                          icon: Icons.badge_outlined,
                          label: 'Display Name',
                          value: name),
                      _InfoTile(
                          icon: Icons.people_alt_outlined,
                          label: 'Relationship',
                          value: relationship),
                      const SizedBox(height: 16),
                      _FamilySectionHeader('Account'),
                      _ActionTile(
                        icon: Icons.switch_account_rounded,
                        label: 'Switch Account',
                        subtitle: 'Sign out and start fresh',
                        iconColor: const Color(0xFFE65100),
                        onTap: onSwitchAccount,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FamilySectionHeader extends StatelessWidget {
  final String title;
  const _FamilySectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title.toUpperCase(),
        style: VitalPathTheme.labelLarge.copyWith(
          color: VitalPathTheme.softGrey,
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: VitalPathTheme.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2F1),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                Icon(icon, size: 18, color: const Color(0xFF00897B)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: VitalPathTheme.softGrey,
                        fontWeight: FontWeight.w500)),
                Text(value,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: VitalPathTheme.deepCharcoal,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color? iconColor;
  final VoidCallback? onTap;
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: VitalPathTheme.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor != null
                        ? iconColor!.withValues(alpha: 0.1)
                        : const Color(0xFFE0F2F1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon,
                      size: 20,
                      color: iconColor ?? const Color(0xFF00897B)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: VitalPathTheme.deepCharcoal,
                          )),
                      Text(subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: VitalPathTheme.softGrey,
                          )),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: Color(0xFFBDBDBD), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
