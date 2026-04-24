import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:vitalpath/models/timeline_entry.dart';
import 'package:vitalpath/providers/dashboard_provider.dart';
import 'package:vitalpath/services/medicine_logging_service.dart';

/// Shows a prominent "Take All" card when 2+ medicine entries are due now.
/// Tapping "Take All" quick-logs every entry in the bundle simultaneously.
/// Placed above the timeline in HomeScreen; disappears once all doses are taken.
class BundleCard extends StatefulWidget {
  const BundleCard({super.key});

  @override
  State<BundleCard> createState() => _BundleCardState();
}

class _BundleCardState extends State<BundleCard>
    with SingleTickerProviderStateMixin {
  bool _isLogging = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _takeAll(
      BuildContext context, List<TimelineEntry> bundle) async {
    if (_isLogging) return;
    setState(() => _isLogging = true);
    HapticFeedback.mediumImpact();

    final provider = context.read<DashboardProvider>();
    int logged = 0;

    for (final entry in bundle) {
      if (!entry.canQuickLog) continue;
      try {
        await provider.quickLog(
          entryId: entry.id,
          medicineId: entry.medicineId!,
        );
        logged++;
      } on DuplicateLogException {
        // Already logged — counts as done in bundle context.
        logged++;
      } catch (_) {
        // Individual failures don't block the rest of the bundle.
      }
    }

    if (mounted) {
      setState(() => _isLogging = false);
      if (logged > 0 && context.mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  logged == bundle.length
                      ? 'All $logged doses logged!'
                      : '$logged of ${bundle.length} doses logged',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF00695C),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        final bundle = provider.todayEntries
            .where((e) =>
                e.type == TimelineEntryType.medicine &&
                e.isDueNow &&
                !e.isCompleted &&
                e.canQuickLog)
            .toList();

        if (bundle.length < 2) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (_, child) {
              final glow = _pulseController.value;
              return Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF00897B), Color(0xFF00695C)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00897B)
                          .withValues(alpha: 0.25 + glow * 0.2),
                      blurRadius: 16 + glow * 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFFF176),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'DUE NOW',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${bundle.length} medicines',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Medicine names
                  ...bundle.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.medication_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                e.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              e.subtitle.split('·').first.trim(),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 14),
                  // Take All button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: _isLogging
                        ? const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: () => _takeAll(context, bundle),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF00695C),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(
                              Icons.check_circle_rounded,
                              size: 20,
                            ),
                            label: Text(
                              'Take All ${bundle.length} Doses',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
