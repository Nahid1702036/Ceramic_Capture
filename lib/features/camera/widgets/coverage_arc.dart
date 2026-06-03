// lib/features/camera/widgets/coverage_arc.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/models/capture_models.dart';
import '../../../core/services/coverage_engine.dart';
import '../../../core/constants/app_constants.dart';

class CoverageArc extends StatelessWidget {
  final CoverageState coverage;
  const CoverageArc({super.key, required this.coverage});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: CustomPaint(painter: _ArcPainter(coverage)),
          ),
          const SizedBox(height: 4),
          Text(
            '${coverage.coveragePercent.toStringAsFixed(0)}%',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: coverage.meetsTarget
                    ? AppColors.success
                    : AppColors.warning),
          ),
          const Text('coverage',
              style: TextStyle(fontSize: 9, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          _ZoneDots(coverage: coverage),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final CoverageState coverage;
  _ArcPainter(this.coverage);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Background ring
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.white12
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6);

    // Coverage arc
    final sweepAngle =
        (coverage.coveragePercent / 100) * 2 * math.pi;
    final paint = Paint()
      ..color = coverage.meetsTarget ? AppColors.success : AppColors.warning
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      paint,
    );

    // 85% target marker
    final targetAngle = -math.pi / 2 + 0.85 * 2 * math.pi;
    final tx = center.dx + radius * math.cos(targetAngle);
    final ty = center.dy + radius * math.sin(targetAngle);
    canvas.drawCircle(Offset(tx, ty), 3, Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.coverage.coveragePercent != coverage.coveragePercent;
}

class _ZoneDots extends StatelessWidget {
  final CoverageState coverage;
  const _ZoneDots({required this.coverage});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: CoverageZone.values.map((zone) {
        final hits = coverage.zoneHits[zone] ?? 0;
        final status = CoverageEngine.zoneStatus(hits);
        final color = status == ZoneStatus.good
            ? AppColors.success
            : status == ZoneStatus.adequate
                ? AppColors.warning
                : Colors.white24;
        return Tooltip(
          message: '${CoverageEngine.zoneLabel(zone)}: $hits',
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        );
      }).toList(),
    );
  }
}
