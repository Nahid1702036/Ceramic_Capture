// lib/core/models/capture_models.dart

import 'package:json_annotation/json_annotation.dart';

part 'capture_models.g.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum CapturePass {
  calibration,
  orbit,
  macro,
  base,
  scale,
}

enum YoloClass {
  ceramicObject,
  makerMark,
  signature,
  stamp,
  footRing,
  scaleMarker,
}

enum CoverageZone {
  front,
  rear,
  left,
  right,
  top,
  bottom,
}

enum QualityFlag {
  ok,
  blurMotion,
  blur,
  overexposure,
  underexposure,
  duplicate,
}

enum InferenceMode { tflite, fastapi }

// ─── Detection Result ─────────────────────────────────────────────────────────

@JsonSerializable()
class Detection {
  final YoloClass cls;
  final double confidence;
  final double x, y, w, h; // normalised bbox

  const Detection({
    required this.cls,
    required this.confidence,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  factory Detection.fromJson(Map<String, dynamic> json) =>
      _$DetectionFromJson(json);
  Map<String, dynamic> toJson() => _$DetectionToJson(this);
}

// ─── Frame Analysis ───────────────────────────────────────────────────────────

@JsonSerializable()
class FrameAnalysis {
  final List<Detection> detections;
  final List<QualityFlag> qualityFlags;
  final CoverageZone? coveredZone;
  final bool scaleMarkerVisible;
  final bool objectInFrame;
  final double sharpnessScore;   // Laplacian variance, higher = sharper
  final double exposureScore;    // 0–1, 0.5 = ideal

  const FrameAnalysis({
    required this.detections,
    required this.qualityFlags,
    required this.coveredZone,
    required this.scaleMarkerVisible,
    required this.objectInFrame,
    required this.sharpnessScore,
    required this.exposureScore,
  });

  bool get isAcceptable =>
      qualityFlags.isEmpty || qualityFlags == [QualityFlag.ok];

  factory FrameAnalysis.fromJson(Map<String, dynamic> json) =>
      _$FrameAnalysisFromJson(json);
  Map<String, dynamic> toJson() => _$FrameAnalysisToJson(this);
}

// ─── Per-frame Kalman physics state (from server) ────────────────────────────
//
// Returned by POST /predict/{session_id} when FAPE is active on the server.
// Stored per-image so FAPE reconstruction gets the correct calibrated priors.
//
//   rhoFil     — KalmanThermalEstimator thermal noise floor (camera heat)
//   kMu        — SpecKCalibrator contrast mean (glaze shininess proxy)
//   sigma2K    — SpecKCalibrator posterior uncertainty
//   trs        — temporal residual score (motion proxy; 0 = still)
//   frameValid — passed FrameQualityGate (false = fallback values used)

@JsonSerializable()
class PhysicsState {
  final double rhoFil;
  final double kMu;
  final double sigma2K;
  final double trs;
  final bool frameValid;

  const PhysicsState({
    required this.rhoFil,
    required this.kMu,
    required this.sigma2K,
    required this.trs,
    required this.frameValid,
  });

  /// Neutral priors — used when server runs YOLO-only (no FAPE).
  static const PhysicsState neutral = PhysicsState(
    rhoFil: 0.02,
    kMu: 0.05,
    sigma2K: 0.1,
    trs: 0.0,
    frameValid: true,
  );

  factory PhysicsState.fromJson(Map<String, dynamic> json) =>
      _$PhysicsStateFromJson(json);
  Map<String, dynamic> toJson() => _$PhysicsStateToJson(this);
}

// ─── Captured Image Record ────────────────────────────────────────────────────

@JsonSerializable()
class CapturedImage {
  final String id;
  final String filePath;
  final String colmapPath;     // relative path inside colmap/images/
  final CapturePass pass;
  final DateTime capturedAt;
  final FrameAnalysis analysis;
  final double? imuAzimuth;    // degrees, orbit pass only
  final double? imuElevation;  // degrees
  final CoverageZone? zone;
  /// Kalman physics scalars from the server for this frame.
  /// Null when using TFLite-only mode (no server).
  final PhysicsState? physics;

  const CapturedImage({
    required this.id,
    required this.filePath,
    required this.colmapPath,
    required this.pass,
    required this.capturedAt,
    required this.analysis,
    this.imuAzimuth,
    this.imuElevation,
    this.zone,
    this.physics,
  });

  factory CapturedImage.fromJson(Map<String, dynamic> json) =>
      _$CapturedImageFromJson(json);
  Map<String, dynamic> toJson() => _$CapturedImageToJson(this);
}

// ─── Coverage State ───────────────────────────────────────────────────────────

@JsonSerializable()
class CoverageState {
  final Map<CoverageZone, int> zoneHits;   // zone → image count
  final double coveragePercent;            // 0–100
  final bool meetsTarget;                  // ≥ 85%

  const CoverageState({
    required this.zoneHits,
    required this.coveragePercent,
    required this.meetsTarget,
  });

  static CoverageState empty() => CoverageState(
        zoneHits: {for (final z in CoverageZone.values) z: 0},
        coveragePercent: 0,
        meetsTarget: false,
      );

  factory CoverageState.fromJson(Map<String, dynamic> json) =>
      _$CoverageStateFromJson(json);
  Map<String, dynamic> toJson() => _$CoverageStateToJson(this);
}

// ─── Project Session ──────────────────────────────────────────────────────────

@JsonSerializable()
class CaptureSession {
  final String projectId;
  final String pieceName;
  final DateTime captureDate;
  final String projectRoot;      // absolute path on device
  final List<CapturedImage> images;
  final CoverageState coverage;
  final String? scaleReference;  // e.g. "aruco_marker", "ruler_200mm"
  final double? estimatedMmPerPixel;
  final bool calibrationDone;
  final bool sessionComplete;

  const CaptureSession({
    required this.projectId,
    required this.pieceName,
    required this.captureDate,
    required this.projectRoot,
    required this.images,
    required this.coverage,
    this.scaleReference,
    this.estimatedMmPerPixel,
    required this.calibrationDone,
    required this.sessionComplete,
  });

  // Counts per pass
  int get orbitCount => images.where((i) => i.pass == CapturePass.orbit).length;
  int get macroCount => images.where((i) => i.pass == CapturePass.macro).length;
  int get baseCount => images.where((i) => i.pass == CapturePass.base).length;
  int get scaleCount => images.where((i) => i.pass == CapturePass.scale).length;
  int get calibCount => images.where((i) => i.pass == CapturePass.calibration).length;
  int get totalImages => images.length;

  // Stage completion checks
  bool get orbitComplete => coverage.meetsTarget;
  bool get macroComplete => macroCount >= 1;
  bool get baseComplete => baseCount >= 1;
  bool get scaleComplete => scaleCount >= 1;

  Map<String, dynamic> toMetadataJson() => {
        'project_id': projectId,
        'piece_name': pieceName,
        'capture_date': captureDate.toIso8601String().substring(0, 10),
        'total_images': totalImages,
        'orbit_images': orbitCount,
        'macro_images': macroCount,
        'base_images': baseCount,
        'scale_images': scaleCount,
        'calibration_images': calibCount,
        'coverage': coverage.coveragePercent,
        'scale_reference': scaleReference,
        'estimated_scale_mm_per_pixel': estimatedMmPerPixel,
        'session_complete': sessionComplete,
      };

  factory CaptureSession.fromJson(Map<String, dynamic> json) =>
      _$CaptureSessionFromJson(json);
  Map<String, dynamic> toJson() => _$CaptureSessionToJson(this);

  CaptureSession copyWith({
    List<CapturedImage>? images,
    CoverageState? coverage,
    String? scaleReference,
    double? estimatedMmPerPixel,
    bool? calibrationDone,
    bool? sessionComplete,
  }) =>
      CaptureSession(
        projectId: projectId,
        pieceName: pieceName,
        captureDate: captureDate,
        projectRoot: projectRoot,
        images: images ?? this.images,
        coverage: coverage ?? this.coverage,
        scaleReference: scaleReference ?? this.scaleReference,
        estimatedMmPerPixel: estimatedMmPerPixel ?? this.estimatedMmPerPixel,
        calibrationDone: calibrationDone ?? this.calibrationDone,
        sessionComplete: sessionComplete ?? this.sessionComplete,
      );
}
