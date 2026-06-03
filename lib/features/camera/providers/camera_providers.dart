// lib/features/camera/providers/camera_providers.dart
//
// Central state management for the active capture session.
// Uses Riverpod StateNotifier pattern.

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/capture_models.dart';
import '../../../core/services/yolo_service.dart';
import '../../../core/services/quality_analyzer.dart';
import '../../../core/services/coverage_engine.dart';
import '../../../core/services/project_file_service.dart';
import '../../../core/constants/app_constants.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

// ─── Session provider ────────────────────────────────────────────────────────

final sessionProvider =
    StateNotifierProvider<SessionNotifier, CaptureSession?>((ref) {
  return SessionNotifier(ref);
});

// ─── Active pass provider ─────────────────────────────────────────────────────

final activePassProvider = StateProvider<CapturePass>((ref) {
  return CapturePass.calibration;
});

// ─── Live frame analysis provider ────────────────────────────────────────────

final liveAnalysisProvider = StateProvider<FrameAnalysis?>((ref) => null);

// ─── IMU state provider ───────────────────────────────────────────────────────

final imuProvider = StateProvider<({double azimuth, double elevation})>(
    (ref) => (azimuth: 0, elevation: 0));

// ─── YOLO service provider ────────────────────────────────────────────────────

final yoloServiceProvider = Provider<YoloService>((ref) {
  // Switch to InferenceMode.fastapi + fastapiHost for dev
  final service = YoloService(mode: InferenceMode.tflite);
  ref.onDispose(service.dispose);
  return service;
});

// ─── Quality analyzer provider ────────────────────────────────────────────────

final qualityAnalyzerProvider = Provider<QualityAnalyzer>((ref) {
  return QualityAnalyzer();
});

// ─── File service provider ────────────────────────────────────────────────────

final fileServiceProvider = Provider<ProjectFileService>((ref) {
  return ProjectFileService();
});

// ─── Frame counter (for naming) ───────────────────────────────────────────────

final frameCountProvider = StateProvider.family<int, CapturePass>((ref, pass) => 0);

// ─── Session notifier ─────────────────────────────────────────────────────────

class SessionNotifier extends StateNotifier<CaptureSession?> {
  final Ref _ref;
  static const _uuid = Uuid();

  StreamSubscription? _imuSub;

  SessionNotifier(this._ref) : super(null) {
    _initImu();
  }

  void _initImu() {
    // gyroscope gives rotation rates; we integrate for azimuth/elevation
    // For simplicity, accelerometer gives gravity direction → elevation
    _imuSub = accelerometerEventStream().listen((event) {
      // elevation: angle of gravity vector from horizontal
      final elevation = _ref.read(imuProvider).elevation;
      // Simple gravity-based elevation
      final newElevation = -event.y * 5.7; // crude scaling
      final newAzimuth = _ref.read(imuProvider).azimuth;
      _ref.read(imuProvider.notifier).state =
          (azimuth: newAzimuth, elevation: newElevation.clamp(-90.0, 90.0));
    });

    // Gyroscope integration for azimuth
    gyroscopeEventStream().listen((event) {
      final current = _ref.read(imuProvider);
      final newAz = (current.azimuth + event.z * 2.0) % 360;
      _ref.read(imuProvider.notifier).state =
          (azimuth: newAz, elevation: current.elevation);
    });
  }

  // ─── Create new session ───────────────────────────────────────────────────

  Future<void> createSession(String pieceName) async {
    final fileService = _ref.read(fileServiceProvider);
    final projectId =
        '${pieceName.toLowerCase().replaceAll(' ', '_')}_${_uuid.v4().substring(0, 6)}';
    final projectRoot = await fileService.createProjectRoot(pieceName);
    await fileService.writeColmapProjectIni(projectRoot);

    state = CaptureSession(
      projectId: projectId,
      pieceName: pieceName,
      captureDate: DateTime.now(),
      projectRoot: projectRoot,
      images: [],
      coverage: CoverageState.empty(),
      calibrationDone: false,
      sessionComplete: false,
    );

    // Notify server to initialise Kalman + SpecKCalibrator for this session.
    // Fire-and-forget — failure just means physics metadata won't be returned.
    _startServerSession(projectId);
  }

