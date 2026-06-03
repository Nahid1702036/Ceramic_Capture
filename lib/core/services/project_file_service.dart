// lib/core/services/project_file_service.dart
//
// Creates and manages the on-device project folder structure:
//
//   project_001/
//   ├── images/
//   │   ├── orbit/
//   │   ├── macro/
//   │   ├── base/
//   │   ├── scale/
//   │   └── calibration/
//   ├── metadata/
//   │   ├── metadata.json
//   │   └── capture_report.json
//   ├── colmap/
//   │   ├── images/        (symlinked copies for COLMAP)
//   │   └── project.ini
//   └── reports/
//       └── capture_checklist.pdf  (written by PdfReportService)

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../models/capture_models.dart';

class ProjectFileService {
  static const _uuid = Uuid();

  // ─── Create new project directory ──────────────────────────────────────────

  Future<String> createProjectRoot(String pieceName) async {
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final slug = pieceName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+$'), '');
    final root = p.join(base.path, 'CeramicCapture', '${slug}_$date');

    await _mkdirs(root);
    return root;
  }

  Future<void> _mkdirs(String root) async {
    final dirs = [
      p.join(root, 'images', 'orbit'),
      p.join(root, 'images', 'macro'),
      p.join(root, 'images', 'base'),
      p.join(root, 'images', 'scale'),
      p.join(root, 'images', 'calibration'),
      p.join(root, 'metadata'),
      p.join(root, 'colmap', 'images'),
      p.join(root, 'reports'),
    ];
    for (final dir in dirs) {
      await Directory(dir).create(recursive: true);
    }
  }

  // ─── Save a captured frame ──────────────────────────────────────────────────

  Future<({String imagePath, String colmapPath})> saveImage({
    required String projectRoot,
    required Uint8List bytes,
    required CapturePass pass,
    required int frameIndex,
  }) async {
    final passName = pass.name; // 'orbit', 'macro', etc.
    final filename = '${passName}_${frameIndex.toString().padLeft(4, '0')}.jpg';

    final imagePath = p.join(projectRoot, 'images', passName, filename);
    await File(imagePath).writeAsBytes(bytes);

    // Copy into colmap/images/ with pass prefix for easy filtering
    final colmapFilename = '${passName}_$filename';
    final colmapPath = p.join(projectRoot, 'colmap', 'images', colmapFilename);
    await File(colmapPath).writeAsBytes(bytes);

    return (imagePath: imagePath, colmapPath: colmapFilename);
  }

  // ─── Write metadata.json ────────────────────────────────────────────────────

  Future<void> writeMetadata(
      String projectRoot, CaptureSession session) async {
    final file = File(p.join(projectRoot, 'metadata', 'metadata.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(session.toMetadataJson()),
    );
  }

  // ─── Write capture_report.json (full session) ───────────────────────────────

  Future<void> writeCaptureReport(
      String projectRoot, CaptureSession session) async {
    final file = File(p.join(projectRoot, 'metadata', 'capture_report.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_buildReport(session)),
    );
  }

  Map<String, dynamic> _buildReport(CaptureSession session) {
    final passStats = <String, dynamic>{};
    for (final pass in CapturePass.values) {
      final imgs = session.images.where((i) => i.pass == pass).toList();
      final rejected = imgs.where((i) => !i.analysis.isAcceptable).length;
      passStats[pass.name] = {
        'total': imgs.length,
        'accepted': imgs.length - rejected,
        'rejected': rejected,
      };
    }

    final featureCounts = <String, int>{};
    for (final img in session.images) {
      for (final d in img.analysis.detections) {
        final key = d.cls.name;
        featureCounts[key] = (featureCounts[key] ?? 0) + 1;
      }
    }

    return {
      'project_id': session.projectId,
      'piece_name': session.pieceName,
      'capture_date': session.captureDate.toIso8601String(),
      'session_complete': session.sessionComplete,
      'stage_summary': {
        'calibration_done': session.calibrationDone,
        'orbit_complete': session.orbitComplete,
        'macro_complete': session.macroComplete,
        'base_complete': session.baseComplete,
        'scale_complete': session.scaleComplete,
      },
      'pass_stats': passStats,
      'coverage': {
        'percent': session.coverage.coveragePercent,
        'meets_target': session.coverage.meetsTarget,
        'zone_hits': session.coverage.zoneHits.map(
          (k, v) => MapEntry(k.name, v),
        ),
      },
      'detected_features': featureCounts,
      'scale': {
        'reference': session.scaleReference,
        'mm_per_pixel': session.estimatedMmPerPixel,
      },
      'images': session.images.map((i) => {
            'id': i.id,
            'pass': i.pass.name,
            'file': i.colmapPath,
            'captured_at': i.capturedAt.toIso8601String(),
            'quality': i.analysis.qualityFlags.map((f) => f.name).toList(),
            'zone': i.zone?.name,
            'imu_azimuth': i.imuAzimuth,
            'imu_elevation': i.imuElevation,
            // Kalman physics scalars — consumed by FAPE reconstruction
            if (i.physics != null) 'physics': {
              'rho_fil':     i.physics!.rhoFil,
              'k_mu':        i.physics!.kMu,
              'sigma2_k':    i.physics!.sigma2K,
              'trs':         i.physics!.trs,
              'frame_valid': i.physics!.frameValid,
            },
          }).toList(),
    };
  }

  // ─── Write COLMAP project.ini ───────────────────────────────────────────────

  Future<void> writeColmapProjectIni(String projectRoot) async {
    final ini = '''
[General]
database_path=database.db
image_path=images

[Feature]
# Extracted with SIFT defaults — adjust if needed
max_image_size=3200

[Matcher]
# Sequential matcher works well for orbit sequences
matcher=sequential
overlap=10

[Mapper]
# Scale-aware reconstruction
ba_global_use_pba=false
''';
    final file = File(p.join(projectRoot, 'colmap', 'project.ini'));
    await file.writeAsString(ini);
  }

  // ─── Load existing session ──────────────────────────────────────────────────

  Future<CaptureSession?> loadSession(String projectRoot) async {
    try {
      final file = File(p.join(projectRoot, 'metadata', 'capture_report.json'));
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return CaptureSession.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  // ─── List all sessions ──────────────────────────────────────────────────────

  Future<List<String>> listProjectRoots() async {
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final root = Directory(p.join(base.path, 'CeramicCapture'));
    if (!await root.exists()) return [];
    final dirs = await root
        .list()
        .where((e) => e is Directory)
        .map((e) => e.path)
        .toList();
    return dirs;
  }
}
