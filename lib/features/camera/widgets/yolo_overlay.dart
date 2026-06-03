// lib/features/camera/widgets/yolo_overlay.dart
//
// Ceramic-aware YOLO overlay:
//
//   ┌─────────────────────────────────────────┐
//   │  ░░░░░░░░░ dim vignette ░░░░░░░░░░░░░░  │
//   │  ░░░                             ░░░░░  │
//   │  ░░░   ╭───────────────────────╮ ░░░░░  │
//   │  ░░░   │  (clear spotlight)    │ ░░░░░  │
//   │  ░░░   │                       │ ░░░░░  │
//   │  ░░░   ╰───────────────────────╯ ░░░░░  │
//   │  ░░░    ┌ Tang Dynasty Vase 94%┐ ░░░░░  │
//   │  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ ░░░░░  │
//   └─────────────────────────────────────────┘
//
//  • When ceramicObject is detected:
//      – soft vignette dims everything outside the bbox (saveLayer + dstOut blur)
//      – a gentle glowing rounded border frames the object
//      – a pill label shows the session piece name + confidence
//  • Secondary detections (marks, signatures, …) get small subtle tag chips
//    inside the lit area, not obstructive labels.
//  • When nothing is detected the canvas is untouched so the full frame is
//    visible and the user can reposition.

import 'package:flutter/material.dart';
import '../../../core/models/capture_models.dart';
import '../../../core/constants/app_constants.dart';

class YoloOverlay extends StatelessWidget {
  final List<Detection> detections;

  /// Session piece name shown in the label, e.g. "Tang Dynasty Vase".
  /// Falls back to "Ceramic Object" when null.
  final String? pieceName;

  const YoloOverlay({
    super.key,
    required this.detections,
    this.pieceName,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _YoloPainter(detections, pieceName),
      child: const SizedBox.expand(),
    );
  }
}

// ─── Painter ──────────────────────────────────────────────────────────────────

class _YoloPainter extends CustomPainter {
  final List<Detection> detections;
  final String? pieceName;

  _YoloPainter(this.detections, this.pieceName);

  // Class colours for secondary detections
  static const _classColors = <YoloClass, Color>{
    YoloClass.ceramicObject: AppColors.orbit,
    YoloClass.makerMark:     AppColors.macro,
    YoloClass.signature:     Color(0xFFB5179E),
    YoloClass.stamp:         Color(0xFF7209B7),
    YoloClass.footRing:      AppColors.base,
    YoloClass.scaleMarker:   AppColors.scale,
  };

  // Short display names for secondary feature chips
  static const _featureLabels = <YoloClass, String>{
    YoloClass.makerMark:   'Maker Mark',
    YoloClass.signature:   'Signature',
    YoloClass.stamp:       'Stamp',
    YoloClass.footRing:    'Foot Ring',
    YoloClass.scaleMarker: '⊡ Scale',
  };

  @override
  void paint(Canvas canvas, Size size) {
    // Pick the highest-confidence ceramicObject detection as the primary target.
    final ceramicDet = detections
        .where((d) => d.cls == YoloClass.ceramicObject)
        .fold<Detection?>(
          null,
          (best, d) => best == null || d.confidence > best.confidence ? d : best,
        );

    if (ceramicDet != null) {
      final bbox = Rect.fromLTWH(
        ceramicDet.x * size.width,
        ceramicDet.y * size.height,
        ceramicDet.w * size.width,
        ceramicDet.h * size.height,
      );

      _drawVignette(canvas, size, bbox);
      _drawSoftBorder(canvas, bbox);
      _drawLabel(
        canvas,
        size,
        bbox,
        '${pieceName ?? "Ceramic Object"}  ${(ceramicDet.confidence * 100).toStringAsFixed(0)}%',
      );
    }

    // Secondary feature detections — subtle chips, won't obstruct the view.
    for (final det in detections) {
      if (det.cls == YoloClass.ceramicObject) continue;
      final color = _classColors[det.cls] ?? Colors.white;
      final rect = Rect.fromLTWH(
        det.x * size.width,
        det.y * size.height,
        det.w * size.width,
        det.h * size.height,
      );
      _drawFeatureChip(canvas, rect, color, _featureLabels[det.cls] ?? det.cls.name);
    }
  }

  // ─── Soft vignette (spotlight) ─────────────────────────────────────────────

