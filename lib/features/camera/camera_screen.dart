// lib/features/camera/camera_screen.dart
//
// Full-screen camera viewfinder with:
//   • Live YOLO bounding box overlay
//   • Quality HUD (blur, exposure, duplicate indicators)
//   • Coverage arc (orbit pass only)
//   • Capture gating: button disabled if quality flags are critical
//   • Pass-specific guidance banner
//   • Shutter → writes to session via SessionNotifier

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/models/capture_models.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/yolo_service.dart';
import '../../core/services/quality_analyzer.dart';
import '../../core/services/coverage_engine.dart';
import 'providers/camera_providers.dart';
import 'widgets/yolo_overlay.dart';
import 'widgets/quality_hud.dart';
import 'widgets/coverage_arc.dart';
import 'widgets/pass_guide_banner.dart';
import 'widgets/capture_button.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitializing = true;
  bool _isCapturing = false;

  // Live analysis throttle — analyse every N frames
  int _frameCount = 0;
  static const int _analysisPeriod = 10; // every 10th frame

  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras == null || _cameras!.isEmpty) return;

    _controller = CameraController(
      _cameras![0],
      ResolutionPreset.veryHigh,
      imageFormatGroup: ImageFormatGroup.jpeg,
      enableAudio: false,
    );

    await _controller!.initialize();
    await _controller!.setFlashMode(FlashMode.off);

    // Start streaming for live analysis
    await _controller!.startImageStream(_onFrame);

    if (mounted) setState(() => _isInitializing = false);
  }

  void _onFrame(CameraImage image) {
    _frameCount++;
    if (_frameCount % _analysisPeriod != 0) return;
    _analyseFrame(image);
  }

  Future<void> _analyseFrame(CameraImage image) async {
    try {
      final bytes = _cameraImageToBytes(image);
      final yolo = ref.read(yoloServiceProvider);
      final qa = ref.read(qualityAnalyzerProvider);

      final results = await Future.wait([
        yolo.detect(bytes),
        qa.analyse(bytes),
      ]);

      final detections = results[0] as List<Detection>;
      final qualResult = results[1] as ({
        List<QualityFlag> flags,
        double sharpness,
        double exposure
      });
      final imu = ref.read(imuProvider);
      final zone = CoverageEngine.zoneFromImu(imu.azimuth, imu.elevation);

      final analysis = FrameAnalysis(
        detections: detections,
        qualityFlags: qualResult.flags,
        coveredZone: zone,
        scaleMarkerVisible: YoloService.scaleMarkerVisible(detections),
        objectInFrame: YoloService.objectInFrame(detections),
        sharpnessScore: qualResult.sharpness,
        exposureScore: qualResult.exposure,
      );

      ref.read(sessionProvider.notifier).updateLiveAnalysis(analysis);
    } catch (_) {}
  }

  Uint8List _cameraImageToBytes(CameraImage image) {
    // YUV420 → JPEG approximation via plane concatenation
    // In production, use a native plugin or compute isolate for proper conversion
    final WriteBuffer buffer = WriteBuffer();
    for (final plane in image.planes) {
      buffer.putUint8List(plane.bytes);
    }
    return buffer.done().buffer.asUint8List();
  }

  Future<void> _onCapture() async {
    if (_isCapturing || _controller == null) return;

    final pass = ref.read(activePassProvider);
    final analysis = ref.read(liveAnalysisProvider);

    // Gate: check pass-specific requirements
    if (!_meetsPassRequirements(pass, analysis)) return;

    setState(() => _isCapturing = true);
    _flashCapture();

    try {
      final xFile = await _controller!.takePicture();
      final bytes = await xFile.readAsBytes();

      final captured =
          await ref.read(sessionProvider.notifier).captureImage(
                bytes: bytes,
                pass: pass,
              );

      if (captured != null && mounted) {
        _showCaptureToast(captured);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  bool _meetsPassRequirements(CapturePass pass, FrameAnalysis? analysis) {
    if (analysis == null) return true; // allow if no analysis yet
    final config = passConfigs[pass]!;

    if (config.requiresObjectDetected && !analysis.objectInFrame) {
      _showRequirementWarning('Object not detected in frame');
      return false;
    }
    if (config.requiresScaleMarker && !analysis.scaleMarkerVisible) {
      _showRequirementWarning('Scale marker not visible');
      return false;
    }
    // Block on critical quality flags
    final blockers = [QualityFlag.blurMotion, QualityFlag.blur];
    if (analysis.qualityFlags.any(blockers.contains)) {
      _showRequirementWarning('Image too blurry — stabilise and retry');
      return false;
    }
    return true;
  }

  void _showRequirementWarning(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _flashCapture() {
    // Brief white flash overlay
    setState(() {});
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 80), () {
      if (mounted) setState(() {});
    });
  }

  void _showCaptureToast(CapturedImage image) {
    final flags = image.analysis.qualityFlags;
    final isOk = flags.isEmpty || flags.first == QualityFlag.ok;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(isOk ? Icons.check_circle : Icons.warning_amber,
              color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(isOk
              ? 'Captured ✓'
              : 'Captured with warnings: ${flags.map((f) => f.label).join(', ')}'),
        ]),
        backgroundColor: isOk ? AppColors.success : AppColors.warning,
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.stopImageStream();
    } else if (state == AppLifecycleState.resumed) {
      _controller?.startImageStream(_onFrame);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _controller?.dispose();
    _flashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pass = ref.watch(activePassProvider);
    final session = ref.watch(sessionProvider);
    final analysis = ref.watch(liveAnalysisProvider);
    final coverage = session?.coverage;

    return Scaffold(
      backgroundColor: Colors.black,
      body: _isInitializing
          ? const _LoadingView()
          : Stack(
              fit: StackFit.expand,
              children: [
                // ── Camera preview ──────────────────────────────────────
                CameraPreview(_controller!),

                // ── YOLO detection overlay ──────────────────────────────
                if (analysis != null)
                  YoloOverlay(
                    detections: analysis.detections,
                    pieceName: session?.pieceName,
                  ),

                // ── Top: pass guide banner ──────────────────────────────
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: PassGuideBanner(pass: pass, analysis: analysis),
                  ),
                ),

                // ── Quality HUD (top right) ─────────────────────────────
                Positioned(
                  top: 80,
                  right: 12,
                  child: QualityHud(analysis: analysis),
                ),

                // ── Orbit coverage arc (orbit pass only) ────────────────
                if (pass == CapturePass.orbit && coverage != null)
                  Positioned(
                    top: 80,
                    left: 12,
                    child: CoverageArc(coverage: coverage),
                  ),

                // ── Bottom controls ─────────────────────────────────────
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: _BottomBar(
                      pass: pass,
                      session: session,
                      analysis: analysis,
                      isCapturing: _isCapturing,
                      onCapture: _onCapture,
                      onPassChange: (p) =>
                          ref.read(activePassProvider.notifier).state = p,
                    ),
                  ),
                ),

                // ── Capture flash ───────────────────────────────────────
                if (_isCapturing)
                  Container(color: Colors.white.withOpacity(0.3)),
              ],
            ),
    );
  }
}

