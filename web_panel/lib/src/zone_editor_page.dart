import 'package:cvsafe_core/cvsafe_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'common.dart';
import 'state.dart';

/// Draw and adjust danger zones on a camera view by clicking or dragging polygon corners.
/// Coordinates are stored normalised (0..1), so they work at any camera resolution.
class ZoneEditorPage extends ConsumerStatefulWidget {
  const ZoneEditorPage({super.key, required this.camera});
  final Camera camera;
  @override
  ConsumerState<ZoneEditorPage> createState() => _ZoneEditorPageState();
}

class _ZoneEditorPageState extends ConsumerState<ZoneEditorPage> {
  late List<Zone> zones;
  List<List<double>>? drawing; // corners of the zone being drawn
  int? selected;
  int? _draggingVertex; // corner index being dragged on the selected zone
  bool dirty = false;
  bool saving = false;

  int _bust = DateTime.now().millisecondsSinceEpoch;
  double _aspect = 16 / 9;
  bool _imageOk = false;
  bool _imageLoading = true;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    zones = widget.camera.zones.map((z) => z.copyWith()).toList();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stream == null) _resolveImage();
  }

  String get _url => ref.read(panelControllerProvider).api.frameUrl(widget.camera.id, bust: _bust);

  void _resolveImage() {
    if (_stream != null && _listener != null) _stream!.removeListener(_listener!);
    if (!ref.read(pollEnabledProvider)) {
      setState(() {
        _imageOk = false;
        _imageLoading = false;
      });
      return;
    }
    setState(() => _imageLoading = true);
    final stream = NetworkImage(_url).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() {
        _aspect = info.image.width / info.image.height;
        _imageOk = true;
        _imageLoading = false;
      });
    }, onError: (_, __) {
      if (!mounted) return;
      setState(() {
        _imageOk = false;
        _imageLoading = false;
      });
    });
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) _stream!.removeListener(_listener!);
    super.dispose();
  }

  Future<void> _uploadReference() async {
    final st = ref.read(panelControllerProvider);
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1920, maxHeight: 1920);
    if (f == null) return;
    try {
      await st.api.uploadReference(widget.camera.id, await f.readAsBytes(), f.name.isEmpty ? 'reference.jpg' : f.name);
      _bust = DateTime.now().millisecondsSinceEpoch;
      _resolveImage();
      await ref.read(panelControllerProvider.notifier).reloadSite();
      if (mounted) toast(context, 'Reference photo uploaded');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<(String, String)?> _zoneDialog({String name = '', String type = 'restricted', required String title}) async {
    final ctrl = TextEditingController(text: name);
    var t = type;
    final res = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: C.panel,
          title: Text(title, style: sans(size: 17, weight: FontWeight.w700)),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: fieldDecoration('Zone name', hint: 'e.g. Crane 2 swing radius')),
              const SizedBox(height: 12),
              for (final opt in const [
                ('restricted', 'Restricted zone', 'Any person entering raises an alert'),
                ('height', 'Work at height', 'Workers inside must wear a harness'),
              ])
                ListTile(
                  onTap: () => setD(() => t = opt.$1),
                  leading: Icon(t == opt.$1 ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: t == opt.$1 ? C.orange : C.muted),
                  title: Text(opt.$2, style: sans(size: 14)),
                  subtitle: Text(opt.$3, style: sans(size: 12, color: C.muted)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                if (ctrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, (ctrl.text.trim(), t));
              },
              child: Text('OK', style: sans(size: 14, color: C.orange, weight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    return res;
  }

  Future<void> _finishDrawing() async {
    final pts = drawing;
    if (pts == null || pts.length < 3) return;
    final r = await _zoneDialog(title: 'New zone');
    if (r == null) return;
    setState(() {
      zones.add(Zone('', r.$1, r.$2, pts));
      drawing = null;
      selected = zones.length - 1;
      dirty = true;
    });
  }

  Future<void> _editZone(int i) async {
    final z = zones[i];
    final r = await _zoneDialog(title: 'Edit zone', name: z.name, type: z.type);
    if (r == null) return;
    setState(() {
      z.name = r.$1;
      z.type = r.$2;
      dirty = true;
    });
  }

  Future<void> _save() async {
    final st = ref.read(panelControllerProvider);
    final ctrl = ref.read(panelControllerProvider.notifier);
    setState(() => saving = true);
    try {
      final saved = await st.api.saveZones(widget.camera.id, zones);
      await ctrl.reloadSite();
      if (!mounted) return;
      setState(() {
        zones = saved;
        dirty = false;
      });
      toast(context, 'Zones saved · active on the next analysed frame');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _back() async {
    if (dirty &&
        !await confirmDialog(context, 'Discard changes?', 'Your zone changes are not saved.', action: 'Discard')) {
      return;
    }
    if (mounted) context.go('/cameras');
  }

  int? _hitVertex(Offset localPos, Size size) {
    final sel = selected;
    if (sel == null || sel < 0 || sel >= zones.length) return null;
    final pts = zones[sel].polygon;
    for (var i = 0; i < pts.length; i++) {
      final pt = Offset(pts[i][0] * size.width, pts[i][1] * size.height);
      if ((pt - localPos).distance <= 14) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(panelControllerProvider);
    final canEdit = st.user?.canManage ?? false;
    final cam = widget.camera;

    final canvas = AspectRatio(
      aspectRatio: _aspect,
      child: LayoutBuilder(builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return MouseRegion(
          cursor: drawing != null ? SystemMouseCursors.precise : SystemMouseCursors.basic,
          child: GestureDetector(
            onTapUp: (d) {
              if (drawing == null) return;
              setState(() => drawing!.add([
                    (d.localPosition.dx / size.width).clamp(0.0, 1.0).toDouble(),
                    (d.localPosition.dy / size.height).clamp(0.0, 1.0).toDouble(),
                  ]));
            },
            onPanStart: !canEdit || drawing != null
                ? null
                : (d) {
                    _draggingVertex = _hitVertex(d.localPosition, size);
                  },
            onPanUpdate: !canEdit || drawing != null
                ? null
                : (d) {
                    final sel = selected;
                    final vIdx = _draggingVertex;
                    if (sel == null || vIdx == null) return;
                    setState(() {
                      zones[sel].polygon[vIdx] = [
                        (d.localPosition.dx / size.width).clamp(0.0, 1.0).toDouble(),
                        (d.localPosition.dy / size.height).clamp(0.0, 1.0).toDouble(),
                      ];
                      dirty = true;
                    });
                  },
            onPanEnd: !canEdit || drawing != null ? null : (_) => _draggingVertex = null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(fit: StackFit.expand, children: [
                if (_imageOk)
                  Image.network(_url, fit: BoxFit.fill, gaplessPlayback: true)
                else
                  Container(
                    color: C.panel2,
                    alignment: Alignment.center,
                    child: _imageLoading
                        ? const CircularProgressIndicator()
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No camera image yet.\nUpload a reference photo of this camera view, or connect the stream.\n'
                              'You can still draw zones on the empty canvas.',
                              textAlign: TextAlign.center,
                              style: sans(size: 13, color: C.muted, height: 1.5),
                            ),
                          ),
                  ),
                CustomPaint(painter: _ZonePainter(zones, drawing, selected)),
              ]),
            ),
          ),
        );
      }),
    );

    final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (canEdit) ...[
        if (drawing == null)
          BigButton(label: 'Draw New Zone', icon: Icons.draw_outlined, onPressed: () => setState(() => drawing = [])),
        if (drawing != null) ...[
          Panel(
            color: alpha(C.orange, 0.08),
            borderColor: alpha(C.orange, 0.5),
            padding: const EdgeInsets.all(12),
            child: Text(
              'Click on the image to place the corners of the zone (${drawing!.length} placed). '
              'Place at least 3, then press Finish.',
              style: sans(size: 12.5, color: C.orange, height: 1.4),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ActionButton(
                label: 'Undo',
                icon: Icons.undo,
                onPressed: drawing!.isEmpty ? null : () => setState(() => drawing!.removeLast()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: ActionButton(
                    label: 'Cancel', icon: Icons.close, onPressed: () => setState(() => drawing = null))),
          ]),
          const SizedBox(height: 8),
          BigButton(
            label: 'Finish Zone',
            icon: Icons.check,
            color: C.green,
            textColor: const Color(0xFF052E1C),
            onPressed: drawing!.length >= 3 ? _finishDrawing : null,
          ),
        ],
        const SizedBox(height: 10),
        ActionButton(label: 'Upload Reference Photo', icon: Icons.add_photo_alternate_outlined, onPressed: _uploadReference),
        const SizedBox(height: 16),
      ],
      Text('ZONES (${zones.length})', style: mono(size: 11, color: C.muted, weight: FontWeight.w700)),
      if (canEdit && selected != null && drawing == null) ...[
        const SizedBox(height: 4),
        Text('Tip: drag orange corner handles on the canvas to adjust the selected zone.',
            style: sans(size: 11.5, color: C.orange)),
      ],
      const SizedBox(height: 8),
      if (zones.isEmpty) Text('No zones yet.', style: sans(size: 13, color: C.muted)),
      for (var i = 0; i < zones.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: C.panel2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: selected == i ? C.orange : Colors.transparent),
            ),
            child: ListTile(
              dense: true,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onTap: () => setState(() => selected = selected == i ? null : i),
              leading: Icon(zones[i].type == 'restricted' ? Icons.warning_amber_rounded : Icons.height,
                  color: zones[i].type == 'restricted' ? C.red : C.blue),
              title: Text(zones[i].name, style: sans(size: 13.5, weight: FontWeight.w600)),
              subtitle: Text(
                  '${zones[i].type == 'restricted' ? 'Restricted' : 'Work at height'} · ${zones[i].polygon.length} corners',
                  style: mono(size: 10.5, color: C.muted)),
              trailing: canEdit
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _editZone(i)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: C.pink),
                        onPressed: () => setState(() {
                          zones.removeAt(i);
                          selected = null;
                          dirty = true;
                        }),
                      ),
                    ])
                  : null,
            ),
          ),
        ),
      if (canEdit) ...[
        const SizedBox(height: 10),
        BigButton(
            label: dirty ? 'Save Zones' : 'Saved',
            icon: Icons.save_outlined,
            busy: saving,
            onPressed: dirty ? _save : null),
      ] else
        Text('Only administrators and OHS specialists can edit zones.', style: sans(size: 12, color: C.muted)),
    ]);

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 20, 10),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.border))),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
              const SizedBox(width: 6),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Zones · ${cam.id}', style: sans(size: 19, weight: FontWeight.w800)),
                  Text(cam.name, style: sans(size: 12.5, color: C.muted)),
                ]),
              ),
              if (dirty) const Pill('UNSAVED CHANGES', color: C.yellow, small: true),
            ]),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth > 900;
              if (wide) {
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: canvas)),
                  SizedBox(
                      width: 340,
                      child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(0, 20, 20, 20), child: side)),
                ]);
              }
              return ListView(padding: const EdgeInsets.all(16), children: [canvas, const SizedBox(height: 16), side]);
            }),
          ),
        ]),
      ),
    );
  }
}

