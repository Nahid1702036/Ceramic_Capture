// lib/features/export/services/pdf_report_service.dart
//
// Generates reports/capture_checklist.pdf:
//   • Cover page: project ID, date, piece name, pass summary
//   • Stage checklist: calibration ✓, orbit ✓ (coverage%), macro ✓, base ✓, scale ✓
//   • Coverage map: zone hit table
//   • Detected features summary
//   • Quality flags breakdown (rejected frames per pass)
//   • Thumbnail grid for each pass (up to 12 per pass)

import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path/path.dart' as p;
import '../../../core/models/capture_models.dart';
import '../../../core/services/coverage_engine.dart';

class PdfReportService {
  static const PdfColor _primary = PdfColor.fromInt(0xFF1A1A2E);
  static const PdfColor _accent = PdfColor.fromInt(0xFFE94560);
  static const PdfColor _green = PdfColor.fromInt(0xFF2ECC71);
  static const PdfColor _red = PdfColor.fromInt(0xFFE74C3C);
  static const PdfColor _amber = PdfColor.fromInt(0xFFF39C12);
  static const PdfColor _lightGray = PdfColor.fromInt(0xFFF5F5F5);

  Future<String> generate(CaptureSession session) async {
    final pdf = pw.Document();

    // Load thumbnail bytes
    final thumbs = await _loadThumbnails(session);

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (context) => _header(context, session),
      footer: (context) => _footer(context),
      build: (context) => [
        _coverSection(session),
        pw.SizedBox(height: 16),
        _stageChecklist(session),
        pw.SizedBox(height: 16),
        _coverageTable(session),
        pw.SizedBox(height: 16),
        _featuresTable(session),
        pw.SizedBox(height: 16),
        _qualityBreakdown(session),
        if (thumbs.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          _thumbnailGrid(thumbs),
        ],
      ],
    ));

    final outPath = p.join(session.projectRoot, 'reports', 'capture_checklist.pdf');
    final file = File(outPath);
    await file.writeAsBytes(await pdf.save());
    return outPath;
  }

  // ─── Header / Footer ────────────────────────────────────────────────────────

  pw.Widget _header(pw.Context ctx, CaptureSession session) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
              bottom: pw.BorderSide(color: _accent, width: 2)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('CERAMIC CAPTURE',
                style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: _primary)),
            pw.Text(session.projectId,
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
          ],
        ),
      );

  pw.Widget _footer(pw.Context ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Stage 1 — Capture Checklist',
                style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
      );

  // ─── Cover section ───────────────────────────────────────────────────────────

  pw.Widget _coverSection(CaptureSession session) => pw.Container(
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          color: _primary,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('CAPTURE CHECKLIST REPORT',
                style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white)),
            pw.SizedBox(height: 8),
            _infoRow('Project ID', session.projectId, light: true),
            _infoRow('Piece Name', session.pieceName, light: true),
            _infoRow('Capture Date',
                session.captureDate.toIso8601String().substring(0, 10),
                light: true),
            _infoRow('Total Images', '${session.totalImages}', light: true),
            _infoRow('Coverage',
                '${session.coverage.coveragePercent.toStringAsFixed(1)}%',
                light: true),
            _infoRow('Status',
                session.sessionComplete ? 'COMPLETE' : 'INCOMPLETE',
                light: true),
          ],
        ),
      );

  pw.Widget _infoRow(String label, String value, {bool light = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [
          pw.SizedBox(width: 120,
              child: pw.Text('$label:',
                  style: pw.TextStyle(
                      fontSize: 9,
                      color: light ? PdfColors.grey400 : PdfColors.grey700))),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: light ? PdfColors.white : _primary)),
        ]),
      );

  // ─── Stage checklist ─────────────────────────────────────────────────────────

  pw.Widget _stageChecklist(CaptureSession session) {
    final stages = [
      ('Calibration Shot', session.calibrationDone, 'Empty rig, pre-piece'),
      ('Orbit Pass', session.orbitComplete,
          '${session.coverage.coveragePercent.toStringAsFixed(1)}% coverage (target ≥85%)'),
      ('Macro Pass', session.macroComplete,
          '${session.macroCount} close-ups captured'),
      ('Base / Foot Station', session.baseComplete,
          '${session.baseCount} base images (inverted piece)'),
      ('Scale Reference', session.scaleComplete,
          session.scaleReference ?? 'Not set'),
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Stage Checklist'),
        pw.Table(
          columnWidths: {
            0: const pw.FlexColumnWidth(2),
            1: const pw.FlexColumnWidth(0.5),
            2: const pw.FlexColumnWidth(3),
          },
          children: [
            _tableHeader(['Stage', 'Status', 'Notes']),
            ...stages.map((s) => pw.TableRow(
                  decoration: pw.BoxDecoration(
                      color: stages.indexOf(s).isEven
                          ? _lightGray
                          : PdfColors.white),
                  children: [
                    _tableCell(s.$1),
                    _tableCellCentered(
                      s.$2 ? '✓' : '✗',
                      color: s.$2 ? _green : _red,
                      bold: true,
                    ),
                    _tableCell(s.$3),
                  ],
                )),
          ],
        ),
      ],
    );
  }

  // ─── Coverage table ──────────────────────────────────────────────────────────

  pw.Widget _coverageTable(CaptureSession session) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionTitle('Angular Coverage by Zone'),
          pw.Table(
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1.5),
            },
            children: [
              _tableHeader(['Zone', 'Images', 'Status']),
              ...CoverageZone.values.map((zone) {
                final hits = session.coverage.zoneHits[zone] ?? 0;
                final status = CoverageEngine.zoneStatus(hits);
                final color = status == ZoneStatus.good
                    ? _green
                    : status == ZoneStatus.adequate
                        ? _amber
                        : _red;
                final idx = CoverageZone.values.indexOf(zone);
                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                      color: idx.isEven ? _lightGray : PdfColors.white),
                  children: [
                    _tableCell(CoverageEngine.zoneLabel(zone)),
                    _tableCellCentered('$hits'),
                    _tableCellCentered(
                      status.name.toUpperCase(),
                      color: color,
                      bold: true,
                    ),
                  ],
                );
              }),
            ],
          ),
        ],
      );

  // ─── Detected features ───────────────────────────────────────────────────────

  pw.Widget _featuresTable(CaptureSession session) {
    final counts = <YoloClass, int>{};
    for (final img in session.images) {
      for (final d in img.analysis.detections) {
        counts[d.cls] = (counts[d.cls] ?? 0) + 1;
      }
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Detected Features (YOLO)'),
        pw.Table(
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(1),
          },
          children: [
            _tableHeader(['Feature Class', 'Detections']),
            ...YoloClass.values.asMap().entries.map((e) {
              final count = counts[e.value] ?? 0;
              return pw.TableRow(
                decoration: pw.BoxDecoration(
                    color: e.key.isEven ? _lightGray : PdfColors.white),
                children: [
                  _tableCell(_yoloLabel(e.value)),
                  _tableCellCentered('$count',
                      color: count > 0 ? _green : PdfColors.grey600),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  // ─── Quality breakdown ───────────────────────────────────────────────────────

  pw.Widget _qualityBreakdown(CaptureSession session) {
    final rows = <List<String>>[];
    for (final pass in CapturePass.values) {
      final imgs = session.images.where((i) => i.pass == pass).toList();
      if (imgs.isEmpty) continue;
      final rejected = imgs.where((i) => !i.analysis.isAcceptable).length;
      rows.add([
        pass.name.toUpperCase(),
        '${imgs.length}',
        '${imgs.length - rejected}',
        '$rejected',
      ]);
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Quality Summary'),
        pw.Table(
          columnWidths: {
            0: const pw.FlexColumnWidth(2),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(1),
          },
          children: [
            _tableHeader(['Pass', 'Total', 'Accepted', 'Rejected']),
            ...rows.asMap().entries.map((e) => pw.TableRow(
                  decoration: pw.BoxDecoration(
                      color: e.key.isEven ? _lightGray : PdfColors.white),
                  children: e.value
                      .asMap()
                      .entries
                      .map((c) => c.key == 3 && c.value != '0'
                          ? _tableCellCentered(c.value, color: _red)
                          : _tableCellCentered(c.value))
                      .toList(),
                )),
          ],
        ),
      ],
    );
  }

  // ─── Thumbnail grid ──────────────────────────────────────────────────────────

  pw.Widget _thumbnailGrid(Map<CapturePass, List<Uint8List>> thumbs) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionTitle('Thumbnails'),
          ...thumbs.entries.map((entry) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(entry.key.name.toUpperCase(),
                      style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700)),
                  pw.SizedBox(height: 4),
                  pw.Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: entry.value
                        .take(12)
                        .map((bytes) => pw.Container(
                              width: 60,
                              height: 60,
                              child: pw.Image(pw.MemoryImage(bytes)),
                            ))
                        .toList(),
                  ),
                  pw.SizedBox(height: 8),
                ],
              )),
        ],
      );

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  pw.Widget _sectionTitle(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(title,
            style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: _primary)),
      );

  pw.TableRow _tableHeader(List<String> headers) => pw.TableRow(
        decoration: const pw.BoxDecoration(color: _primary),
        children: headers
            .map((h) => pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(h,
                      style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white)),
                ))
            .toList(),
      );

  pw.Widget _tableCell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(text, style: const pw.TextStyle(fontSize: 8)),
      );

  pw.Widget _tableCellCentered(String text,
          {PdfColor? color, bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(text,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
                fontSize: 8,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: color)),
      );

  String _yoloLabel(YoloClass cls) {
    switch (cls) {
      case YoloClass.ceramicObject: return 'Ceramic Object';
      case YoloClass.makerMark: return 'Maker Mark';
      case YoloClass.signature: return 'Signature';
      case YoloClass.stamp: return 'Stamp';
      case YoloClass.footRing: return 'Foot Ring';
      case YoloClass.scaleMarker: return 'Scale Marker';
    }
  }

  Future<Map<CapturePass, List<Uint8List>>> _loadThumbnails(
      CaptureSession session) async {
    final result = <CapturePass, List<Uint8List>>{};
    for (final pass in CapturePass.values) {
      final imgs = session.images
          .where((i) => i.pass == pass && i.analysis.isAcceptable)
          .take(12)
          .toList();
      if (imgs.isEmpty) continue;
      final thumbBytes = <Uint8List>[];
      for (final img in imgs) {
        try {
          final file = File(img.filePath);
          if (await file.exists()) {
            thumbBytes.add(await file.readAsBytes());
          }
        } catch (_) {}
      }
      if (thumbBytes.isNotEmpty) result[pass] = thumbBytes;
    }
    return result;
  }
}
