// lib/features/camera/widgets/pass_guide_banner.dart
import 'package:flutter/material.dart';
import '../../../core/models/capture_models.dart';
import '../../../core/constants/app_constants.dart';

class PassGuideBanner extends StatelessWidget {
  final CapturePass pass;
  final FrameAnalysis? analysis;
  const PassGuideBanner({super.key, required this.pass, required this.analysis});

  @override
  Widget build(BuildContext context) {
    final cfg = passConfigs[pass]!;
    final objectOk =
        !cfg.requiresObjectDetected || (analysis?.objectInFrame ?? false);
    final scaleOk =
        !cfg.requiresScaleMarker || (analysis?.scaleMarkerVisible ?? false);
    final allOk = objectOk && scaleOk;

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (allOk ? Colors.black : AppColors.error).withOpacity(0.75),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: allOk ? cfg.color : AppColors.error,
          width: 1,
        ),
      ),
      child: Row(children: [
        Icon(cfg.icon, color: cfg.color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cfg.title,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: cfg.color)),
              Text(
                !objectOk
                    ? '⚠ Object not detected'
                    : !scaleOk
                        ? '⚠ Scale marker not visible'
                        : cfg.subtitle,
                style: TextStyle(
                    fontSize: 10,
                    color: allOk ? AppColors.textSecondary : Colors.white),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}