class _ZonePainter extends CustomPainter {
  _ZonePainter(this.zones, this.drawing, this.selected);
  final List<Zone> zones;
  final List<List<double>>? drawing;
  final int? selected;

  Offset _pt(List<double> p, Size s) => Offset(p[0] * s.width, p[1] * s.height);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < zones.length; i++) {
      final z = zones[i];
      if (z.polygon.length < 3) continue;
      final color = z.type == 'restricted' ? C.red : C.blue;
      final path = Path()..addPolygon([for (final p in z.polygon) _pt(p, size)], true);
      canvas.drawPath(path, Paint()..color = alpha(color, selected == i ? 0.32 : 0.18));
      canvas.drawPath(
          path,
          Paint()
            ..color = selected == i ? C.orange : color
            ..style = PaintingStyle.stroke
            ..strokeWidth = selected == i ? 3 : 2);
      if (selected == i) {
        for (final p in z.polygon) {
          canvas.drawCircle(_pt(p, size), 5.5, Paint()..color = C.orange);
          canvas.drawCircle(
              _pt(p, size),
              5.5,
              Paint()
                ..color = Colors.white
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5);
        }
      }
      final tp = TextPainter(
        text: TextSpan(
            text: ' ${z.name.toUpperCase()} ',
            style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                backgroundColor: alpha(color, 0.85))),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, _pt(z.polygon.first, size) + const Offset(4, 4));
    }
    final d = drawing;
    if (d != null && d.isNotEmpty) {
      final line = Paint()
        ..color = C.orange
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      for (var i = 1; i < d.length; i++) {
        canvas.drawLine(_pt(d[i - 1], size), _pt(d[i], size), line);
      }
      if (d.length >= 3) {
        canvas.drawLine(
            _pt(d.last, size),
            _pt(d.first, size),
            Paint()
              ..color = alpha(C.orange, 0.45)
              ..strokeWidth = 1.5);
      }
      for (final p in d) {
        canvas.drawCircle(_pt(p, size), 5, Paint()..color = C.orange);
        canvas.drawCircle(
            _pt(p, size),
            5,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ZonePainter old) => true;
}
