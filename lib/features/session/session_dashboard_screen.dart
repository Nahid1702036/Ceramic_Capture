// lib/features/session/session_dashboard_screen.dart
//
// Mid-capture dashboard that lives between passes:
//   • Overall progress (stages done / 5)
//   • Coverage % dial
//   • Per-pass image counts vs targets
//   • "Enter Camera" button for current pass
//   • "Export Session" button when all stages complete

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/capture_models.dart';
import '../../core/services/coverage_engine.dart';
import '../../features/export/services/pdf_report_service.dart';
import '../camera/providers/camera_providers.dart';
import '../camera/camera_screen.dart';

class SessionDashboardScreen extends ConsumerWidget {
  const SessionDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.pieceName,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            Text(session.projectId,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CameraScreen()),
            ),
            tooltip: 'Open Camera',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Overview row ─────────────────────────────────────────────
            Row(children: [
              Expanded(child: _CoverageGauge(session: session)),
              const Gap(12),
              Expanded(child: _StageProgress(session: session)),
            ]).animate().fadeIn(),

            const Gap(16),

            // ── Pass cards ───────────────────────────────────────────────
            const _SectionLabel('CAPTURE STAGES'),
            const Gap(8),
            ...capturePassSequence.asMap().entries.map((e) {
              return _PassCard(
                pass: e.value,
                session: session,
                onEnterCamera: () => Navigator.of(context)
                    .push(MaterialPageRoute(
                      builder: (_) {
                        ref.read(activePassProvider.notifier).state = e.value;
                        return const CameraScreen();
                      },
                    )),
              ).animate(delay: (e.key * 80).ms).fadeIn().slideX(begin: 0.05, end: 0);
            }),

            const Gap(16),

            // ── Coverage zone table ──────────────────────────────────────
            const _SectionLabel('COVERAGE ZONES'),
            const Gap(8),
            _CoverageZoneTable(session: session).animate().fadeIn(delay: 400.ms),

            const Gap(24),

            // ── Export ───────────────────────────────────────────────────
            _ExportPanel(session: session),
            const Gap(16),
          ],
        ),
      ),
    );
  }
}

// ─── Coverage gauge ───────────────────────────────────────────────────────────

class _CoverageGauge extends StatelessWidget {
  final CaptureSession session;
  const _CoverageGauge({required this.session});

  @override
  Widget build(BuildContext context) => _Card(
        child: Column(children: [
          CircularPercentIndicator(
            radius: 46,
            lineWidth: 8,
            percent: (session.coverage.coveragePercent / 100).clamp(0.0, 1.0),
            center: Text(
              '${session.coverage.coveragePercent.toStringAsFixed(0)}%',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: session.coverage.meetsTarget
                      ? AppColors.success
                      : AppColors.warning),
            ),
            progressColor: session.coverage.meetsTarget
                ? AppColors.success
                : AppColors.warning,
            backgroundColor: AppColors.surfaceElevated,
          ),
          const Gap(6),
          const Text('Orbit Coverage',
              style:
                  TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          Text(
            session.coverage.meetsTarget ? '✓ Target met' : 'Target: 85%',
            style: TextStyle(
                fontSize: 10,
                color: session.coverage.meetsTarget
                    ? AppColors.success
                    : AppColors.textSecondary),
          ),
        ]),
      );
}

// ─── Stage progress ───────────────────────────────────────────────────────────

class _StageProgress extends StatelessWidget {
  final CaptureSession session;
  const _StageProgress({required this.session});