  /// Dims the whole canvas then punches a feathered hole at [bbox].
  /// Uses saveLayer + BlendMode.dstOut so the cutout edges are soft.
  void _drawVignette(Canvas canvas, Size size, Rect bbox) {
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);

    canvas.saveLayer(fullRect, Paint());

    // Dark overlay across the full frame
    canvas.drawRect(
      fullRect,
      Paint()..color = Colors.black.withOpacity(0.72),
    );

    // Feathered hole — expand the bbox slightly so the glow border sits in
    // the transition zone rather than inside the sharp cutout.
    canvas.drawRRect(
      RRect.fromRectAndRadius(bbox.inflate(18), const Radius.circular(22)),
      Paint()
        ..blendMode = BlendMode.dstOut
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22)
        ..color = Colors.white,
    );

    canvas.restore();
  }

  // ─── Soft glowing border ───────────────────────────────────────────────────

  void _drawSoftBorder(Canvas canvas, Rect bbox) {
    const color = AppColors.orbit;
    const cornerRadius = 14.0;
    final rRect = RRect.fromRectAndRadius(bbox, const Radius.circular(cornerRadius));

    // Concentric glow layers (outermost → innermost)
    for (int i = 3; i >= 1; i--) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          bbox.inflate(i * 3.0),
          Radius.circular(cornerRadius + i * 3.0),
        ),
        Paint()
          ..color = color.withOpacity(0.07 * i)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, i * 4.0),
      );
    }

    // Primary border — thin, rounded, semi-transparent
    canvas.drawRRect(
      rRect,
      Paint()
        ..color = color.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );

    // Soft corner accents (dots, not hard ticks)
    final dotPaint = Paint()..color = color;
    const dotR = 3.0;
    for (final corner in [
      bbox.topLeft,
      bbox.topRight,
      bbox.bottomLeft,
      bbox.bottomRight,
    ]) {
      canvas.drawCircle(corner, dotR, dotPaint);
    }
  }

  // ─── Piece-name label pill ─────────────────────────────────────────────────

  void _drawLabel(Canvas canvas, Size size, Rect bbox, String text) {
    const color = AppColors.orbit;
    const fontSize = 12.0;
    const hPad = 14.0;
    const vPad = 7.0;
    const radius = 20.0;

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * 0.75);

    final pillW = tp.width + hPad * 2;
    final pillH = tp.height + vPad * 2;

    // Prefer centred below the bbox; flip above if too close to the bottom.
    double px = bbox.center.dx - pillW / 2;
    double py = bbox.bottom + 10;
    if (py + pillH > size.height - 12) py = bbox.top - pillH - 10;
    px = px.clamp(10.0, size.width - pillW - 10.0);

    final pillRect = Rect.fromLTWH(px, py, pillW, pillH);
    final pillRRect = RRect.fromRectAndRadius(pillRect, const Radius.circular(radius));

    // Drop shadow first
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        pillRect.shift(const Offset(0, 3)),
        const Radius.circular(radius),
      ),
      Paint()
        ..color = Colors.black.withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Pill background
    canvas.drawRRect(pillRRect, Paint()..color = color.withOpacity(0.88));

    // Label text
    tp.paint(canvas, Offset(px + hPad, py + vPad));
  }

  // ─── Secondary feature chip ────────────────────────────────────────────────

  void _drawFeatureChip(Canvas canvas, Rect rect, Color color, String label) {
    final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(7));

    // Subtle dashed-style border (two alternating strokes faked with opacity)
    canvas.drawRRect(
      rRect,
      Paint()
        ..color = color.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Tiny tag chip above the box
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const chipHPad = 5.0;
    const chipVPad = 3.0;
    final chipW = tp.width + chipHPad * 2;
    final chipH = tp.height + chipVPad * 2;

    final chipRect = Rect.fromLTWH(
      rect.left + 4,
      rect.top - chipH / 2 - 2,
      chipW,
      chipH,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(chipRect, const Radius.circular(4)),
      Paint()..color = color.withOpacity(0.82),
    );
    tp.paint(canvas, Offset(chipRect.left + chipHPad, chipRect.top + chipVPad));
  }

  @override
  bool shouldRepaint(_YoloPainter old) =>
      old.detections != detections || old.pieceName != pieceName;
}
