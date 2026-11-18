import 'package:cvsafe_core/cvsafe_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'common.dart';
import 'state.dart';

/// Searchable incident log with filters and a detail dialog.
class IncidentsPage extends ConsumerStatefulWidget {
  const IncidentsPage({super.key, this.initialIncidentId});
  final int? initialIncidentId;

  @override
  ConsumerState<IncidentsPage> createState() => IncidentsPageState();
}

class IncidentsPageState extends ConsumerState<IncidentsPage> {
  String? status = 'open';
  String? category;
  String? cameraId;
  String? severity;
  final _search = TextEditingController();
  int limit = 50;
  List<Incident> rows = [];
  bool loading = false;
  String? error;
  bool _loaded = false;
  int? _openedInitialId;

  @override
  void initState() {
    super.initState();
    if (widget.initialIncidentId != null) {
      status = null; // ensure the deep-linked incident can be seen regardless of status
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => load());
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final st = ref.read(panelControllerProvider);
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await st.api.incidents(status: status, category: category, cameraId: cameraId, limit: limit);
      if (!mounted) return;
      setState(() => rows = r);
      _maybeOpenInitial();
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Server not reachable');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _maybeOpenInitial() async {
    final targetId = widget.initialIncidentId;
    if (targetId == null || _openedInitialId == targetId) return;
    _openedInitialId = targetId;
    Incident? target;
    for (final i in rows) {
      if (i.id == targetId) {
        target = i;
        break;
      }
    }
    target ??= await ref.read(panelControllerProvider.notifier).loadIncidentDetail(targetId);
    if (target != null && mounted) {
      showIncidentDialog(context, target, onChanged: load);
    }
  }