  @override
  Widget build(BuildContext context) {
    final done = [
      session.calibrationDone,
      session.orbitComplete,
      session.macroComplete,
      session.baseComplete,
      session.scaleComplete,
    ].where((v) => v).length;

    return _Card(
      child: Column(children: [
        CircularPercentIndicator(
          radius: 46,
          lineWidth: 8,
          percent: done / 5,
          center: Text('$done/5',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          progressColor: AppColors.primary,
          backgroundColor: AppColors.surfaceElevated,
        ),
        const Gap(6),
        const Text('Stages Done',
            style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        Text(
          done == 5 ? '✓ All complete' : '${5 - done} remaining',
          style: TextStyle(
              fontSize: 10,
              color:
                  done == 5 ? AppColors.success : AppColors.textSecondary),
        ),
      ]),
    );
  }
}

// ─── Pass card ────────────────────────────────────────────────────────────────

class _PassCard extends StatelessWidget {
  final CapturePass pass;
  final CaptureSession session;
  final VoidCallback onEnterCamera;

  const _PassCard(
      {required this.pass,
      required this.session,
      required this.onEnterCamera});

  bool _isComplete(CaptureSession s) {
    switch (pass) {
      case CapturePass.calibration: return s.calibrationDone;
      case CapturePass.orbit: return s.orbitComplete;
      case CapturePass.macro: return s.macroComplete;
      case CapturePass.base: return s.baseComplete;
      case CapturePass.scale: return s.scaleComplete;
    }
  }

  int _count(CaptureSession s) =>
      s.images.where((i) => i.pass == pass).length;

  @override
  Widget build(BuildContext context) {
    final cfg = passConfigs[pass]!;
    final complete = _isComplete(session);
    final count = _count(session);
    final progress = (count / cfg.targetMin).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: complete
              ? AppColors.success.withOpacity(0.4)
              : cfg.color.withOpacity(0.3),
        ),
      ),
      child: Row(children: [
        // Pass icon
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: cfg.color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            complete ? Icons.check_circle : cfg.icon,
            color: complete ? AppColors.success : cfg.color,
            size: 18,
          ),
        ),
        const Gap(10),

        // Pass info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cfg.title,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const Gap(4),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: AppColors.surfaceElevated,
                valueColor: AlwaysStoppedAnimation(
                    complete ? AppColors.success : cfg.color),
              ),
              const Gap(2),
              Text('$count / ${cfg.targetMin} min',
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textSecondary)),
            ],
          ),
        ),
        const Gap(10),

        // Shoot button
        GestureDetector(
          onTap: onEnterCamera,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: cfg.color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              complete ? 'ADD' : 'SHOOT',
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.black),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─── Coverage zone table ──────────────────────────────────────────────────────

class _CoverageZoneTable extends StatelessWidget {
  final CaptureSession session;
  const _CoverageZoneTable({required this.session});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: CoverageZone.values.map((zone) {
          final hits = session.coverage.zoneHits[zone] ?? 0;
          final status = CoverageEngine.zoneStatus(hits);
          final color = status == ZoneStatus.good
              ? AppColors.success
              : status == ZoneStatus.adequate
                  ? AppColors.warning
                  : AppColors.error;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const Gap(8),
              Expanded(
                child: Text(CoverageEngine.zoneLabel(zone),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textPrimary)),
              ),
              Text('$hits images',
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textSecondary)),
              const Gap(8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(status.name.toUpperCase(),
                    style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Export panel ─────────────────────────────────────────────────────────────

class _ExportPanel extends ConsumerWidget {
  final CaptureSession session;
  const _ExportPanel({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('EXPORT',
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2,
                  color: AppColors.textSecondary)),
          const Gap(12),
          Row(children: [
            Expanded(
              child: _ExportButton(
                label: 'PDF Report',
                icon: Icons.picture_as_pdf,
                color: AppColors.accent,
                onTap: () async {
                  await ref
                      .read(sessionProvider.notifier)
                      .completeSession();
                  final pdf = PdfReportService();
                  final path = await pdf.generate(
                      ref.read(sessionProvider)!);
                  await Share.shareXFiles([XFile(path)],
                      subject: 'Capture Report — ${session.pieceName}');
                },
              ),
            ),
            const Gap(8),
            Expanded(
              child: _ExportButton(
                label: 'COLMAP Ready',
                icon: Icons.folder_zip,
                color: AppColors.primary,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'Project folder ready at the path shown in metadata.json'),
                  ));
                },
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ExportButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Column(children: [
            Icon(icon, color: color, size: 22),
            const Gap(4),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ]),
        ),
      );
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            fontSize: 10,
            letterSpacing: 2,
            color: AppColors.textSecondary),
      );
}
