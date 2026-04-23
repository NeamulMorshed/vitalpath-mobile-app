/// walk_screen.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Active GPS Walk — full-screen map with live route and stats HUD.
///
/// Blueprint §1.1 / §4:
///   "Build a 'Start Walk' interface that utilises Google Maps / Apple Maps.
///    Trigger a distinct vibration every 1 KM reached."
///
/// Layout:
///   ┌──────────────────────────────────────────────┐
///   │  Google Map (full-screen, GL context)         │  ← live polyline
///   │  ┌───────────────────┐                        │
///   │  │ ← back   ●LIVE    │  ← floating app bar   │
///   │  └───────────────────┘                        │
///   │                                               │
///   │          [KM milestone badges]                │
///   │                                               │
///   ├──────────────────────────────────────────────┤
///   │  DraggableScrollableSheet (stats HUD)         │
///   │   Distance │ Duration │ Pace │ Calories        │
///   │   ─────────────────────────────────────────   │
///   │   [Stop Walk]                                  │
///   └──────────────────────────────────────────────┘
///
/// Dependencies (pubspec.yaml):
///   google_maps_flutter: ^2.9.0
///
/// 120fps strategy:
///   • Google Maps GL surface renders at device refresh rate independently.
///   • The stats HUD is wrapped in [RepaintBoundary] — map redraws never
///     trigger HUD repaints and vice-versa.
///   • Polyline list is updated via [setState] only when a new point is
///     received (bounded by the GPS distanceFilter — max once every ~5 m).
///   • The duration counter is driven by [GpsWalkService]'s 1-second ticker,
///     not a separate UI timer, so there is exactly one tick source.
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:vitalpath/models/gps_walk_session.dart';
import 'package:vitalpath/providers/activity_provider.dart';
import 'package:vitalpath/services/haptic_service.dart';

class WalkScreen extends StatefulWidget {
  const WalkScreen({super.key});

  /// Slides up from the bottom — natural gesture for a modal-style walk UI.
  static PageRoute<GpsWalkSession?> route() {
    return PageRouteBuilder<GpsWalkSession?>(
      pageBuilder: (_, __, ___) => const WalkScreen(),
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      transitionsBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(
            parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
  }

  @override
  State<WalkScreen> createState() => _WalkScreenState();
}

class _WalkScreenState extends State<WalkScreen> {
  // GoogleMapController — used to animate camera to new position.
  // Real type: GoogleMapController (from google_maps_flutter)
  dynamic _mapController;

  // Route polyline points.
  // Real type: Set<Polyline> from google_maps_flutter.
  // Here we track raw RoutePoints and convert when building map args.
  final List<RoutePoint> _displayPoints = [];
  int _previousPointCount = 0;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: Consumer<ActivityProvider>(
          builder: (context, provider, _) {
            final session = provider.activeSession;
            _syncDisplayPoints(session);

            return Stack(
              children: [
                // ── Map layer (full-screen) ──────────────────────────────────
                Positioned.fill(
                  child: _buildMap(session),
                ),

                // ── Floating top bar ─────────────────────────────────────────
                _buildTopBar(context, session),

                // ── KM milestone badge strip ─────────────────────────────────
                if ((session?.kmMilestonesReached ?? 0) > 0)
                  _buildMilestoneBadges(
                      session!.kmMilestonesReached),

                // ── Stats HUD (DraggableScrollableSheet) ────────────────────
                RepaintBoundary(
                  child: _StatsHud(
                    session: session,
                    onStop: () => _stopWalk(context, provider),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Map ────────────────────────────────────────────────────────────────────
  Widget _buildMap(GpsWalkSession? session) {
    // ── Real GoogleMap implementation ────────────────────────────────────────
    //
    // import 'package:google_maps_flutter/google_maps_flutter.dart';
    //
    // final latLngs = session?.routePoints
    //     .map((p) => LatLng(p.latitude, p.longitude))
    //     .toList() ?? [];
    //
    // final startPos = latLngs.isNotEmpty
    //     ? latLngs.first
    //     : const LatLng(51.5074, -0.1278); // fallback: London
    //
    // return GoogleMap(
    //   initialCameraPosition: CameraPosition(
    //     target: startPos,
    //     zoom: 16,
    //   ),
    //   onMapCreated: (ctrl) => _mapController = ctrl,
    //   myLocationEnabled: true,
    //   myLocationButtonEnabled: false,
    //   zoomControlsEnabled: false,
    //   mapToolbarEnabled: false,
    //   mapType: MapType.normal,
    //   polylines: latLngs.length > 1
    //       ? {
    //           Polyline(
    //             polylineId: const PolylineId('walk_route'),
    //             points: latLngs,
    //             color: const Color(0xFF00897B),
    //             width: 5,
    //             startCap: Cap.roundCap,
    //             endCap: Cap.roundCap,
    //             jointType: JointType.round,
    //           ),
    //         }
    //       : {},
    //   markers: latLngs.isNotEmpty
    //       ? {
    //           Marker(
    //             markerId: const MarkerId('start'),
    //             position: latLngs.first,
    //             icon: BitmapDescriptor.defaultMarkerWithHue(
    //                 BitmapDescriptor.hueGreen),
    //           ),
    //         }
    //       : {},
    // );
    // ── Placeholder (add google_maps_flutter to pubspec.yaml) ────────────────
    return Container(
      color: const Color(0xFF1A2744),
      child: CustomPaint(
        painter: _MapPlaceholderPainter(
          points: _displayPoints,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.map_rounded, color: Colors.white24, size: 52),
              const SizedBox(height: 12),
              const Text(
                'Map renders here.\nAdd google_maps_flutter to pubspec.yaml.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white24,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              if (_displayPoints.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${_displayPoints.length} GPS points recorded',
                  style: const TextStyle(
                    color: Color(0xFF00897B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _syncDisplayPoints(GpsWalkSession? session) {
    if (session == null) return;
    if (session.routePoints.length != _previousPointCount) {
      _displayPoints
        ..clear()
        ..addAll(session.routePoints);
      _previousPointCount = session.routePoints.length;

      // Animate camera to latest position.
      // Real: _mapController?.animateCamera(CameraUpdate.newLatLng(
      //   LatLng(session.routePoints.last.latitude,
      //          session.routePoints.last.longitude)));
    }
  }

  // ── Floating top bar ───────────────────────────────────────────────────────
  Widget _buildTopBar(BuildContext context, GpsWalkSession? session) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            // Back button
            GestureDetector(
              onTap: () => _confirmStop(context,
                  context.read<ActivityProvider>()),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
            const Spacer(),
            // Live indicator
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00897B),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── KM milestone badges ────────────────────────────────────────────────────
  Widget _buildMilestoneBadges(int count) {
    return Positioned(
      top: 0,
      bottom: 260,
      right: 16,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(count, (i) {
            final km = i + 1;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00897B),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00897B).withOpacity(0.5),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  '${km}km',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            );
          }).reversed.toList(),
        ),
      ),
    );
  }

  // ── Stop walk ──────────────────────────────────────────────────────────────
  Future<void> _confirmStop(
      BuildContext context, ActivityProvider provider) async {
    if (!provider.isWalking) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    HapticFeedback.heavyImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Stop Walk?',
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E)),
        ),
        content: const Text(
          'This will end your current GPS session and save your route.',
          style: TextStyle(fontSize: 14, color: Color(0xFF555566), height: 1.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFE0E0E0)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 12),
            ),
            child: const Text('Keep Going',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E))),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 12),
            ),
            child: const Text('Stop',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _stopWalk(context, provider);
    }
  }

  Future<void> _stopWalk(
      BuildContext context, ActivityProvider provider) async {
    HapticService().appointmentConfirmed();
    final session = await provider.stopWalk();
    if (mounted) Navigator.of(context).pop(session);
  }
}

// ── Stats HUD ─────────────────────────────────────────────────────────────────
class _StatsHud extends StatelessWidget {
  final GpsWalkSession? session;
  final VoidCallback onStop;

