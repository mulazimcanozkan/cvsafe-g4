import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// AI Scan: analyse a photo or video taken in the field with the same models
/// that watch the site cameras. Violations can be turned into alerts.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _picker = ImagePicker();
  String? cameraId; // assign the scan to a camera -> its zones and subcontractor apply
  bool createAlerts = true;

  // progress
  String? stage; // uploading | analysing
  double? progress;
  String? error;
  Uint8List? preview;

  // results
  ImageScanResult? imageResult;
  VideoScanResult? videoResult;
  bool showRaw = false;

  bool get busy => stage != null;

  void _reset() {
    setState(() {
      error = null;
      imageResult = null;
      videoResult = null;
      preview = null;
      showRaw = false;
      progress = null;
    });
  }

  Future<void> _pickImage(ImageSource src) async {
    final st = AppScope.read(context);
    if (!st.online) {
      toast(context, 'AI Scan needs the server. Set its address from the avatar menu.', error: true);
      return;
    }
    XFile? f;
    try {
      f = await _picker.pickImage(source: src, maxWidth: 1920, maxHeight: 1920, imageQuality: 90);
    } catch (e) {
      if (mounted) toast(context, 'Could not open ${src == ImageSource.camera ? 'camera' : 'gallery'}: $e', error: true);
      return;
    }
    if (f == null) return;
    _reset();
    final bytes = await f.readAsBytes();
    setState(() {
      preview = bytes;
      stage = 'analysing';
    });
    try {
      final r = await st.api.analyzeImage(bytes, f.name.isEmpty ? 'photo.jpg' : f.name,
          cameraId: cameraId, createIncidents: createAlerts);
      if (!mounted) return;
      setState(() => imageResult = r);
      st.addIncidentsFromScan(r.incidentIds);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => stage = null);
    }
  }

  Future<void> _pickVideo(ImageSource src) async {
    final st = AppScope.read(context);
    if (!st.online) {
      toast(context, 'AI Scan needs the server. Set its address from the avatar menu.', error: true);
      return;
    }
    XFile? f;
    try {
      f = await _picker.pickVideo(source: src, maxDuration: const Duration(minutes: 3));
    } catch (e) {
      if (mounted) toast(context, 'Could not open video source: $e', error: true);
      return;
    }
    if (f == null) return;
    _reset();
    setState(() => stage = 'uploading');
    try {
      final name = f.name.isEmpty ? 'clip.mp4' : f.name;
      var job = kIsWeb
          ? await st.api.analyzeVideo(bytes: await f.readAsBytes(), filename: name, cameraId: cameraId, createIncidents: createAlerts)
          : await st.api.analyzeVideo(path: f.path, filename: name, cameraId: cameraId, createIncidents: createAlerts);
      if (!mounted) return;
      setState(() {
        stage = 'analysing';
        progress = 0;
      });
      while (job.status == 'queued' || job.status == 'running') {
        await Future<void>.delayed(const Duration(seconds: 1));
        job = await st.api.job(job.id);
        if (!mounted) return;
        setState(() => progress = job.progress);
      }
      if (job.status == 'error' || job.result == null) throw Exception(job.error ?? 'Video analysis failed');
      final r = job.result!;
      setState(() => videoResult = r);
      st.addIncidentsFromScan(r.incidents.where((i) => i.incidentId != null).map((i) => i.incidentId!).toList());
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => stage = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final cams = st.site?.cameras ?? const <Camera>[];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      const OfflineBanner(),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.document_scanner_outlined, color: C.orange),
            const SizedBox(width: 8),
            Expanded(child: Text('AI Photo & Video Analysis', style: sans(size: 17, weight: FontWeight.w700))),
          ]),
          const SizedBox(height: 6),
          Text(
              'Detects workers, hard hats, hi-vis vests, danger-zone entry, possible falls and machinery proximity. '
              'Faces are blurred before anything is stored (KVKK).',
              style: sans(size: 12.5, color: C.muted, height: 1.4)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _source(Icons.photo_camera_outlined, 'Take Photo', () => _pickImage(ImageSource.camera))),
            const SizedBox(width: 8),
            Expanded(child: _source(Icons.photo_library_outlined, 'Photo from Gallery', () => _pickImage(ImageSource.gallery))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _source(Icons.videocam_outlined, 'Record Video', () => _pickVideo(ImageSource.camera))),
            const SizedBox(width: 8),
            Expanded(child: _source(Icons.video_library_outlined, 'Video from Gallery', () => _pickVideo(ImageSource.gallery))),
          ]),
          const SizedBox(height: 14),
          Text('ASSIGN TO CAMERA / ZONE', style: mono(size: 10.5, color: C.muted, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: C.panel2, borderRadius: BorderRadius.circular(10)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: cams.any((c) => c.id == cameraId) ? cameraId : null,
                isExpanded: true,
                dropdownColor: C.panel2,
                style: mono(size: 12.5),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text('None (no zone rules)', style: mono(size: 12.5))),
                  for (final c in cams)
                    DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text('${c.id} · ${c.name}${c.zones.isEmpty ? '' : ' (${c.zones.length} zone)'}',
                          overflow: TextOverflow.ellipsis, style: mono(size: 12.5)),
                    ),
                ],
                onChanged: busy ? null : (v) => setState(() => cameraId = v),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: createAlerts,
            activeColor: C.orange,
            onChanged: busy ? null : (v) => setState(() => createAlerts = v),
            title: Text('Create alerts for violations', style: sans(size: 13.5)),
            subtitle: Text('Off = analyse only, nothing is logged', style: sans(size: 11.5, color: C.muted)),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      if (busy) _progressCard(),
      if (error != null)
        Panel(
          color: alpha(C.red, 0.1),
          borderColor: alpha(C.red, 0.5),
          child: Row(children: [
            const Icon(Icons.error_outline, color: C.red),
            const SizedBox(width: 10),
            Expanded(child: Text(error!, style: sans(size: 13, color: C.pink))),
          ]),
        ),
      if (imageResult != null) ..._imageResult(imageResult!),
      if (videoResult != null) ..._videoResult(videoResult!),
    ]);
  }

  Widget _source(IconData icon, String label, VoidCallback onTap) => Material(
        color: C.panel2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: busy ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
            child: Column(children: [
              Icon(icon, color: busy ? C.dim : C.orange, size: 26),
              const SizedBox(height: 6),
              Text(label, textAlign: TextAlign.center, style: mono(size: 11.5, weight: FontWeight.w700)),
            ]),
          ),
        ),
      );

  Widget _progressCard() => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (preview != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(preview!, height: 180, width: double.infinity, fit: BoxFit.cover),
              ),
              const SizedBox(height: 12),
            ],
            Row(children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  stage == 'uploading'
                      ? 'Uploading video...'
                      : progress == null
                          ? 'Running YOLO detection...'
                          : 'Analysing frames · ${(progress! * 100).round()}%',
                  style: mono(size: 12.5, weight: FontWeight.w600),
                ),
              ),
            ]),
            if (progress != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: progress, minHeight: 7, backgroundColor: C.panel2),
              ),
            ],
          ]),
        ),
      );

  Widget _stat(String label, String value, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: C.panel2, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: mono(size: 9.5, color: C.muted, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(value, style: mono(size: 18, color: color, weight: FontWeight.w800)),
          ]),
        ),
      );

  Widget _modeNote(String mode) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          mode == 'ppe-model'
              ? 'Model: YOLO pose + trained PPE detector.'
              : 'Model: YOLO pose + colour baseline for PPE. Accuracy improves once the trained PPE model is installed on the server.',
          style: sans(size: 11.5, color: C.muted, height: 1.35),
        ),
      );

  List<Widget> _violationPills(List<ViolationCount> v) => [
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (v.isEmpty) Pill('NO VIOLATIONS', color: C.green, icon: Icons.verified_outlined),
          for (final x in v) Pill('${x.title} ×${x.count}', color: severityColor(x.severity), icon: Icons.warning_amber_rounded),
        ]),
      ];

  List<Widget> _imageResult(ImageScanResult r) {
    final st = AppScope.read(context);
    return [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle('Scan Result', icon: Icons.insights,
              trailing: Pill('${r.latencyMs.round()} ms', color: C.blue, small: true)),
          GestureDetector(
            onTap: () => setState(() => showRaw = !showRaw),
            child: Stack(children: [
              NetImage(st.api.url(showRaw ? r.rawUrl : r.imageUrl), height: 280, fit: BoxFit.contain),
              Positioned(
                right: 8,
                bottom: 8,
                child: Pill(showRaw ? 'RAW · TAP FOR OVERLAY' : 'OVERLAY · TAP FOR RAW', color: C.text, small: true),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            _stat('WORKERS', '${r.persons.length}', C.text),
            const SizedBox(width: 8),
            _stat('COMPLIANT', '${r.compliant}', C.green),
            const SizedBox(width: 8),
            _stat('IN VIOLATION', '${r.persons.length - r.compliant}', r.persons.length - r.compliant > 0 ? C.red : C.green),
          ]),
          ..._violationPills(r.violations),
          if (r.vehicles.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Machinery detected: ${r.vehicles.join(', ')}', style: sans(size: 12, color: C.yellow)),
          ],
          _modeNote(r.mode),
        ]),
      ),
      const SizedBox(height: 12),
      if (r.persons.isNotEmpty)
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PER-WORKER CHECK', style: mono(size: 12, weight: FontWeight.w700, color: C.blue)),
            const SizedBox(height: 10),
            for (final p in r.persons) _personRow(p),
          ]),
        ),
      if (r.incidentIds.isNotEmpty) ...[
        const SizedBox(height: 12),
        BigButton(
          label: 'Open ${r.incidentIds.length} alert${r.incidentIds.length > 1 ? 's' : ''} in Evidence',
          icon: Icons.open_in_new,
          onPressed: () => st.openEvidence(r.incidentIds.first),
        ),
      ],
    ];
  }

  Widget _personRow(PersonResult p) {
    Widget item(String key, String label) {
      final s = p.ppe[key];
      if (s == null || s.state == null) {
        return Pill('$label ?', color: C.dim, small: true);
      }
      return Pill('${s.state! ? '✓' : '✗'} $label ${(s.conf * 100).round()}%',
          color: s.state! ? C.green : C.red, small: true);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: C.panel2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.violations.isEmpty ? alpha(C.green, 0.3) : alpha(C.red, 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('[W-${p.id}]', style: mono(size: 12.5, weight: FontWeight.w800)),
          const SizedBox(width: 8),
          Text(p.violations.isEmpty ? 'PASS' : 'VIOLATION',
              style: mono(size: 11.5, weight: FontWeight.w700, color: p.violations.isEmpty ? C.green : C.red)),
          const Spacer(),
          Text('person ${(p.conf * 100).round()}%', style: mono(size: 10.5, color: C.muted)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          item('hardhat', 'HARD HAT'),
          item('vest', 'VEST'),
          item('harness', 'HARNESS'),
          for (final z in p.zones) Pill('ZONE: $z', color: C.orange, small: true),
          for (final v in p.violations.where((v) => !{'no_hardhat', 'no_vest'}.contains(v)))
            Pill(violationLabels[v] ?? v, color: C.red, small: true),
        ]),
      ]),
    );
  }

  List<Widget> _videoResult(VideoScanResult r) {
    final st = AppScope.read(context);
    final compliance = r.personsTracked == 0 ? 100 : (100 * r.personsCompliant / r.personsTracked).round();
    return [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle('Video Result', icon: Icons.movie_filter_outlined,
              trailing: Pill('${r.framesAnalyzed} frames', color: C.blue, small: true)),
          Text(
              'Analysed ${r.analyzedS.toStringAsFixed(1)}s of ${r.durationS.toStringAsFixed(1)}s · '
              '${r.sampleFps.toStringAsFixed(1)} fps sampling · ${r.latencyMs.round()} ms/frame',
              style: mono(size: 11, color: C.muted)),
          const SizedBox(height: 12),
          Row(children: [
            _stat('WORKERS TRACKED', '${r.personsTracked}', C.text),
            const SizedBox(width: 8),
            _stat('COMPLIANT', '$compliance%', compliance >= 90 ? C.green : (compliance >= 75 ? C.yellow : C.red)),
            const SizedBox(width: 8),
            _stat('INCIDENTS', '${r.incidents.length}', r.incidents.isEmpty ? C.green : C.red),
          ]),
          ..._violationPills(r.violations),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('A violation is reported only if it persists on the same tracked worker for several frames.',
                style: sans(size: 11.5, color: C.muted)),
          ),
          _modeNote(r.mode),
        ]),
      ),
      const SizedBox(height: 12),
      for (final i in r.incidents)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: C.panel,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: i.incidentId == null ? null : () => st.openEvidence(i.incidentId!),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14), border: Border.all(color: alpha(severityColor(i.severity), 0.5))),
                child: Row(children: [
                  SizedBox(width: 110, child: NetImage(st.api.url(i.imageUrl), height: 80)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('at ${_fmtOffset(i.tOffset)} · Worker #W-${i.trackId}',
                          style: mono(size: 10.5, color: C.blue, weight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(i.title, style: sans(size: 14, weight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Pill(i.severity.toUpperCase(), color: severityColor(i.severity), small: true),
                    ]),
                  ),
                  if (i.incidentId != null) const Icon(Icons.chevron_right, color: C.muted),
                ]),
              ),
            ),
          ),
        ),
    ];
  }

  String _fmtOffset(double s) {
    final m = s ~/ 60;
    final sec = (s - m * 60).floor();
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}
