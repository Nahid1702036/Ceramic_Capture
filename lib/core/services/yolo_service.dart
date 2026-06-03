// lib/core/services/yolo_service.dart
//
// Dual-mode YOLO inference:
//   PROD → TFLite (yolov8_ceramic.tflite bundled in assets/models/)
//   DEV  → FastAPI HTTP endpoint on Zorin (http://192.168.x.x:8000/predict)
//
// Classes (must match training label order):
//   0: ceramic_object
//   1: maker_mark
//   2: signature
//   3: stamp
//   4: foot_ring
//   5: scale_marker

import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../models/capture_models.dart'; // Detection, PhysicsState, YoloClass, InferenceMode
import '../constants/app_constants.dart';

class YoloService {
  static const List<YoloClass> _classOrder = [
    YoloClass.ceramicObject,
    YoloClass.makerMark,
    YoloClass.signature,
    YoloClass.stamp,
    YoloClass.footRing,
    YoloClass.scaleMarker,
  ];

  Interpreter? _interpreter;
  bool _isInitialized = false;

  final InferenceMode mode;
  final String? fastapiHost; // e.g. "192.168.1.42:8000"

  /// Active session id — set by SessionNotifier after POST /session/start.
  /// When set, predictions go to /predict/{sessionId} instead of /predict.
  String? _sessionId;
  void setSessionId(String? id) => _sessionId = id;

  YoloService({
    this.mode = InferenceMode.tflite,
    this.fastapiHost,
  });

  // ─── Initialization ─────────────────────────────────────────────────────────