  /// POST /session/start — initialises SpecKCalibrator + KalmanThermalEstimator
  /// on the Zorin server.  Sets the session_id on YoloService so subsequent
  /// /predict calls go to /predict/{sessionId} and return physics metadata.
  Future<void> _startServerSession(String sessionId) async {
    final yolo = _ref.read(yoloServiceProvider);
    if (yolo.fastapiHost == null) return;          // TFLite mode — no server
    try {
      final uri = Uri.parse('http://${yolo.fastapiHost}/session/start');
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_id':   sessionId,
          'device_class': 'mobile',    // iPhone = mobile priors
        }),
      ).timeout(const Duration(seconds: 4));

      if (resp.statusCode == 200) {
        yolo.setSessionId(sessionId);
        print('[Session] server session started: $sessionId');
      }
    } catch (e) {
      print('[Session] /session/start failed (YOLO-only mode): $e');
    }
  }

  // ─── Capture image ────────────────────────────────────────────────────────

  Future<CapturedImage?> captureImage({
    required Uint8List bytes,
    required CapturePass pass,
  }) async {
    if (state == null) return null;

    final yolo = _ref.read(yoloServiceProvider);
    final qa = _ref.read(qualityAnalyzerProvider);
    final fileService = _ref.read(fileServiceProvider);
    final imu = _ref.read(imuProvider);

    // Run YOLO + quality analysis in parallel
    final results = await Future.wait([
      yolo.detect(bytes),
      qa.analyse(bytes),
    ]);

    final detectResult = results[0] as ({
      List<Detection> detections,
      PhysicsState? physics,
    });
    final detections = detectResult.detections;
    final physicsState = detectResult.physics;  // null in TFLite mode

    final qualResult = results[1] as ({
      List<QualityFlag> flags,
      double sharpness,
      double exposure
    });

    final imuAz = imu.azimuth;
    final imuEl = imu.elevation;
    final zone = CoverageEngine.zoneFromImu(imuAz, imuEl);

    final analysis = FrameAnalysis(
      detections: detections,
      qualityFlags: qualResult.flags,
      coveredZone: zone,
      scaleMarkerVisible: YoloService.scaleMarkerVisible(detections),
      objectInFrame: YoloService.objectInFrame(detections),
      sharpnessScore: qualResult.sharpness,
      exposureScore: qualResult.exposure,
    );

    // Get frame index
    final frameIdx = _ref.read(frameCountProvider(pass));
    _ref.read(frameCountProvider(pass).notifier).state = frameIdx + 1;

    // Save to disk
    final paths = await fileService.saveImage(
      projectRoot: state!.projectRoot,
      bytes: bytes,
      pass: pass,
      frameIndex: frameIdx,
    );

    final image = CapturedImage(
      id: _uuid.v4(),
      filePath: paths.imagePath,
      colmapPath: paths.colmapPath,
      pass: pass,
      capturedAt: DateTime.now(),
      analysis: analysis,
      imuAzimuth: imuAz,
      imuElevation: imuEl,
      zone: zone,
      physics: physicsState,   // Kalman scalars from server (null in TFLite mode)
    );

    // Update session
    final newImages = [...state!.images, image];
    final newCoverage = CoverageEngine.compute(newImages);
    final calibDone = state!.calibrationDone || pass == CapturePass.calibration;

    state = state!.copyWith(
      images: newImages,
      coverage: newCoverage,
      calibrationDone: calibDone,
    );

    // Persist metadata
    await fileService.writeMetadata(state!.projectRoot, state!);

    return image;
  }

  // ─── Mark session complete ────────────────────────────────────────────────

  Future<void> completeSession() async {
    if (state == null) return;
    state = state!.copyWith(sessionComplete: true);
    final fileService = _ref.read(fileServiceProvider);
    await fileService.writeCaptureReport(state!.projectRoot, state!);
  }

  // ─── Update live analysis (viewfinder feedback) ───────────────────────────

  void updateLiveAnalysis(FrameAnalysis analysis) {
    _ref.read(liveAnalysisProvider.notifier).state = analysis;
  }

  @override
  void dispose() {
    _imuSub?.cancel();
    super.dispose();
  }
}
