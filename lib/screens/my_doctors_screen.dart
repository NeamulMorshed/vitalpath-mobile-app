/// my_doctors_screen.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// "My Doctors" screen — Profile tab entry point for the doctor-patient sync.
///
/// Blueprint §1.1 / §7:
///   • Searchable list of linked doctors (name, specialty, clinic, sync status).
///   • 'Sync New Doctor' button → [SyncHubBottomSheet] (code or QR).
///   • Connected doctors float to the top with a 'Connected' badge.
///   • Shimmer skeleton while loading from Firebase.
///   • 'Request Appointment' CTA per card → [RequestAppointmentBottomSheet].
///   • 'Unsync' safety protocol: confirmation dialog with governance warning.
///
/// Performance:
///   • [ListView.builder] — lazy, never builds off-screen cards.
///   • [RepaintBoundary] per card — scroll and shimmer never trigger full repaints.
///   • Page transition: [PageRouteBuilder] with [FadeTransition] achieves
///     60/120fps entry by avoiding MaterialPageRoute's heavy scaffold animation.
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:vitalpath/models/doctor_model.dart';
import 'package:vitalpath/providers/appointment_provider.dart';
import 'package:vitalpath/providers/doctor_provider.dart';
import 'package:vitalpath/services/haptic_service.dart';
import 'package:vitalpath/widgets/appointment_card_widget.dart';
import 'package:vitalpath/widgets/doctor_shimmer_widget.dart';
import 'package:vitalpath/widgets/request_appointment_bottom_sheet.dart';
import 'package:vitalpath/widgets/sync_hub_bottom_sheet.dart';

class MyDoctorsScreen extends StatefulWidget {
  final String patientId;

  const MyDoctorsScreen({super.key, required this.patientId});

  /// 60/120fps-friendly route — FadeTransition avoids the default slide overhead.
  static PageRoute<void> route(String patientId) {
    return PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => ChangeNotifierProvider(
        create: (_) => DoctorProvider(),
        child: MyDoctorsScreen(patientId: patientId),
      ),
      transitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    );
  }

  @override
  State<MyDoctorsScreen> createState() => _MyDoctorsScreenState();
}

class _MyDoctorsScreenState extends State<MyDoctorsScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DoctorProvider>().loadDoctors(widget.patientId);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: _buildAppBar(context),
      body: Consumer<DoctorProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const DoctorShimmerList(count: 4);
          }

          final doctors = provider.filtered(_searchQuery);

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Search field ───────────────────────────────────────────────
              SliverToBoxAdapter(child: _buildSearchBar()),

              // ── Connected count strip ──────────────────────────────────────
              if (provider.connectedCount > 0)
                SliverToBoxAdapter(
                  child: _ConnectedStrip(count: provider.connectedCount),
                ),

              // ── Empty state ────────────────────────────────────────────────
              if (doctors.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _searchQuery.isNotEmpty
                      ? _NoResultsState(query: _searchQuery)
                      : _EmptyDoctorsState(
                          patientId: widget.patientId,
                          provider: provider,
                        ),
                ),

              // ── Doctor cards ───────────────────────────────────────────────
              if (doctors.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final doctor = doctors[index];
                        return RepaintBoundary(
                          child: _DoctorCard(
                            doctor: doctor,
                            patientId: widget.patientId,
                            onUnsync: () => _confirmUnsync(context, doctor),
                          ),
                        );
                      },
                      childCount: doctors.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            size: 20, color: Color(0xFF1A1A2E)),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: const Text(
        'My Doctors',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1A1A2E),
        ),
      ),
      actions: [
        Consumer<DoctorProvider>(
          builder: (_, provider, __) => TextButton.icon(
            onPressed: provider.isSyncing
                ? null
                : () => SyncHubBottomSheet.show(
                      context,
                      doctorProvider: provider,
                      patientId: widget.patientId,
                      onSyncSuccess: (_) => HapticService().goalSuccess(),
                    ),
            icon: const Icon(Icons.add_rounded,
                size: 18, color: Color(0xFF00897B)),
            label: const Text(
              'Sync',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF00897B),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: TextField(
        controller: _searchCtrl,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search by name, specialty or clinic…',
          hintStyle:
              const TextStyle(fontSize: 14, color: Color(0xFFBDBDBD)),
          prefixIcon: const Icon(Icons.search_rounded,
              color: Color(0xFF9E9E9E), size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Color(0xFF9E9E9E), size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    HapticFeedback.selectionClick();
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE8E8EE)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE8E8EE)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: Color(0xFF00897B), width: 1.5),
          ),
        ),
      ),
    );
  }

  // ── Unsync confirmation dialog ─────────────────────────────────────────────
  Future<void> _confirmUnsync(BuildContext context, DoctorModel doctor) async {
    HapticFeedback.heavyImpact();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.link_off_rounded,
                  color: Color(0xFFE53935), size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Unsync Doctor?',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E)),
              ),
            ),
          ],
        ),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(
                fontSize: 14, color: Color(0xFF555566), height: 1.6),
            children: [
              const TextSpan(
                text:
                    'Unsyncing will stop automatic updates for verified prescriptions. ',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(
                text: 'Are you sure you want to remove Dr. ${doctor.name}?',
              ),
            ],
          ),
        ),
        actionsPadding:
            const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(ctx).pop(false);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1A1A2E),
              side: const BorderSide(color: Color(0xFFE0E0E0)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12),
            ),
            child: const Text('Keep Connection',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            onPressed: () {
              HapticFeedback.heavyImpact();
              Navigator.of(ctx).pop(true);
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12),
            ),
            child: const Text('Unsync',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<DoctorProvider>().unsyncDoctor(
            patientId: widget.patientId,
            doctorId: doctor.uid,
          );
    }
  }
}