// ─── Bottom bar ───────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final CapturePass pass;
  final CaptureSession? session;
  final FrameAnalysis? analysis;
  final bool isCapturing;
  final VoidCallback onCapture;
  final ValueChanged<CapturePass> onPassChange;

  const _BottomBar({
    required this.pass,
    required this.session,
    required this.analysis,
    required this.isCapturing,
    required this.onCapture,
    required this.onPassChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.75),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pass selector chips
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: capturePassSequence.map((p) {
                final cfg = passConfigs[p]!;
                final isActive = p == pass;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => onPassChange(p),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive
                            ? cfg.color
                            : cfg.color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: cfg.color,
                            width: isActive ? 0 : 1),
                      ),
                      child: Row(children: [
                        Icon(cfg.icon,
                            size: 14,
                            color: isActive
                                ? Colors.black
                                : cfg.color),
                        const SizedBox(width: 4),
                        Text(cfg.title,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isActive
                                    ? Colors.black
                                    : cfg.color)),
                      ]),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // Counter + shutter + session info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Image count for current pass
              _PassCounter(pass: pass, session: session),

              // Shutter button
              CaptureButton(
                isCapturing: isCapturing,
                pass: pass,
                analysis: analysis,
                onCapture: onCapture,
              ),

              // Total images
              _TotalCounter(session: session),
            ],
          ),
        ],
      ),
    );
  }
}

class _PassCounter extends StatelessWidget {
  final CapturePass pass;
  final CaptureSession? session;

  const _PassCounter({required this.pass, required this.session});

  @override
  Widget build(BuildContext context) {
    final count = session?.images
            .where((i) => i.pass == pass)
            .length ??
        0;
    final target = passConfigs[pass]!.targetMin;
    final color = passConfigs[pass]!.color;

    return Column(children: [
      Text('$count',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: count >= target ? AppColors.success : color)),
      Text('/ $target min',
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
    ]);
  }
}

class _TotalCounter extends StatelessWidget {
  final CaptureSession? session;

  const _TotalCounter({required this.session});

  @override
  Widget build(BuildContext context) {
    final total = session?.totalImages ?? 0;
    return Column(children: [
      Text('$total',
          style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary)),
      const Text('total',
          style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
    ]);
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 12),
            Text('Initialising camera…',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
}
