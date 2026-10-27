import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Live CCTV: the latest AI-annotated frame from each camera (refreshed every
/// second) and a read-only view of its geofence zones. Zones are edited on the web portal.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});
  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  bool grid = false;
  Timer? _tick;
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _frame++);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _siren(Camera cam) async {
    final st = AppScope.read(context);
    Incident? target;
    for (final i in st.openIncidents) {
      if (i.cameraId == cam.id) {
        target = i;
        break;
      }
    }
    if (target == null) {
      toast(context, 'No open violation on ${cam.id} to attach the siren to.', error: true);
      return;
    }
    final err = await st.fieldAction(target, 'siren');
    if (mounted) toast(context, err ?? 'Siren triggered for ${cam.name}', error: err != null);
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final cams = st.site?.cameras ?? const <Camera>[];
    if (cams.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: const [
        OfflineBanner(),
        EmptyState(icon: Icons.videocam_off_outlined, title: 'No cameras configured', text: 'Cameras are added on the web portal.'),
      ]);
    }
    final selected = cams.firstWhere((c) => c.id == st.selectedCameraId, orElse: () => cams.first);
    final h = st.health;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      const OfflineBanner(),
      Panel(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Dot(color: (h?.streamsActive ?? 0) > 0 ? C.green : C.dim),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${h?.streamsActive ?? 0}/${cams.length} RTSP STREAMS ACTIVE',
                  style: mono(size: 11.5, color: C.green, weight: FontWeight.w700)),
            ),
            Pill('${cams.fold<int>(0, (n, c) => n + c.zones.length)} GEOFENCES ARMED', color: C.muted, icon: Icons.shield_outlined, small: true),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _metric('AI LATENCY', '${(h?.latencyMs ?? 0).round()} ms')),
            const SizedBox(width: 8),
            Expanded(child: _metric('AGG FPS', '${(h?.aggFps ?? 0).toStringAsFixed(1)} FPS')),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _modeBtn(Icons.center_focus_strong_outlined, 'Focused Feed', !grid, () => setState(() => grid = false))),
        const SizedBox(width: 8),
        Expanded(child: _modeBtn(Icons.grid_view, 'Multi-Grid (2x2)', grid, () => setState(() => grid = true))),
      ]),
      const SizedBox(height: 12),
      if (grid)
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.15,
          children: [
            for (final c in cams.take(4))
              GestureDetector(
                onTap: () {
                  st.selectedCameraId = c.id;
                  setState(() => grid = false);
                },
                child: _thumb(c, st, height: 110),
              ),
          ],
        )
      else ...[
        SizedBox(
          height: 36,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final c in cams)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: c.id == selected.id,
                  onSelected: (_) => setState(() => st.selectedCameraId = c.id),
                  showCheckmark: false,
                  label: Text(c.zones.isNotEmpty ? c.zones.first.name : c.name,
                      style: mono(size: 11.5, weight: FontWeight.w700, color: c.id == selected.id ? Colors.white : C.text)),
                  selectedColor: C.orange,
                  backgroundColor: C.panel,
                  side: BorderSide(color: c.id == selected.id ? C.orange : C.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        Panel(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              _feed(selected, st, 230),
              Positioned(
                left: 8,
                top: 8,
                child: Pill(selected.live ? '● LIVE · ${selected.id}' : '○ OFFLINE · ${selected.id}',
                    color: selected.live ? C.red : C.dim, small: true),
              ),
              if (selected.live)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Pill('${selected.fps.toStringAsFixed(1)} FPS · ${selected.persons} PERSONS', color: C.green, small: true),
                ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('TARGET ANCHOR', style: mono(size: 10, color: C.muted, weight: FontWeight.w700)),
                  Text(selected.name, style: sans(size: 17, weight: FontWeight.w600)),
                  if (selected.subcontractor != null) Text(selected.subcontractor!, style: mono(size: 10.5, color: C.muted)),
                ]),
              ),
              SizedBox(
                width: 130,
                child: BigButton(
                  label: 'Sound Siren',
                  icon: Icons.volume_up_outlined,
                  color: C.red,
                  onPressed: selected.openViolations > 0 || st.openIncidents.any((i) => i.cameraId == selected.id)
                      ? () => _siren(selected)
                      : null,
                ),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: Text('FEED SWITCHER (${cams.length - 1} OTHER STREAMS)',
                style: mono(size: 11.5, weight: FontWeight.w700)),
          ),
          Text('Swipe or select', style: mono(size: 10.5, color: C.blue)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 170,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final c in cams.where((c) => c.id != selected.id))
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: () => setState(() => st.selectedCameraId = c.id),
                  child: SizedBox(width: 200, child: _thumb(c, st, height: 110)),
                ),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 14),
      _zonesPanel(selected),
    ]);
  }

  Widget _metric(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: C.panel2, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Expanded(child: Text(label, style: mono(size: 10.5, color: C.muted))),
          Text(value, style: mono(size: 12, color: C.green, weight: FontWeight.w700)),
        ]),
      );

  Widget _modeBtn(IconData icon, String label, bool active, VoidCallback onTap) => Material(
        color: active ? C.orange : C.panel,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: 46,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12), border: Border.all(color: active ? C.orange : C.border)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 18, color: active ? Colors.white : C.muted),
              const SizedBox(width: 6),
              Text(label, style: mono(size: 12, weight: FontWeight.w700, color: active ? Colors.white : C.text)),
            ]),
          ),
        ),
      );

  /// Latest frame from the server, or the newest evidence image when the stream is offline.
  Widget _feed(Camera c, AppState st, double height) {
    if (st.online && c.live) {
      // a changing URL forces a reload each second; gaplessPlayback avoids flicker
      final url = '${st.api.snapshotUrl(c.id)}&f=$_frame';
      return NetImage(url, height: height);
    }
    String? last;
    for (final i in st.incidents) {
      if (i.cameraId == c.id && i.imageUrl != null) {
        last = st.api.url(i.imageUrl!);
        break;
      }
    }
    return Stack(children: [
      NetImage(last, height: height),
      Positioned.fill(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Pill(last == null ? 'STREAM OFFLINE' : 'STREAM OFFLINE · LAST EVIDENCE', color: C.muted, small: true),
          ),
        ),
      ),
    ]);
  }

  Widget _thumb(Camera c, AppState st, {required double height}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(children: [
          _feed(c, st, height),
          Positioned(left: 6, top: 6, child: Pill(c.id, color: C.orange, filled: true, small: true)),
          if (c.live)
            Positioned(right: 6, bottom: 6, child: Pill('${c.persons} Workers', color: C.text, small: true)),
        ]),
        const SizedBox(height: 6),
        Text(c.name, style: sans(size: 13.5, weight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
        Row(children: [
          Dot(color: c.openViolations > 0 ? C.orange : C.green, size: 7),
          const SizedBox(width: 5),
          Text(c.openViolations > 0 ? '${c.openViolations} Open Violations' : 'Normal · 0 Violations',
              style: mono(size: 10, color: c.openViolations > 0 ? C.orange : C.green)),
        ]),
      ]);

  Widget _zonesPanel(Camera cam) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.shield_outlined, color: C.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Virtual Geofence Zones (${cam.zones.length})', style: sans(size: 16, weight: FontWeight.w700)),
            ),
            Pill('SYNCED', color: C.green, small: true),
          ]),
          const SizedBox(height: 10),
          if (cam.zones.isEmpty) Text('No zones defined for ${cam.id}.', style: sans(size: 13, color: C.muted)),
          for (final z in cam.zones)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.panel2, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: alpha(z.type == 'restricted' ? C.red : C.blue, 0.18), borderRadius: BorderRadius.circular(8)),
                  child: Icon(z.type == 'restricted' ? Icons.warning_amber_rounded : Icons.height,
                      color: z.type == 'restricted' ? C.red : C.blue, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(z.name, style: mono(size: 12.5, weight: FontWeight.w700)),
                    Text(z.type == 'restricted' ? 'Restricted · any entry raises an alert' : 'Work at height · harness required',
                        style: sans(size: 12, color: C.muted)),
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.laptop_mac, size: 15, color: C.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Drawing and calibrating zones is done on the web portal.',
                  style: sans(size: 12, color: C.muted)),
            ),
          ]),
        ]),
      );
}
