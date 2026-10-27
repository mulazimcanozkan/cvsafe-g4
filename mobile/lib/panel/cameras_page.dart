import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';
import 'zone_editor.dart';

/// Camera list with live / reference frames; add, edit, delete and open the zone editor.
class CamerasPage extends StatefulWidget {
  const CamerasPage({super.key});
  @override
  State<CamerasPage> createState() => _CamerasPageState();
}

class _CamerasPageState extends State<CamerasPage> {
  Timer? _tick;
  int _bust = 0;

  @override
  void initState() {
    super.initState();
    // refresh thumbnails every 3 s (live cameras show the latest annotated frame)
    _tick = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() => _bust++);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _edit({Camera? cam}) async {
    final st = AppScope.read(context);
    final subs = st.site?.subcontractors ?? const <Subcontractor>[];
    final id = TextEditingController(text: cam?.id ?? '');
    final name = TextEditingController(text: cam?.name ?? '');
    final source = TextEditingController(text: cam?.source ?? '');
    String? sub = cam?.subcontractorId;
    String? error;
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: C.panel,
          title: Text(cam == null ? 'Add camera' : 'Edit ${cam.id}', style: sans(size: 17, weight: FontWeight.w700)),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: id,
                enabled: cam == null,
                decoration: fieldDecoration('Camera ID', hint: 'CAM-05', icon: Icons.tag),
              ),
              const SizedBox(height: 10),
              TextField(controller: name, decoration: fieldDecoration('Name / location', hint: 'North gate', icon: Icons.place_outlined)),
              const SizedBox(height: 10),
              TextField(
                controller: source,
                decoration: fieldDecoration('Stream source (optional)',
                    hint: 'rtsp://user:pass@192.168.1.21:554/stream1  or a video file path', icon: Icons.link),
              ),
              const SizedBox(height: 10),
              InputDecorator(
                decoration: fieldDecoration('Subcontractor responsible', icon: Icons.handshake_outlined)
                    .copyWith(contentPadding: const EdgeInsets.fromLTRB(0, 4, 8, 4)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: subs.any((s) => s.id == sub) ? sub : null,
                    isExpanded: true,
                    dropdownColor: C.panel2,
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text('None', style: sans(size: 13.5))),
                      for (final s in subs) DropdownMenuItem<String?>(value: s.id, child: Text(s.name, style: sans(size: 13.5))),
                    ],
                    onChanged: (v) => setD(() => sub = v),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text('Leave the source empty if there is no stream yet: photos and videos can still be assigned to this camera.',
                  style: sans(size: 11.5, color: C.muted)),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, style: sans(size: 12.5, color: C.pink)),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setD(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await st.api.saveCamera(
                            id: id.text.trim(), name: name.text.trim(), source: source.text.trim(), subcontractor: sub);
                        await st.reloadSite();
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setD(() {
                          busy = false;
                          error = e.toString();
                        });
                      }
                    },
              child: Text('Save', style: sans(size: 14, color: C.orange, weight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(Camera cam) async {
    final st = AppScope.read(context);
    if (!await confirmDialog(context, 'Delete ${cam.id}?',
        'The camera and its zones are removed. Past incidents stay in the log.')) {
      return;
    }
    try {
      await st.api.deleteCamera(cam.id);
      await st.reloadSite();
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  void _zones(Camera cam) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ZoneEditorPage(camera: cam)));
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final isAdmin = st.user?.isAdmin ?? false;
    final cams = st.site?.cameras ?? const <Camera>[];
    return PanelPage(
      title: 'Cameras & Zones',
      subtitle: 'Connect site cameras and draw the danger zones each one watches',
      actions: [
        if (isAdmin) ActionButton(label: 'Add Camera', icon: Icons.add, primary: true, onPressed: () => _edit()),
      ],
      children: [
        if (cams.isEmpty)
          const EmptyState(icon: Icons.videocam_off_outlined, title: 'No cameras yet', text: 'Add the first camera to start.'),
        Wrap(spacing: 16, runSpacing: 16, children: [
          for (final c in cams)
            SizedBox(
              width: 360,
              child: Panel(
                padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Stack(children: [
                    NetImage(st.api.frameUrl(c.id, bust: c.live ? _bust : 0), height: 190),
                    Positioned(left: 8, top: 8, child: Pill(c.id, color: C.orange, filled: true, small: true)),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Pill(c.live ? 'LIVE · ${c.fps.toStringAsFixed(1)} FPS' : (c.hasReference ? 'REFERENCE PHOTO' : 'OFFLINE'),
                          color: c.live ? C.green : C.muted, small: true),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Text(c.name, style: sans(size: 15.5, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${c.subcontractor ?? 'No subcontractor'} · ${c.zones.length} zones · ${c.openViolations} open alerts',
                      style: mono(size: 10.5, color: C.muted)),
                  if (isAdmin && (c.source ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(c.source!.replaceAll(RegExp(r'//[^@/]*@'), '//***@'),
                        style: mono(size: 10, color: C.dim), overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: ActionButton(label: 'Zones', icon: Icons.draw_outlined, onPressed: () => _zones(c))),
                    if (isAdmin) ...[
                      const SizedBox(width: 6),
                      IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(cam: c)),
                      IconButton(
                          tooltip: 'Delete', icon: const Icon(Icons.delete_outline, color: C.pink), onPressed: () => _delete(c)),
                    ],
                  ]),
                ]),
              ),
            ),
        ]),
      ],
    );
  }
}