  Future<void> init() async {
    if (mode == InferenceMode.tflite) {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/yolov8_ceramic.tflite',
        options: InterpreterOptions()..threads = 4,
      );
      _isInitialized = true;
    } else {
      // FastAPI mode: no init needed, just verify host is set
      assert(fastapiHost != null, 'fastapiHost must be set in dev mode');
      _isInitialized = true;
    }
  }

  void dispose() {
    _interpreter?.close();
    _isInitialized = false;
  }

  // ─── Main inference entry point ─────────────────────────────────────────────
  //
  // Returns ({ detections, physics }) where physics is null in TFLite mode
  // or when the server is running YOLO-only (no FAPE).

  Future<({List<Detection> detections, PhysicsState? physics})> detect(
      Uint8List imageBytes) async {
    assert(_isInitialized, 'Call init() first');
    if (mode == InferenceMode.tflite) {
      final dets = await _detectTFLite(imageBytes);
      return (detections: dets, physics: null);
    } else {
      return await _detectFastAPI(imageBytes);
    }
  }

  // ─── TFLite inference ───────────────────────────────────────────────────────

  Future<List<Detection>> _detectTFLite(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) return [];

    // YOLOv8 expects 640×640 RGB float32 normalised [0,1]
    const inputSize = 640;
    final resized = img.copyResize(image, width: inputSize, height: inputSize);
    final input = _imageToFloat32(resized, inputSize);

    // Output shape: [1, 10, 8400] — 10 = 4 bbox + 6 class scores
    final outputShape = _interpreter!.getOutputTensor(0).shape;
    final output = List.generate(
      outputShape[0],
      (_) => List.generate(
        outputShape[1],
        (_) => List.filled(outputShape[2], 0.0),
      ),
    );

    _interpreter!.run(input, output);
    return _parseYolov8Output(output[0], inputSize);
  }

  List<List<List<double>>> _imageToFloat32(img.Image image, int size) {
    final input = List.generate(
      1,
      (_) => List.generate(
        3,
        (c) => List.generate(size * size, (i) {
          final x = i % size;
          final y = i ~/ size;
          final pixel = image.getPixel(x, y);
          if (c == 0) return pixel.r / 255.0;
          if (c == 1) return pixel.g / 255.0;
          return pixel.b / 255.0;
        }),
      ),
    );
    return input;
  }

  List<Detection> _parseYolov8Output(
      List<List<double>> output, int inputSize) {
    final detections = <Detection>[];
    const confThreshold = 0.45;
    const nmsThreshold = 0.5;

    // output[row][col]: rows = [cx, cy, w, h, cls0..cls5], cols = 8400 anchors
    final numAnchors = output[0].length;
    final candidates = <_RawDetection>[];

    for (int a = 0; a < numAnchors; a++) {
      final cx = output[0][a];
      final cy = output[1][a];
      final w = output[2][a];
      final h = output[3][a];

      // Find best class
      double bestConf = 0;
      int bestCls = 0;
      for (int c = 0; c < _classOrder.length; c++) {
        final score = output[4 + c][a];
        if (score > bestConf) {
          bestConf = score;
          bestCls = c;
        }
      }

      if (bestConf >= confThreshold) {
        candidates.add(_RawDetection(
          cls: bestCls,
          conf: bestConf,
          cx: cx / inputSize,
          cy: cy / inputSize,
          w: w / inputSize,
          h: h / inputSize,
        ));
      }
    }

    // Simple NMS per class
    final kept = _nms(candidates, nmsThreshold);
    for (final d in kept) {
      detections.add(Detection(
        cls: _classOrder[d.cls],
        confidence: d.conf,
        x: (d.cx - d.w / 2).clamp(0.0, 1.0),
        y: (d.cy - d.h / 2).clamp(0.0, 1.0),
        w: d.w.clamp(0.0, 1.0),
        h: d.h.clamp(0.0, 1.0),
      ));
    }

    return detections;
  }

  List<_RawDetection> _nms(List<_RawDetection> dets, double threshold) {
    dets.sort((a, b) => b.conf.compareTo(a.conf));
    final kept = <_RawDetection>[];
    final suppressed = List.filled(dets.length, false);

    for (int i = 0; i < dets.length; i++) {
      if (suppressed[i]) continue;
      kept.add(dets[i]);
      for (int j = i + 1; j < dets.length; j++) {
        if (dets[i].cls == dets[j].cls &&
            _iou(dets[i], dets[j]) > threshold) {
          suppressed[j] = true;
        }
      }
    }
    return kept;
  }

  double _iou(_RawDetection a, _RawDetection b) {
    final ax1 = a.cx - a.w / 2, ay1 = a.cy - a.h / 2;
    final ax2 = a.cx + a.w / 2, ay2 = a.cy + a.h / 2;
    final bx1 = b.cx - b.w / 2, by1 = b.cy - b.h / 2;
    final bx2 = b.cx + b.w / 2, by2 = b.cy + b.h / 2;

    final ix = (ax2 < bx2 ? ax2 : bx2) - (ax1 > bx1 ? ax1 : bx1);
    final iy = (ay2 < by2 ? ay2 : by2) - (ay1 > by1 ? ay1 : by1);
    if (ix <= 0 || iy <= 0) return 0;
    final inter = ix * iy;
    return inter / (a.w * a.h + b.w * b.h - inter);
  }

  // ─── FastAPI HTTP inference (dev mode) ─────────────────────────────────────
  //
  // Talks to either:
  //   /predict/{sessionId}  → { detections:[…], physics:{…} }   (session-aware)
  //   /predict              → { detections:[…], physics:null }   (stateless)
  //   /predict              → […]                                (legacy bare array)

  Future<({List<Detection> detections, PhysicsState? physics})>
      _detectFastAPI(Uint8List bytes) async {
    try {
      // Use session endpoint when sessionId is set, else stateless fallback.
      final path = (_sessionId != null && _sessionId!.isNotEmpty)
          ? 'predict/$_sessionId'
          : 'predict';
      final uri = Uri.parse('http://$fastapiHost/$path');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/octet-stream'},
        body: bytes,
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        return (detections: <Detection>[], physics: null);
      }

      final decoded = jsonDecode(response.body);

      // ── New shape: { detections:[…], physics:{…} } ──────────────────
      if (decoded is Map<String, dynamic>) {
        final rawDets = decoded['detections'] as List<dynamic>? ?? [];
        final dets = rawDets
            .map((d) => Detection.fromJson(d as Map<String, dynamic>))
            .toList();
        final physMap = decoded['physics'] as Map<String, dynamic>?;
        final physics = physMap != null ? PhysicsState.fromJson(physMap) : null;
        return (detections: dets, physics: physics);
      }

      // ── Legacy shape: bare array ─────────────────────────────────────
      if (decoded is List<dynamic>) {
        final dets = decoded
            .map((d) => Detection.fromJson(d as Map<String, dynamic>))
            .toList();
        return (detections: dets, physics: null);
      }

      return (detections: <Detection>[], physics: null);
    } catch (_) {
      return (detections: <Detection>[], physics: null);
    }
  }

  // ─── Helpers for UI ─────────────────────────────────────────────────────────

  static bool hasClass(List<Detection> dets, YoloClass cls) =>
      dets.any((d) => d.cls == cls);

  static bool objectInFrame(List<Detection> dets) =>
      hasClass(dets, YoloClass.ceramicObject);

  static bool scaleMarkerVisible(List<Detection> dets) =>
      hasClass(dets, YoloClass.scaleMarker);

  static List<YoloClass> detectedFeatures(List<Detection> dets) =>
      dets.map((d) => d.cls).toSet().toList();
}

class _RawDetection {
  final int cls;
  final double conf, cx, cy, w, h;
  const _RawDetection({
    required this.cls,
    required this.conf,
    required this.cx,
    required this.cy,
    required this.w,
    required this.h,
  });
}