  const _StatsHud({required this.session, required this.onStop});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.26,
      minChildSize: 0.20,
      maxChildSize: 0.50,
      snap: true,
      snapSizes: const [0.26, 0.50],
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
                color: Color(0x22000000),
                blurRadius: 20,
                offset: Offset(0, -4)),
          ],
        ),
        child: ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),

            // ── Stats grid ─────────────────────────────────────────────────
            Row(
              children: [
                _StatTile(
                  label: 'Distance',
                  value: session?.formattedDistance ?? '0 m',
                  icon: Icons.straighten_rounded,
                ),
                _StatTile(
                  label: 'Duration',
                  value: session?.formattedDuration ?? '0s',
                  icon: Icons.timer_rounded,
                ),
                _StatTile(
                  label: 'Pace',
                  value: session?.formattedPace ?? '--:--',
                  icon: Icons.speed_rounded,
                ),
                _StatTile(
                  label: 'kcal',
                  value: session != null
                      ? session!.caloriesBurned.toInt().toString()
                      : '0',
                  icon: Icons.local_fire_department_rounded,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Stop button ────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.stop_circle_rounded, size: 22),
                label: const Text(
                  'Stop Walk',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Single stat tile ──────────────────────────────────────────────────────────
class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF9E9E9E)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
                fontSize: 11, color: Color(0xFF9E9E9E)),
          ),
        ],
      ),
    );
  }
}

// ── Map placeholder painter ───────────────────────────────────────────────────
// Draws a simple polyline from recorded RoutePoints when google_maps_flutter
// is not yet integrated. Gives visual feedback that GPS is working.
class _MapPlaceholderPainter extends CustomPainter {
  final List<RoutePoint> points;
  const _MapPlaceholderPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    // Normalise lat/lng to canvas coordinates.
    final lats = points.map((p) => p.latitude);
    final lngs = points.map((p) => p.longitude);
    final minLat = lats.reduce((a, b) => a < b ? a : b);
    final maxLat = lats.reduce((a, b) => a > b ? a : b);
    final minLng = lngs.reduce((a, b) => a < b ? a : b);
    final maxLng = lngs.reduce((a, b) => a > b ? a : b);
    final latRange = maxLat - minLat;
    final lngRange = maxLng - minLng;

    if (latRange == 0 || lngRange == 0) return;

    final paint = Paint()
      ..color = const Color(0xFF00897B)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = (points[i].longitude - minLng) / lngRange * size.width * 0.8 +
          size.width * 0.1;
      final y = (1 - (points[i].latitude - minLat) / latRange) *
              size.height *
              0.6 +
          size.height * 0.1;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);

    // Start dot.
    final firstX =
        (points.first.longitude - minLng) / lngRange * size.width * 0.8 +
            size.width * 0.1;
    final firstY =
        (1 - (points.first.latitude - minLat) / latRange) * size.height * 0.6 +
            size.height * 0.1;
    canvas.drawCircle(
      Offset(firstX, firstY),
      6,
      Paint()..color = const Color(0xFF00897B),
    );
  }

  @override
  bool shouldRepaint(_MapPlaceholderPainter old) =>
      old.points.length != points.length;
}
