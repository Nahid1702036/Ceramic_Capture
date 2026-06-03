// lib/features/camera/widgets/capture_button.dart
import 'package:flutter/material.dart';
import '../../../core/models/capture_models.dart';
import '../../../core/constants/app_constants.dart';

class CaptureButton extends StatelessWidget {
  final bool isCapturing;
  final CapturePass pass;
  final FrameAnalysis? analysis;
  final VoidCallback onCapture;

  const CaptureButton({
    super.key,
    required this.isCapturing,
    required this.pass,
    required this.analysis,
    required this.onCapture,
  });

  bool get _isBlocked {
    if (analysis == null) return false;
    return analysis!.qualityFlags.any(
        (f) => f == QualityFlag.blur || f == QualityFlag.blurMotion);
  }

  @override
  Widget build(BuildContext context) {
    final cfg = passConfigs[pass]!;
    final blocked = _isBlocked || isCapturing;
    final color = blocked ? AppColors.textSecondary : cfg.color;

    return GestureDetector(
      onTap: blocked ? null : onCapture,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.15),
          border: Border.all(color: color, width: 3),
        ),
        child: Center(
          child: isCapturing
              ? SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: color,
                    strokeWidth: 2,
                  ),
                )
              : Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
        ),
      ),
    );
  }
}
