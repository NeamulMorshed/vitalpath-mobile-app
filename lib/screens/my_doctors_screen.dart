/// my_doctors_screen.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// "My Doctors" screen accessed from the Profile tab.
///
/// Blueprint §1.1: "Patients request appointments through the 'My Doctors'
/// interface in their Profile."
///
/// Features:
///   • Lists all doctors the patient has linked (via QR/6-digit sync).
///   • Each doctor card shows: name, specialty, sync status.
///   • "Request Appointment" CTA per doctor → opens [RequestAppointmentBottomSheet].
///   • Upcoming confirmed appointments shown as a sub-section below each doctor.
///   • 60/120fps: RepaintBoundary per doctor card, ListView.builder (lazy).
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:vitalpath/models/appointment_model.dart';
import 'package:vitalpath/providers/appointment_provider.dart';
import 'package:vitalpath/widgets/appointment_card_widget.dart';
import 'package:vitalpath/widgets/request_appointment_bottom_sheet.dart';

// ── Simple DoctorProfile model (in production this comes from Firestore) ──────
class DoctorProfile {
  final String uid;
  final String name;
  final String specialty;
  final String? avatarUrl;
  final bool isSynced;

  const DoctorProfile({
    required this.uid,
    required this.name,
    required this.specialty,
    this.avatarUrl,
    this.isSynced = true,
  });
}

class MyDoctorsScreen extends StatelessWidget {
  // In production, this list is loaded from Firestore /users/{uid}/linked_doctors.
  // Passed as a constructor param here for testability.
  final List<DoctorProfile> doctors;
  final String patientId;

  const MyDoctorsScreen({
    super.key,
    required this.doctors,
    required this.patientId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
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
          // Sync via QR / 6-digit code — wired in Phase 2.
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded,
                color: Color(0xFF00897B)),
            tooltip: 'Sync with a new doctor',
            onPressed: () => HapticFeedback.lightImpact(),
          ),
        ],
      ),
      body: doctors.isEmpty
          ? const _EmptyDoctorsState()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
              physics: const BouncingScrollPhysics(),
              itemCount: doctors.length,
              itemBuilder: (context, index) {
                final doctor = doctors[index];
                return RepaintBoundary(
                  child: _DoctorCard(
                    doctor: doctor,
                    patientId: patientId,
                  ),
                );
              },
            ),
    );
  }
}

// ── Doctor card ───────────────────────────────────────────────────────────────
class _DoctorCard extends StatelessWidget {
  final DoctorProfile doctor;
  final String patientId;

  const _DoctorCard({required this.doctor, required this.patientId});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppointmentProvider>(
      builder: (context, provider, _) {
        // Upcoming confirmed appointments with this doctor.
        final upcoming = provider.confirmedAppointments
            .where((a) =>
                a.doctorId == doctor.uid &&
                a.displayTime.isAfter(DateTime.now()))
            .take(2)
            .toList();

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey[200]!, width: 1),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x07000000), blurRadius: 8, offset: Offset(0, 3))
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Column(
              children: [
                // ── Doctor header ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Row(
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
                                  fontSize: 13, color: Color(0xFF9E9E9E)),
                            ),
                          ],
                        ),
                      ),

                      // Sync badge
                      if (doctor.isSynced)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6F7F4),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.sync_rounded,
                                  size: 12, color: Color(0xFF00897B)),
                              SizedBox(width: 4),
                              Text(
                                'Synced',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF00897B),
                                ),
                              ),
                            ],
                          ),
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
                          'Upcoming Appointments',
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
                              isOnline: true, // real: inject ConnectivityService
                            );
                      },
                    ),
                    splashColor: const Color(0xFF00897B).withOpacity(0.06),
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

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyDoctorsState extends StatelessWidget {
  const _EmptyDoctorsState();

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
          ],
        ),
      ),
    );
  }
}
