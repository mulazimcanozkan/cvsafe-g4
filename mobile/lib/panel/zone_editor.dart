import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';

/// Draw danger zones on a camera view by clicking the corners of each polygon.
/// Coordinates are stored normalised (0..1), so they work at any camera resolution.
class ZoneEditorPage extends StatefulWidget {
  const ZoneEditorPage({super.key, required this.camera});
  final Camera camera;
  @override
  State<ZoneEditorPage> createState() => _ZoneEditorPageState();
}

class _ZoneEditorPageState extends State<ZoneEditorPage> {
  late List<Zone> zones;
  List<List<double>>? drawing; // corners of the zone being drawn
  int? selected;
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
    zones = widget.camera.zones.map((z) => Zone(z.id, z.name, z.type, [for (final p in z.polygon) [...p]])).toList();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stream == null) _resolveImage();
  }

  String get _url => AppScope.read(context).api.frameUrl(widget.camera.id, bust: _bust);

  void _resolveImage() {
    if (_stream != null && _listener != null) _stream!.removeListener(_listener!);
    setState(() => _imageLoading = true);
    final stream = NetworkImage(_url).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() {
        _aspect = info.image.width / info.image.height;
        _imageOk = true;
        _imageLoading = false;
      });
    }, onError: (e, s) {
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
    final st = AppScope.read(context);
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1920, maxHeight: 1920);
    if (f == null) return;
    try {
      await st.api.uploadReference(widget.camera.id, await f.readAsBytes(), f.name.isEmpty ? 'reference.jpg' : f.name);
      _bust = DateTime.now().millisecondsSinceEpoch;
      _resolveImage();
      if (mounted) toast(context, 'Reference photo uploaded');
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<(String, String)?> _zoneDialog({String name = '', String type = 'restricted', required String title}) {
    final ctrl = TextEditingController(text: name);
    var t = type;
    return showDialog<(String, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: C.panel,
          title: Text(title, style: sans(size: 17, weight: FontWeight.w700)),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: ctrl, autofocus: true, decoration: fieldDecoration('Zone name', hint: 'e.g. Crane 2 swing radius')),
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
    final st = AppScope.read(context);
    setState(() => saving = true);
    try {
      final saved = await st.api.saveZones(widget.camera.id, zones);
      await st.reloadSite();
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
    if (dirty && !await confirmDialog(context, 'Discard changes?', 'Your zone changes are not saved.', action: 'Discard')) {
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
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
            Expanded(child: ActionButton(label: 'Cancel', icon: Icons.close, onPressed: () => setState(() => drawing = null))),
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
      const SizedBox(height: 8),
      if (zones.isEmpty) Text('No zones yet.', style: sans(size: 13, color: C.muted)),
      for (var i = 0; i < zones.length; i++)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: C.panel2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected == i ? C.orange : Colors.transparent),
          ),
          child: ListTile(
            dense: true,
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
      if (canEdit) ...[
        const SizedBox(height: 10),
        BigButton(label: dirty ? 'Save Zones' : 'Saved', icon: Icons.save_outlined, busy: saving, onPressed: dirty ? _save : null),
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
                  SizedBox(width: 340, child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(0, 20, 20, 20), child: side)),
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
      final tp = TextPainter(
        text: TextSpan(
            text: ' ${z.name.toUpperCase()} ',
            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, backgroundColor: alpha(color, 0.85))),
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
        canvas.drawLine(_pt(d.last, size), _pt(d.first, size), Paint()
          ..color = alpha(C.orange, 0.45)
          ..strokeWidth = 1.5);
      }
      for (final p in d) {
        canvas.drawCircle(_pt(p, size), 5, Paint()..color = C.orange);
        canvas.drawCircle(_pt(p, size), 5, Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ZonePainter old) => true;
}
