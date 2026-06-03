// lib/features/camera/widgets/quality_hud.dart
import 'package:flutter/material.dart';
import '../../../core/models/capture_models.dart';
import '../../../core/services/quality_analyzer.dart';
import '../../../core/constants/app_constants.dart';

class QualityHud extends StatelessWidget {
  final FrameAnalysis? analysis;
  const QualityHud({super.key, required this.analysis});

  @override
  Widget build(BuildContext context) {
    if (analysis == null) return const SizedBox.shrink();

    final flags = analysis!.qualityFlags;
    final sharpness = analysis!.sharpnessScore;
    final exposure = analysis!.exposureScore;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetricRow(
            label: 'Sharp',
            value: (sharpness / 300).clamp(0.0, 1.0),
            color: sharpness > 80
                ? AppColors.success
                : sharpness > 40
                    ? AppColors.warning
                    : AppColors.error,
          ),
          const SizedBox(height: 4),
          _MetricRow(
            label: 'Exp',
            value: exposure,
            color: (exposure > 0.3 && exposure < 0.8)
                ? AppColors.success
                : AppColors.warning,
          ),
          const SizedBox(height: 6),
          ...flags
              .where((f) => f != QualityFlag.ok)
              .map((f) => _FlagChip(flag: f)),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _MetricRow(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(
            width: 32,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 9, color: AppColors.textSecondary))),
        const SizedBox(width: 4),
        SizedBox(
          width: 60,
          height: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ]);
}

class _FlagChip extends StatelessWidget {
  final QualityFlag flag;
  const _FlagChip({required this.flag});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.8),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${flag.emoji} ${flag.label}',
          style: const TextStyle(fontSize: 9, color: Colors.white),
        ),
      );
}