  List<Incident> get _filteredRows {
    final q = _search.text.trim().toLowerCase();
    return rows.where((i) {
      if (severity != null && i.severity != severity) return false;
      if (q.isEmpty) return true;
      return '${i.id}' == q ||
          '#${i.id}' == q ||
          i.title.toLowerCase().contains(q) ||
          (i.cameraId ?? '').toLowerCase().contains(q) ||
          (i.cameraName ?? '').toLowerCase().contains(q) ||
          (i.zoneName ?? '').toLowerCase().contains(q) ||
          (i.subcontractor ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Widget _dropdown<T>(String label, T? value, List<(T?, String)> items, ValueChanged<T?> onChanged, { bool reload = true }) =>
      SizedBox(
        width: 185,
        child: InputDecorator(
          decoration: fieldDecoration(label).copyWith(contentPadding: const EdgeInsets.fromLTRB(12, 4, 8, 4)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T?>(
              value: value,
              isExpanded: true,
              dropdownColor: C.panel2,
              style: sans(size: 13),
              items: [
                for (final i in items)
                  DropdownMenuItem<T?>(value: i.$1, child: Text(i.$2, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                onChanged(v);
                if (reload) {
                  limit = 50;
                  load();
                }
              },
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(panelControllerProvider);
    final cams = st.site?.cameras ?? const <Camera>[];
    final visible = _filteredRows;
    return PanelPage(
      title: 'Incidents',
      subtitle: 'Every AI alert with evidence, response and timeline',
      actions: [ActionButton(label: 'Refresh', icon: Icons.refresh, onPressed: loading ? null : load)],
      children: [
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _dropdown<String>('Status', status, const [
            (null, 'All'),
            ('open', 'Open'),
            ('acknowledged', 'Addressed'),
            ('false_alarm', 'False alarm'),
          ], (v) => setState(() => status = v)),
          _dropdown<String>('Type', category, const [
            (null, 'All types'),
            ('ppe', 'PPE'),
            ('zone', 'Danger zone'),
            ('height', 'Work at height'),
            ('fall', 'Fall'),
            ('proximity', 'Machinery'),
          ], (v) => setState(() => category = v)),
          _dropdown<String>('Camera', cameraId, [
            (null, 'All cameras'),
            for (final c in cams) (c.id, '${c.id} · ${c.name}'),
          ], (v) => setState(() => cameraId = v)),
          _dropdown<String>(
            'Severity',
            severity,
            const [
              (null, 'All severities'),
              ('critical', 'Critical'),
              ('high', 'High'),
              ('moderate', 'Moderate'),
            ],
            (v) => setState(() => severity = v),
            reload: false,
          ),
          SizedBox(
            width: 240,
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: sans(size: 13),
              decoration: fieldDecoration('Search', hint: 'Title, zone, company, #id', icon: Icons.search).copyWith(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 16, color: C.muted),
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        if (error != null)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(error!, style: sans(size: 13, color: C.pink))),
        if (loading && rows.isEmpty)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        if (!loading && visible.isEmpty && error == null)
          const EmptyState(icon: Icons.inbox_outlined, title: 'No incidents match these filters'),
        if (visible.isNotEmpty)
          TablePanel(
            table: DataTable(
              showCheckboxColumn: false,
              headingRowHeight: 42,
              dataRowMinHeight: 52,
              dataRowMaxHeight: 64,
              columns: [
                DataColumn(label: Text('#', style: tableHeader)),
                DataColumn(label: Text('TIME', style: tableHeader)),
                DataColumn(label: Text('INCIDENT', style: tableHeader)),
                DataColumn(label: Text('LOCATION', style: tableHeader)),
                DataColumn(label: Text('SUBCONTRACTOR', style: tableHeader)),
                DataColumn(label: Text('SEVERITY', style: tableHeader)),
                DataColumn(label: Text('STATUS', style: tableHeader)),
              ],
              rows: [
                for (final i in visible)
                  DataRow(
                    onSelectChanged: (_) => showIncidentDialog(context, i, onChanged: load),
                    cells: [
                      DataCell(Text('${i.id}', style: mono(size: 12, color: C.muted))),
                      DataCell(Text(dateTime(i.createdAt), style: mono(size: 12))),
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Text(i.title,
                            style: tableCell.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      )),
                      DataCell(Text('${i.cameraId ?? 'UPLOAD'} · ${i.zoneName ?? i.cameraName ?? '-'}', style: tableCell)),
                      DataCell(Text(i.subcontractor ?? '-', style: tableCell)),
                      DataCell(Pill(i.severity.toUpperCase(), color: severityColor(i.severity), small: true)),
                      DataCell(_statusPill(i.status)),
                    ],
                  ),
              ],
            ),
          ),
        if (rows.length >= limit) ...[
          const SizedBox(height: 12),
          Center(
            child: ActionButton(
              label: 'Load more',
              icon: Icons.expand_more,
              onPressed: loading
                  ? null
                  : () {
                      limit += 50;
                      load();
                    },
            ),
          ),
        ],
      ],
    );
  }
}

Widget _statusPill(String status) => switch (status) {
      'open' => const Pill('OPEN', color: C.red, small: true),
      'acknowledged' => const Pill('ADDRESSED', color: C.green, small: true),
      _ => const Pill('FALSE ALARM', color: C.muted, small: true),
    };

/// Incident detail with evidence image, metadata, actions and timeline.
Future<void> showIncidentDialog(BuildContext context, Incident inc, {VoidCallback? onChanged}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: C.bg,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 760),
        child: _IncidentDetail(incident: inc, onChanged: onChanged),
      ),
    ),
  );
}

class _IncidentDetail extends ConsumerStatefulWidget {
  const _IncidentDetail({required this.incident, this.onChanged});
  final Incident incident;
  final VoidCallback? onChanged;
  @override
  ConsumerState<_IncidentDetail> createState() => _IncidentDetailState();
}

class _IncidentDetailState extends ConsumerState<_IncidentDetail> {
  late Incident inc = widget.incident;
  bool raw = false;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    try {
      final full = await ref.read(panelControllerProvider).api.incident(inc.id);
      if (mounted) setState(() => inc = full);
    } catch (_) {}
  }

  Future<void> _do(Future<Incident> Function() call, String ok) async {
    setState(() => busy = true);
    try {
      final r = await call();
      if (!mounted) return;
      setState(() => inc = r);
      ref.read(panelControllerProvider.notifier).replaceIncident(r);
      widget.onChanged?.call();
      ref.read(panelControllerProvider.notifier).refresh(quiet: true);
      toast(context, ok);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _promptFalseAlarm() async {
    final reasons = ref.read(panelControllerProvider).falseAlarmReasons;
    var selectedReason = reasons.isNotEmpty ? reasons.first.code : 'wrong_detection';
    var noteText = '';
    final res = await showDialog<(String, String?)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: C.panel,
          title: Text('Mark as false alarm', style: sans(size: 17, weight: FontWeight.w700)),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Select the reason for the AI feedback loop (FR-13, BR-02):',
                  style: sans(size: 13, color: C.muted)),
              const SizedBox(height: 10),
              for (final r in reasons)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onTap: () => setD(() => selectedReason = r.code),
                  leading: Icon(
                    selectedReason == r.code ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: selectedReason == r.code ? C.orange : C.muted,
                  ),
                  title: Text(r.label, style: sans(size: 13.5)),
                ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) => noteText = v,
                decoration: fieldDecoration('Optional note', hint: 'e.g. Sun reflection on scaffold', icon: Icons.notes),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final note = noteText.trim();
                Navigator.pop(ctx, (selectedReason, note.isEmpty ? null : note));
              },
              child: Text('Confirm False Alarm', style: sans(size: 14, color: C.pink, weight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    if (res == null || !mounted) return;
    final st = ref.read(panelControllerProvider);
    await _do(
      () => st.api.falseAlarm(inc.id, reason: res.$1, note: res.$2),
      'Marked as false alarm',
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(panelControllerProvider);
    final img = raw ? (inc.rawUrl ?? inc.imageUrl) : inc.imageUrl;
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Pill(inc.severity.toUpperCase(), color: severityColor(inc.severity)),
            const SizedBox(width: 8),
            _statusPill(inc.status),
          ]),
          Text('#${inc.id} · ${dateTime(inc.createdAt)}', style: mono(size: 11, color: C.muted)),
        ],
      ),
      const SizedBox(height: 10),
      Text(inc.title, style: sans(size: 20, weight: FontWeight.w800, height: 1.2)),
      const SizedBox(height: 12),
      InfoRow(
          icon: Icons.videocam_outlined,
          label: 'Camera',
          value: '${inc.cameraId ?? 'UPLOAD'} · ${inc.cameraName ?? 'Field photo/video'}'),
      InfoRow(icon: Icons.place_outlined, label: 'Zone', value: inc.zoneName ?? 'Not in a defined zone'),
      InfoRow(icon: Icons.handshake_outlined, label: 'Subcontractor', value: inc.subcontractor ?? 'Unassigned'),
      InfoRow(
          icon: Icons.badge_outlined,
          label: 'Workers',
          value: inc.personIds.isEmpty ? '-' : inc.personIds.map((p) => '#W-$p').join(', '),
          sub: inc.count > 1 ? '${inc.count} detections merged' : null),
      InfoRow(
          icon: Icons.gavel_outlined,
          label: 'Reference',
          value: inc.references.isEmpty ? '6331 s. ISG Kanunu' : inc.references.join('\n'),
          valueColor: C.orange),
      if (inc.status == 'false_alarm')
        InfoRow(
          icon: Icons.feedback_outlined,
          label: 'Reason',
          value: st.falseAlarmReasonLabel(inc.falseAlarmReason),
          valueColor: C.pink,
        ),
      if (inc.canAcknowledge || inc.canMarkFalseAlarm) ...[
        const SizedBox(height: 8),
        Row(children: [
          if (inc.canAcknowledge) ...[
            Expanded(
              child: BigButton(
                label: 'Mark Addressed',
                icon: Icons.check_circle_outline,
                color: C.green,
                textColor: const Color(0xFF052E1C),
                busy: busy,
                onPressed: () => _do(() => st.api.acknowledge(inc.id), 'Marked as addressed'),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (inc.canMarkFalseAlarm)
            Expanded(
              child: BigButton(
                label: 'False Alarm',
                icon: Icons.cancel_outlined,
                color: C.pink,
                outlined: true,
                onPressed: busy ? null : _promptFalseAlarm,
              ),
            ),
        ]),
      ],
      if (inc.status != 'false_alarm') ...[
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final act in const [
            ('siren', 'Trigger Siren', Icons.campaign_outlined),
            ('dispatch', 'Dispatch Warden', Icons.directions_walk),
            ('broadcast', 'Zone Broadcast', Icons.record_voice_over_outlined),
            ('log', 'Log Warning', Icons.edit_note),
          ])
            ActionChip(
              avatar: Icon(act.$3, size: 15, color: C.orange),
              label: Text(act.$2, style: mono(size: 11, weight: FontWeight.w600)),
              backgroundColor: C.panel2,
              side: const BorderSide(color: C.border),
              onPressed: busy ? null : () => _do(() => st.api.action(inc.id, act.$1), '${act.$2} logged'),
            ),
        ]),
      ],
      const SizedBox(height: 14),
      Text('TIMELINE', style: mono(size: 11, color: C.muted, weight: FontWeight.w700)),
      const SizedBox(height: 6),
      if (inc.timeline.isEmpty) Text('Loading...', style: sans(size: 12.5, color: C.muted)),
      for (final e in inc.timeline)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 70, child: Text(clock(e.ts), style: mono(size: 11, color: C.blue))),
            Expanded(child: Text(e.text, style: sans(size: 12.5))),
          ]),
        ),
    ]);
    final image = Column(children: [
      Expanded(
        child: Container(
          decoration: BoxDecoration(color: C.panel2, borderRadius: BorderRadius.circular(12)),
          child: img == null
              ? Center(child: Text('No snapshot stored', style: mono(size: 12, color: C.dim)))
              : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: InteractiveViewer(maxScale: 5, child: Image.network(st.api.url(img), fit: BoxFit.contain)),
                ),
        ),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        ChoiceChip(label: const Text('AI overlay'), selected: !raw, onSelected: (_) => setState(() => raw = false)),
        const SizedBox(width: 8),
        ChoiceChip(label: const Text('Raw (faces blurred)'), selected: raw, onSelected: (_) => setState(() => raw = true)),
      ]),
    ]);
    return Padding(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > 760;
        final close = Align(
          alignment: Alignment.topRight,
          child: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
        );
        if (wide) {
          return Column(children: [
            close,
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(flex: 3, child: image),
                const SizedBox(width: 18),
                Expanded(flex: 2, child: SingleChildScrollView(child: info)),
              ]),
            ),
          ]);
        }
        return Column(children: [
          close,
          Expanded(
            child: ListView(children: [SizedBox(height: 320, child: image), const SizedBox(height: 14), info]),
          ),
        ]);
      }),
    );
  }
}
