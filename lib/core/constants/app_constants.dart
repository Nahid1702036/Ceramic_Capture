// lib/core/constants/app_constants.dart

import 'package:flutter/material.dart';
import '../models/capture_models.dart';

class AppColors {
  static const background = Color(0xFF0D0D1A);
  static const surface = Color(0xFF1A1A2E);
  static const surfaceElevated = Color(0xFF252540);
  static const primary = Color(0xFF4CC9F0);    // electric blue
  static const accent = Color(0xFFE94560);     // coral red
  static const success = Color(0xFF2ECC71);
  static const warning = Color(0xFFF39C12);
  static const error = Color(0xFFE74C3C);
  static const textPrimary = Color(0xFFF0F0F0);
  static const textSecondary = Color(0xFF8888AA);
  static const orbit = Color(0xFF4CC9F0);
  static const macro = Color(0xFFB5179E);
  static const base = Color(0xFFF77F00);
  static const scale = Color(0xFF2ECC71);
  static const calibration = Color(0xFF888888);
}

class PassConfig {
  final CapturePass pass;
  final String title;
  final String subtitle;
  final String instruction;
  final int targetMin;       // minimum images recommended
  final Color color;
  final IconData icon;
  final bool requiresObjectDetected;
  final bool requiresScaleMarker;

  const PassConfig({
    required this.pass,
    required this.title,
    required this.subtitle,
    required this.instruction,
    required this.targetMin,
    required this.color,
    required this.icon,
    this.requiresObjectDetected = false,
    this.requiresScaleMarker = false,
  });
}

const passConfigs = <CapturePass, PassConfig>{
  CapturePass.calibration: PassConfig(
    pass: CapturePass.calibration,
    title: 'Calibration',
    subtitle: 'Empty rig shot',
    instruction:
        'Clear the rig completely — no object, no scale marker. '
        'Capture 1–3 frames of the empty setup before placing the piece.',
    targetMin: 1,
    color: AppColors.calibration,
    icon: Icons.camera_outlined,
  ),
  CapturePass.orbit: PassConfig(
    pass: CapturePass.orbit,
    title: 'Orbit Pass',
    subtitle: 'Full angular coverage ≥ 85%',
    instruction:
        'Walk the camera in a full orbit around the piece. '
        'Shoot from low, mid, and high angles. '
        'Coverage bar must reach 85% before proceeding.',
    targetMin: 60,
    color: AppColors.orbit,
    icon: Icons.threesixty,
    requiresObjectDetected: true,
  ),
  CapturePass.macro: PassConfig(
    pass: CapturePass.macro,
    title: 'Macro Pass',
    subtitle: 'Close-ups of every mark & feature',
    instruction:
        'Get within 20–30 cm of every mark, signature, stamp, and '
        'fine surface detail. YOLO will flag when a feature class '
        'is detected — confirm and capture.',
    targetMin: 10,
    color: AppColors.macro,
    icon: Icons.zoom_in,
    requiresObjectDetected: true,
  ),
  CapturePass.base: PassConfig(
    pass: CapturePass.base,
    title: 'Base Station',
    subtitle: 'Flip piece — capture foot & marks',
    instruction:
        'Invert the piece to expose the foot ring. '
        'Capture all marks, foot ring, and base surface. '
        'This is the only way to see the foot — do not skip.',
    targetMin: 10,
    color: AppColors.base,
    icon: Icons.flip,
    requiresObjectDetected: true,
  ),
  CapturePass.scale: PassConfig(
    pass: CapturePass.scale,
    title: 'Scale Reference',
    subtitle: 'ArUco marker / ruler must be visible',
    instruction:
        'Place the ArUco marker or ruler in the scene. '
        'Scale marker must be detected by YOLO before capture is accepted. '
        'COLMAP is scale-free without this.',
    targetMin: 3,
    color: AppColors.scale,
    icon: Icons.straighten,
    requiresObjectDetected: false,
    requiresScaleMarker: true,
  ),
};

// Ordered pass sequence for the guided workflow
const capturePassSequence = [
  CapturePass.calibration,
  CapturePass.orbit,
  CapturePass.macro,
  CapturePass.base,
  CapturePass.scale,
];

// Minimum sharpness score to display a "ready to shoot" indicator
const double minSharpnessForCapture = 80.0;

// FastAPI dev server default
const String defaultFastapiHost = '192.168.1.100:8000';