// ── Connected doctors strip ───────────────────────────────────────────────────
class _ConnectedStrip extends StatelessWidget {
  final int count;
  const _ConnectedStrip({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded,
              size: 14, color: Color(0xFF00897B)),
          const SizedBox(width: 6),
          Text(
            '$count doctor${count == 1 ? '' : 's'} connected',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF00897B),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Doctor card ───────────────────────────────────────────────────────────────
class _DoctorCard extends StatelessWidget {
  final DoctorModel doctor;
  final String patientId;
  final VoidCallback onUnsync;

  const _DoctorCard({
    required this.doctor,
    required this.patientId,
    required this.onUnsync,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AppointmentProvider>(
      builder: (context, apptProvider, _) {
        final upcoming = apptProvider.confirmedAppointments
            .where((a) =>
                a.doctorId == doctor.uid &&
                a.displayTime.isAfter(DateTime.now()))
            .take(2)
            .toList();

        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: doctor.isConnected
                  ? const Color(0xFF00897B).withOpacity(0.18)
                  : Colors.grey[200]!,
              width: doctor.isConnected ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: doctor.isConnected
                    ? const Color(0xFF00897B).withOpacity(0.06)
                    : const Color(0x07000000),
                blurRadius: doctor.isConnected ? 12 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Column(
              children: [
                // ── Doctor info header ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: const Color(0xFFE6F7F4),
                        backgroundImage: doctor.avatarUrl != null
                            ? NetworkImage(doctor.avatarUrl!)
                            : null,
                        child: doctor.avatarUrl == null
                            ? Text(
                                doctor.name[0].toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF00897B),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 14),

                      // Name / specialty / clinic
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Dr. ${doctor.name}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              doctor.specialty,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF9E9E9E)),
                            ),
                            if (doctor.clinicName.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  const Icon(Icons.business_rounded,
                                      size: 11,
                                      color: Color(0xFFBDBDBD)),
                                  const SizedBox(width: 4),
                                  Text(
                                    doctor.clinicName,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFFBDBDBD)),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Sync status badge + unsync
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _SyncBadge(status: doctor.syncStatus),
                          if (doctor.isConnected) ...[
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: onUnsync,
                              child: const Text(
                                'Unsync',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFE53935),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Upcoming appointments ───────────────────────────────────
                if (upcoming.isNotEmpty) ...[
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.event_rounded,
                            size: 13, color: Color(0xFF9E9E9E)),
                        const SizedBox(width: 6),
                        Text(
                          'Upcoming',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...upcoming.map((a) => AppointmentCardWidget(
                        appointment: a,
                        compact: true,
                      )),
                ],

                // ── Request Appointment CTA ─────────────────────────────────
                const Divider(height: 1),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => RequestAppointmentBottomSheet.show(
                      context,
                      doctor: doctor,
                      patientId: patientId,
                      onSubmit: (appointment) {
                        context.read<AppointmentProvider>().requestAppointment(
                              appointment: appointment,
                              isOnline: true,
                            );
                      },
                    ),
                    splashColor:
                        const Color(0xFF00897B).withOpacity(0.06),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.calendar_month_rounded,
                              size: 18, color: Color(0xFF00897B)),
                          SizedBox(width: 8),
                          Text(
                            'Request Appointment',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF00897B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Sync status badge ─────────────────────────────────────────────────────────
class _SyncBadge extends StatelessWidget {
  final DoctorSyncStatus status;
  const _SyncBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: status.backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 11, color: status.color),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: status.color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyDoctorsState extends StatelessWidget {
  final String patientId;
  final DoctorProvider provider;
  const _EmptyDoctorsState(
      {required this.patientId, required this.provider});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
              child: const Icon(Icons.person_search_rounded,
                  size: 36, color: Color(0xFF00897B)),
            ),
            const SizedBox(height: 18),
            const Text(
              'No Doctors Linked',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ask your doctor for their 6-digit sync code or QR code to connect.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: Color(0xFF9E9E9E), height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => SyncHubBottomSheet.show(
                context,
                doctorProvider: provider,
                patientId: patientId,
                onSyncSuccess: (_) => HapticService().goalSuccess(),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Sync a Doctor',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── No search results ─────────────────────────────────────────────────────────
class _NoResultsState extends StatelessWidget {
  final String query;
  const _NoResultsState({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded,
                size: 40, color: Color(0xFFBDBDBD)),
            const SizedBox(height: 14),
            Text(
              'No results for "$query"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try searching by specialty or clinic name.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
            ),
          ],
        ),
      ),
    );
  }
}
