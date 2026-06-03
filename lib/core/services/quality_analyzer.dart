// lib/core/services/quality_analyzer.dart
//
// Pure-Dart quality checks that mirror what OpenCV would give you.
// Uses the `image` package for pixel access — no native code needed,
// works identically on Android and iOS.
//
// Checks:
//   • Blur (Laplacian variance)
//   • Motion blur (directional gradient asymmetry)
//   • Overexposure  (>95% pixels above 230)
//   • Underexposure (<5% pixels above 30)
//   • Duplicate     (perceptual hash similarity to previous frame)

import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../models/capture_models.dart';

class QualityAnalyzer {
  // Thresholds (tune after field testing)
  static const double _blurThreshold = 80.0;        // Laplacian variance
  static const double _motionBlurThreshold = 0.35;  // gradient asymmetry ratio
  static const double _overexposureRatio = 0.15;    // > 15% saturated pixels → reject
  static const double _underexposureRatio = 0.15;
  static const int _duplicateHammingThreshold = 8;  // pHash bits that can differ

  // Last frame's pHash for duplicate detection
  String? _lastPHash;

  /// Analyse a JPEG/PNG [bytes] and return quality flags + scores.
  Future<({List<QualityFlag> flags, double sharpness, double exposure})>
      analyse(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) {
      return (
        flags: [QualityFlag.blur],
        sharpness: 0,
        exposure: 0.5,
      );
    }

    // Work on a downscaled grayscale copy for speed
    final small = img.copyResize(image, width: 320);
    final gray = img.grayscale(small);

    final sharpness = _laplacianVariance(gray);
    final exposure = _exposureScore(gray);
    final motionBlurScore = _motionBlurScore(gray);
    final currentHash = _pHash(gray);

    final flags = <QualityFlag>[];

    if (sharpness < _blurThreshold && motionBlurScore > _motionBlurThreshold) {
      flags.add(QualityFlag.blurMotion);
    } else if (sharpness < _blurThreshold) {
      flags.add(QualityFlag.blur);
    }

    final overRatio = _saturatedPixelRatio(gray, 230);
    if (overRatio > _overexposureRatio) flags.add(QualityFlag.overexposure);

    final underRatio = _darkPixelRatio(gray, 30);
    if (underRatio > _underexposureRatio) flags.add(QualityFlag.underexposure);

    if (_lastPHash != null &&
        _hammingDistance(currentHash, _lastPHash!) < _duplicateHammingThreshold) {
      flags.add(QualityFlag.duplicate);
    }
    _lastPHash = currentHash;

    return (
      flags: flags.isEmpty ? [QualityFlag.ok] : flags,
      sharpness: sharpness,
      exposure: exposure,
    );
  }

  void resetDuplicateState() => _lastPHash = null;

  // ─── Laplacian variance (sharpness) ────────────────────────────────────────

  double _laplacianVariance(img.Image gray) {
    final w = gray.width;
    final h = gray.height;
    final pixels = List.generate(h, (y) =>
        List.generate(w, (x) => _lum(gray, x, y)));

    double sum = 0;
    double sumSq = 0;
    int count = 0;

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final lap = -4 * pixels[y][x] +
            pixels[y - 1][x] +
            pixels[y + 1][x] +
            pixels[y][x - 1] +
            pixels[y][x + 1];
        sum += lap;
        sumSq += lap * lap;
        count++;
      }
    }
    final mean = sum / count;
    return (sumSq / count) - (mean * mean);
  }

  // ─── Motion blur (horizontal vs vertical gradient asymmetry) ───────────────

  double _motionBlurScore(img.Image gray) {
    final w = gray.width;
    final h = gray.height;
    double hGrad = 0, vGrad = 0;

    for (int y = 0; y < h; y++) {
      for (int x = 1; x < w - 1; x++) {
        hGrad += (_lum(gray, x + 1, y) - _lum(gray, x - 1, y)).abs();
      }
    }
    for (int x = 0; x < w; x++) {
      for (int y = 1; y < h - 1; y++) {
        vGrad += (_lum(gray, x, y + 1) - _lum(gray, x, y - 1)).abs();
      }
    }
    final total = hGrad + vGrad;
    if (total == 0) return 0;
    // Strong asymmetry → likely motion blur in one direction
    return (hGrad - vGrad).abs() / total;
  }

  // ─── Exposure ───────────────────────────────────────────────────────────────

  double _exposureScore(img.Image gray) {
    double sum = 0;
    for (int y = 0; y < gray.height; y++) {
      for (int x = 0; x < gray.width; x++) {
        sum += _lum(gray, x, y);
      }
    }
    final mean = sum / (gray.width * gray.height * 255);
    // Returns 0–1: 0.5 = ideal
    return mean;
  }

  double _saturatedPixelRatio(img.Image gray, int threshold) {
    int count = 0;
    for (int y = 0; y < gray.height; y++) {
      for (int x = 0; x < gray.width; x++) {
        if (_lum(gray, x, y) > threshold) count++;
      }
    }
    return count / (gray.width * gray.height);
  }

  double _darkPixelRatio(img.Image gray, int threshold) {
    int count = 0;
    for (int y = 0; y < gray.height; y++) {
      for (int x = 0; x < gray.width; x++) {
        if (_lum(gray, x, y) < threshold) count++;
      }
    }
    return count / (gray.width * gray.height);
  }

  // ─── Perceptual hash (8×8 DCT) ─────────────────────────────────────────────

  String _pHash(img.Image gray) {
    final thumb = img.copyResize(gray, width: 32, height: 32);
    // Simple average hash (fast, good enough for duplicate detection)
    int sum = 0;
    final vals = <int>[];
    for (int y = 0; y < 8; y++) {
      for (int x = 0; x < 8; x++) {
        final v = _lum(thumb, x * 4, y * 4);
        vals.add(v);
        sum += v;
      }
    }
    final mean = sum ~/ 64;
    return vals.map((v) => v >= mean ? '1' : '0').join();
  }

  int _hammingDistance(String a, String b) {
    int dist = 0;
    for (int i = 0; i < math.min(a.length, b.length); i++) {
      if (a[i] != b[i]) dist++;
    }
    return dist;
  }

  // ─── Pixel luminance helper ─────────────────────────────────────────────────

  int _lum(img.Image g, int x, int y) {
    final p = g.getPixel(x, y);
    return p.r.toInt();   // grayscale R == G == B
  }
}

// ─── Human-readable flag descriptions ─────────────────────────────────────────

extension QualityFlagLabel on QualityFlag {
  String get label {
    switch (this) {
      case QualityFlag.ok: return 'OK';
      case QualityFlag.blur: return 'Blurry';
      case QualityFlag.blurMotion: return 'Motion blur';
      case QualityFlag.overexposure: return 'Overexposed';
      case QualityFlag.underexposure: return 'Underexposed';
      case QualityFlag.duplicate: return 'Duplicate';
    }
  }

  String get emoji {
    switch (this) {
      case QualityFlag.ok: return '✓';
      case QualityFlag.blur: return '🌫';
      case QualityFlag.blurMotion: return '💨';
      case QualityFlag.overexposure: return '☀️';
      case QualityFlag.underexposure: return '🌑';
      case QualityFlag.duplicate: return '⧉';
    }
  }
}
