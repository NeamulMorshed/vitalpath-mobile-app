/// gps_walk_session.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Data model for an active or completed GPS-tracked walk session.
///
/// Blueprint §1.1 / §4 — Active GPS Walk:
///   Captures the full route as a list of [RoutePoint]s with timestamps.
///   Each 1km milestone is tracked so haptic feedback can be replayed in the
///   session summary. [kmMilestonesReached] drives the KM badge strip in the UI.
///
/// Storage resilience (Blueprint §1.2):
///   When [GpsWalkService] detects low device storage it sets [isGpsArchived]
///   and replaces the full [routePoints] with [archiveBounds] — a 4-coordinate
///   bounding box that preserves geographic extent without storing the path.
///   Step count, distance, duration, and calories are NEVER archived away.
///
/// Firestore path: users/{userId}/walk_sessions/{sessionId}
/// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

// ── RoutePoint ────────────────────────────────────────────────────────────────
class RoutePoint {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double? altitudeM;
  final double? speedMs;

  const RoutePoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.altitudeM,
    this.speedMs,
  });

  factory RoutePoint.fromJson(Map<String, dynamic> json) => RoutePoint(
        latitude: (json['lat'] as num).toDouble(),
        longitude: (json['lng'] as num).toDouble(),
        timestamp: DateTime.parse(json['ts'] as String),
        altitudeM:
            json['alt'] != null ? (json['alt'] as num).toDouble() : null,
        speedMs:
            json['spd'] != null ? (json['spd'] as num).toDouble() : null,
      );

  Map<String, dynamic> toJson() => {
        'lat': latitude,
        'lng': longitude,
        'ts': timestamp.toIso8601String(),
        if (altitudeM != null) 'alt': altitudeM,
        if (speedMs != null) 'spd': speedMs,
      };
}

// ── BoundingBox ───────────────────────────────────────────────────────────────
// Minimal geographic footprint stored when GPS path is archived.
class BoundingBox {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  const BoundingBox({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  factory BoundingBox.fromPoints(List<RoutePoint> points) {
    assert(points.isNotEmpty, 'Cannot build BoundingBox from empty list');
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points.skip(1)) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    return BoundingBox(
        minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng);
  }

  factory BoundingBox.fromJson(Map<String, dynamic> json) => BoundingBox(
        minLat: (json['min_lat'] as num).toDouble(),
        maxLat: (json['max_lat'] as num).toDouble(),
        minLng: (json['min_lng'] as num).toDouble(),
        maxLng: (json['max_lng'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'min_lat': minLat,
        'max_lat': maxLat,
        'min_lng': minLng,
        'max_lng': maxLng,
      };
}

// ── GpsWalkSession ────────────────────────────────────────────────────────────
class GpsWalkSession {
  final String? id;
  final String patientId;

  // ── Route data ─────────────────────────────────────────────────────────────
  final List<RoutePoint> routePoints;
  final double distanceKm;
  final int durationSeconds;
  final double caloriesBurned;
  final int stepCount;
  final int kmMilestonesReached; // 0, 1, 2, … — drives badge strip in UI

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  final DateTime startedAt;
  final DateTime? endedAt;
  final bool isActive;

  // ── Storage resilience ─────────────────────────────────────────────────────
  /// True after GPS path data was replaced with [archiveBounds] due to low
  /// device storage. Numeric fields are always preserved.
  final bool isGpsArchived;
  final BoundingBox? archiveBounds;

  const GpsWalkSession({
    this.id,
    required this.patientId,
    required this.routePoints,
    required this.distanceKm,
    required this.durationSeconds,
    required this.caloriesBurned,
    required this.stepCount,
    required this.kmMilestonesReached,
    required this.startedAt,
    this.endedAt,
    this.isActive = false,
    this.isGpsArchived = false,
    this.archiveBounds,
  });

  // ── Computed ───────────────────────────────────────────────────────────────
  String get formattedDistance {
    if (distanceKm < 1.0) return '${(distanceKm * 1000).toInt()} m';
    return '${distanceKm.toStringAsFixed(2)} km';
  }

  String get formattedDuration {
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    final s = durationSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  /// Minutes per km. Returns 0 when distance is negligible.
  double get paceMinPerKm =>
      distanceKm > 0.01 ? (durationSeconds / 60.0) / distanceKm : 0;

  String get formattedPace {
    if (paceMinPerKm == 0) return '--:--';
    final m = paceMinPerKm.floor();
    final s = ((paceMinPerKm - m) * 60).round();
    return '$m:${s.toString().padLeft(2, '0')} /km';
  }

  // ── Serialisation ──────────────────────────────────────────────────────────
  factory GpsWalkSession.fromJson(Map<String, dynamic> json) {
    return GpsWalkSession(
      id: json['id'] as String?,
      patientId: json['patient_id'] as String,
      routePoints: json['isGpsArchived'] == true
          ? []
          : (json['route_points'] as List<dynamic>? ?? [])
              .map((e) =>
                  RoutePoint.fromJson(e as Map<String, dynamic>))
              .toList(),
      distanceKm: (json['distance_km'] as num).toDouble(),
      durationSeconds: json['duration_seconds'] as int,
      caloriesBurned: (json['calories_burned'] as num).toDouble(),
      stepCount: json['step_count'] as int? ?? 0,
      kmMilestonesReached: json['km_milestones_reached'] as int? ?? 0,
      startedAt: DateTime.parse(json['started_at'] as String),
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      isActive: json['is_active'] as bool? ?? false,
      isGpsArchived: json['is_gps_archived'] as bool? ?? false,
      archiveBounds: json['archive_bounds'] != null
          ? BoundingBox.fromJson(
              json['archive_bounds'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'patient_id': patientId,
        'route_points':
            routePoints.map((p) => p.toJson()).toList(),
        'distance_km': distanceKm,
        'duration_seconds': durationSeconds,
        'calories_burned': caloriesBurned,
        'step_count': stepCount,
        'km_milestones_reached': kmMilestonesReached,
        'started_at': startedAt.toIso8601String(),
        if (endedAt != null) 'ended_at': endedAt!.toIso8601String(),
        'is_active': isActive,
        'is_gps_archived': isGpsArchived,
        if (archiveBounds != null)
          'archive_bounds': archiveBounds!.toJson(),
      };

  GpsWalkSession copyWith({
    String? id,
    List<RoutePoint>? routePoints,
    double? distanceKm,
    int? durationSeconds,
    double? caloriesBurned,
    int? stepCount,
    int? kmMilestonesReached,
    DateTime? endedAt,
    bool? isActive,
    bool? isGpsArchived,
    BoundingBox? archiveBounds,
  }) {
    return GpsWalkSession(
      id: id ?? this.id,
      patientId: patientId,
      routePoints: routePoints ?? this.routePoints,
      distanceKm: distanceKm ?? this.distanceKm,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      caloriesBurned: caloriesBurned ?? this.caloriesBurned,
      stepCount: stepCount ?? this.stepCount,
      kmMilestonesReached:
          kmMilestonesReached ?? this.kmMilestonesReached,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      isActive: isActive ?? this.isActive,
      isGpsArchived: isGpsArchived ?? this.isGpsArchived,
      archiveBounds: archiveBounds ?? this.archiveBounds,
    );
  }

  @override
  String toString() =>
      'GpsWalkSession(id: $id, distance: ${formattedDistance}, '
      'duration: ${formattedDuration}, km: $kmMilestonesReached, '
      'active: $isActive, archived: $isGpsArchived)';
}
