// lib/core/services/coverage_engine.dart
//
// Converts IMU azimuth/elevation into CoverageZone buckets,
// aggregates per-zone hit counts from a list of CapturedImages,
// and derives a coverage percentage and meet-target flag.
//
// Coverage %:
//   Each of the 6 zones contributes 100/6 ≈ 16.67%.
//   A zone's contribution is scaled by min(hits / targetHitsPerZone, 1.0),
//   so partial hits give partial credit. This makes the dial move
//   smoothly rather than jumping in 16.7% steps.

import '../models/capture_models.dart';

// ─── Zone status ──────────────────────────────────────────────────────────────

enum ZoneStatus { empty, adequate, good }

// ─── Engine ───────────────────────────────────────────────────────────────────

class CoverageEngine {
  /// Images per zone to be considered "good" (full contribution).
  static const int _targetHitsPerZone = 8;

  /// Images per zone to be considered "adequate" (visible in UI as yellow).
  static const int _adequateThreshold = 3;

  /// Coverage percentage that constitutes a completed orbit pass.
  static const double coverageTarget = 85.0;

  // ─── IMU → Zone ─────────────────────────────────────────────────────────────

  /// Maps gyroscope-integrated [azimuth] (0–360°, 0 = front of rig) and
  /// gravity-derived [elevation] (degrees, positive = phone pointing up)
  /// to one of the 6 coverage zones.
  ///
  /// Elevation takes priority: ±45° threshold separates top/bottom from sides.
  static CoverageZone? zoneFromImu(double azimuth, double elevation) {
    if (elevation > 45) return CoverageZone.top;
    if (elevation < -45) return CoverageZone.bottom;

    // Normalise to [0, 360)
    final az = ((azimuth % 360) + 360) % 360;

    // 45° guard zones around cardinal directions
    if (az < 45 || az >= 315) return CoverageZone.front;
    if (az < 135) return CoverageZone.right;
    if (az < 225) return CoverageZone.rear;
    return CoverageZone.left;
  }

  // ─── Coverage computation ────────────────────────────────────────────────────

  /// Computes [CoverageState] from all images in a session.
  /// Only orbit-pass images with a non-null zone contribute.
  static CoverageState compute(List<CapturedImage> images) {
    final zoneHits = <CoverageZone, int>{
      for (final z in CoverageZone.values) z: 0,
    };

    for (final img in images) {
      if (img.pass == CapturePass.orbit && img.zone != null) {
        zoneHits[img.zone!] = (zoneHits[img.zone!] ?? 0) + 1;
      }
    }

    // Continuous coverage percentage — each zone contributes proportionally
    double coverageSum = 0;
    for (final hits in zoneHits.values) {
      coverageSum += (hits / _targetHitsPerZone).clamp(0.0, 1.0);
    }
    final coveragePercent =
        (coverageSum / CoverageZone.values.length) * 100.0;

    return CoverageState(
      zoneHits: zoneHits,
      coveragePercent: coveragePercent,
      meetsTarget: coveragePercent >= coverageTarget,
    );
  }

  // ─── UI helpers ──────────────────────────────────────────────────────────────

  static ZoneStatus zoneStatus(int hits) {
    if (hits >= _targetHitsPerZone) return ZoneStatus.good;
    if (hits >= _adequateThreshold) return ZoneStatus.adequate;
    return ZoneStatus.empty;
  }

  static String zoneLabel(CoverageZone zone) {
    switch (zone) {
      case CoverageZone.front:  return 'Front';
      case CoverageZone.rear:   return 'Rear';
      case CoverageZone.left:   return 'Left';
      case CoverageZone.right:  return 'Right';
      case CoverageZone.top:    return 'Top';
      case CoverageZone.bottom: return 'Bottom';
    }
  }
}
