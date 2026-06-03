// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'capture_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Detection _$DetectionFromJson(Map<String, dynamic> json) => Detection(
      cls: $enumDecode(_$YoloClassEnumMap, json['cls']),
      confidence: (json['confidence'] as num).toDouble(),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      w: (json['w'] as num).toDouble(),
      h: (json['h'] as num).toDouble(),
    );

Map<String, dynamic> _$DetectionToJson(Detection instance) => <String, dynamic>{
      'cls': _$YoloClassEnumMap[instance.cls]!,
      'confidence': instance.confidence,
      'x': instance.x,
      'y': instance.y,
      'w': instance.w,
      'h': instance.h,
    };

const _$YoloClassEnumMap = {
  YoloClass.ceramicObject: 'ceramicObject',
  YoloClass.makerMark: 'makerMark',
  YoloClass.signature: 'signature',
  YoloClass.stamp: 'stamp',
  YoloClass.footRing: 'footRing',
  YoloClass.scaleMarker: 'scaleMarker',
};

FrameAnalysis _$FrameAnalysisFromJson(Map<String, dynamic> json) =>
    FrameAnalysis(
      detections: (json['detections'] as List<dynamic>)
          .map((e) => Detection.fromJson(e as Map<String, dynamic>))
          .toList(),
      qualityFlags: (json['qualityFlags'] as List<dynamic>)
          .map((e) => $enumDecode(_$QualityFlagEnumMap, e))
          .toList(),
      coveredZone:
          $enumDecodeNullable(_$CoverageZoneEnumMap, json['coveredZone']),
      scaleMarkerVisible: json['scaleMarkerVisible'] as bool,
      objectInFrame: json['objectInFrame'] as bool,
      sharpnessScore: (json['sharpnessScore'] as num).toDouble(),
      exposureScore: (json['exposureScore'] as num).toDouble(),
    );

Map<String, dynamic> _$FrameAnalysisToJson(FrameAnalysis instance) =>
    <String, dynamic>{
      'detections': instance.detections,
      'qualityFlags':
          instance.qualityFlags.map((e) => _$QualityFlagEnumMap[e]!).toList(),
      'coveredZone': _$CoverageZoneEnumMap[instance.coveredZone],
      'scaleMarkerVisible': instance.scaleMarkerVisible,
      'objectInFrame': instance.objectInFrame,
      'sharpnessScore': instance.sharpnessScore,
      'exposureScore': instance.exposureScore,
    };

const _$QualityFlagEnumMap = {
  QualityFlag.ok: 'ok',
  QualityFlag.blurMotion: 'blurMotion',
  QualityFlag.blur: 'blur',
  QualityFlag.overexposure: 'overexposure',
  QualityFlag.underexposure: 'underexposure',
  QualityFlag.duplicate: 'duplicate',
};

const _$CoverageZoneEnumMap = {
  CoverageZone.front: 'front',
  CoverageZone.rear: 'rear',
  CoverageZone.left: 'left',
  CoverageZone.right: 'right',
  CoverageZone.top: 'top',
  CoverageZone.bottom: 'bottom',
};

PhysicsState _$PhysicsStateFromJson(Map<String, dynamic> json) => PhysicsState(
      rhoFil: (json['rhoFil'] as num).toDouble(),
      kMu: (json['kMu'] as num).toDouble(),
      sigma2K: (json['sigma2K'] as num).toDouble(),
      trs: (json['trs'] as num).toDouble(),
      frameValid: json['frameValid'] as bool,
    );

Map<String, dynamic> _$PhysicsStateToJson(PhysicsState instance) =>
    <String, dynamic>{
      'rhoFil': instance.rhoFil,
      'kMu': instance.kMu,
      'sigma2K': instance.sigma2K,
      'trs': instance.trs,
      'frameValid': instance.frameValid,
    };

CapturedImage _$CapturedImageFromJson(Map<String, dynamic> json) =>
    CapturedImage(
      id: json['id'] as String,
      filePath: json['filePath'] as String,
      colmapPath: json['colmapPath'] as String,
      pass: $enumDecode(_$CapturePassEnumMap, json['pass']),
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      analysis:
          FrameAnalysis.fromJson(json['analysis'] as Map<String, dynamic>),
      imuAzimuth: (json['imuAzimuth'] as num?)?.toDouble(),
      imuElevation: (json['imuElevation'] as num?)?.toDouble(),
      zone: $enumDecodeNullable(_$CoverageZoneEnumMap, json['zone']),
      physics: json['physics'] == null
          ? null
          : PhysicsState.fromJson(json['physics'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$CapturedImageToJson(CapturedImage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'filePath': instance.filePath,
      'colmapPath': instance.colmapPath,
      'pass': _$CapturePassEnumMap[instance.pass]!,
      'capturedAt': instance.capturedAt.toIso8601String(),
      'analysis': instance.analysis,
      'imuAzimuth': instance.imuAzimuth,
      'imuElevation': instance.imuElevation,
      'zone': _$CoverageZoneEnumMap[instance.zone],
      'physics': instance.physics,
    };

const _$CapturePassEnumMap = {
  CapturePass.calibration: 'calibration',
  CapturePass.orbit: 'orbit',
  CapturePass.macro: 'macro',
  CapturePass.base: 'base',
  CapturePass.scale: 'scale',
};

CoverageState _$CoverageStateFromJson(Map<String, dynamic> json) =>
    CoverageState(
      zoneHits: (json['zoneHits'] as Map<String, dynamic>).map(
        (k, e) =>
            MapEntry($enumDecode(_$CoverageZoneEnumMap, k), (e as num).toInt()),
      ),
      coveragePercent: (json['coveragePercent'] as num).toDouble(),
      meetsTarget: json['meetsTarget'] as bool,
    );

Map<String, dynamic> _$CoverageStateToJson(CoverageState instance) =>
    <String, dynamic>{
      'zoneHits': instance.zoneHits
          .map((k, e) => MapEntry(_$CoverageZoneEnumMap[k]!, e)),
      'coveragePercent': instance.coveragePercent,
      'meetsTarget': instance.meetsTarget,
    };

CaptureSession _$CaptureSessionFromJson(Map<String, dynamic> json) =>
    CaptureSession(
      projectId: json['projectId'] as String,
      pieceName: json['pieceName'] as String,
      captureDate: DateTime.parse(json['captureDate'] as String),
      projectRoot: json['projectRoot'] as String,
      images: (json['images'] as List<dynamic>)
          .map((e) => CapturedImage.fromJson(e as Map<String, dynamic>))
          .toList(),
      coverage:
          CoverageState.fromJson(json['coverage'] as Map<String, dynamic>),
      scaleReference: json['scaleReference'] as String?,
      estimatedMmPerPixel: (json['estimatedMmPerPixel'] as num?)?.toDouble(),
      calibrationDone: json['calibrationDone'] as bool,
      sessionComplete: json['sessionComplete'] as bool,
    );

Map<String, dynamic> _$CaptureSessionToJson(CaptureSession instance) =>
    <String, dynamic>{
      'projectId': instance.projectId,
      'pieceName': instance.pieceName,
      'captureDate': instance.captureDate.toIso8601String(),
      'projectRoot': instance.projectRoot,
      'images': instance.images,
      'coverage': instance.coverage,
      'scaleReference': instance.scaleReference,
      'estimatedMmPerPixel': instance.estimatedMmPerPixel,
      'calibrationDone': instance.calibrationDone,
      'sessionComplete': instance.sessionComplete,
    };
