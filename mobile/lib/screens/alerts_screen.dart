import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Live alert feed for the field manager: acknowledge, act or mark false alarm.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});
  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  String filter = 'all';

  static const _filters = [
    ('all', 'All', Icons.warning_amber_rounded),
    ('critical', 'Critical', Icons.circle),
    ('ppe', 'PPE Missing', Icons.construction),
    ('zone', 'Zones', Icons.fence),
    ('resolved', 'Resolved', Icons.check_circle_outline),
  ];

  List<Incident> _apply(List<Incident> all) {
    switch (filter) {
      case 'resolved':
        return all.where((i) => !i.isOpen).toList();
      case 'critical':
        return all.where((i) => i.isOpen && i.isCritical).toList();
      case 'ppe':
        return all.where((i) => i.isOpen && i.categories.contains('ppe')).toList();
      case 'zone':
        return all.where((i) => i.isOpen && (i.categories.contains('zone') || i.categories.contains('height'))).toList();
      default:
        return all.where((i) => i.isOpen).toList();
    }
  }

  int _count(List<Incident> all, String f) {
    final keep = filter;
    filter = f;
    final n = _apply(all).length;
    filter = keep;
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final all = st.incidents;
    final open = st.openIncidents;
    final list = _apply(all);
    final warnings = open.length - st.criticalOpen;
    return RefreshIndicator(
      onRefresh: () => st.refresh(),
      color: C.orange,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        const OfflineBanner(),
        // field mode strip
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Dot(color: C.green, size: 10),
            const SizedBox(width: 8),
            Expanded(
              child: Text('FIELD INTERVENTION MODE', style: mono(size: 11, color: C.green, weight: FontWeight.w700)),
            ),
            Text(st.online ? 'Live alerts · 5s sync' : 'Demo', style: mono(size: 10, color: C.muted)),
            const SizedBox(width: 8),
            if (open.isNotEmpty) Pill('${open.length} ACTION REQ', color: C.red, filled: true, small: true),
          ]),
        ),
        const SizedBox(height: 10),
        Panel(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: alpha(C.orange, 0.15), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.gpp_maybe_outlined, color: C.orange),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text((st.site?.name ?? 'Site').toUpperCase(),
                        style: mono(size: 13, weight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 6),
                  if ((st.site?.block ?? '').isNotEmpty) Pill(st.site!.block, color: C.blue, small: true),
                ]),
                const SizedBox(height: 3),
                Text(
                  '${st.criticalOpen} Critical · $warnings Warning'
                  '${open.isNotEmpty ? ' · Last ${timeAgo(open.first.createdAt)}' : ''}',
                  style: mono(size: 11, color: C.muted),
                ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 38,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final f in _filters)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: filter == f.$1,
                  onSelected: (_) => setState(() => filter = f.$1),
                  showCheckmark: false,
                  avatar: Icon(f.$3, size: 14, color: filter == f.$1 ? Colors.white : (f.$1 == 'critical' ? C.red : C.muted)),
                  label: Text('${f.$2} (${_count(all, f.$1)})',
                      style: mono(size: 12, weight: FontWeight.w700, color: filter == f.$1 ? Colors.white : C.text)),
                  selectedColor: C.orange,
                  backgroundColor: C.panel,
                  side: BorderSide(color: filter == f.$1 ? C.orange : C.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        if (st.loading && all.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
        if (!st.loading && list.isEmpty)
          EmptyState(
            icon: filter == 'resolved' ? Icons.inbox_outlined : Icons.verified_user_outlined,
            title: filter == 'resolved' ? 'No resolved alerts yet' : 'No open alerts',
            text: filter == 'resolved' ? null : 'All monitored zones are compliant right now.',
          ),
        for (final inc in list) AlertCard(incident: inc),
      ]),
    );
  }
}

class AlertCard extends StatefulWidget {
  const AlertCard({super.key, required this.incident});
  final Incident incident;
  @override
  State<AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<AlertCard> {
  bool busy = false;

  Future<void> _run(Future<String?> Function() fn, String okMsg) async {
    setState(() => busy = true);
    final err = await fn();
    if (!mounted) return;
    setState(() => busy = false);
    toast(context, err ?? okMsg, error: err != null);
  }

  (String, String, IconData) get _secondary {
    final c = widget.incident.categories;
    if (c.contains('zone') || c.contains('proximity')) return ('siren', 'Siren/Alarm', Icons.campaign_outlined);
    if (c.contains('height') || c.contains('fall')) return ('broadcast', 'Broadcast', Icons.record_voice_over_outlined);
    return ('log', 'Log Warning', Icons.history_edu_outlined);
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final inc = widget.incident;
    final sev = severityColor(inc.severity);
    final sec = _secondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: () => st.openEvidence(inc.id),
        child: Container(
          decoration: BoxDecoration(
            color: C.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: inc.isOpen ? alpha(sev, 0.6) : C.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: inc.isOpen ? alpha(sev, inc.isCritical ? 0.55 : 0.18) : C.panel2,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
              ),
              child: Row(children: [
                Dot(color: inc.isOpen ? sev : C.dim),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${inc.categoryLabel} #${inc.id}',
                      style: mono(size: 11, weight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                ),
                if (inc.count > 1) ...[Pill('Aggregated (${inc.count}x)', color: C.blue, small: true), const SizedBox(width: 6)],
                const Icon(Icons.schedule, size: 13, color: C.text),
                const SizedBox(width: 4),
                Text('${clock(inc.createdAt)} · ${timeAgo(inc.createdAt)}', style: mono(size: 10.5)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(inc.title, style: sans(size: 18, weight: FontWeight.w700, height: 1.2))),
                  const SizedBox(width: 8),
                  if (inc.isOpen)
                    Pill(inc.isCritical ? 'HIGH RISK' : inc.severity.toUpperCase(), color: sev)
                  else
                    Pill(inc.status == 'false_alarm' ? 'FALSE ALARM' : 'ADDRESSED',
                        color: inc.status == 'false_alarm' ? C.muted : C.green),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  const Icon(Icons.videocam_outlined, size: 14, color: C.blue),
                  Text('${inc.cameraId ?? 'UPLOAD'} · ${inc.zoneName ?? inc.cameraName ?? 'Field photo'}',
                      style: mono(size: 11, color: C.blue, weight: FontWeight.w600)),
                ]),
                if (inc.subcontractor != null) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.engineering_outlined, size: 14, color: C.muted),
                    const SizedBox(width: 6),
                    Text(inc.subcontractor!, style: mono(size: 11, color: C.muted)),
                  ]),
                ],
                const SizedBox(height: 10),
                Stack(children: [
                  NetImage(inc.imageUrl == null ? null : st.api.url(inc.imageUrl!), height: 180),
                  if (inc.imageUrl != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Pill('KVKK FACE MASKED', color: C.green, icon: Icons.face_retouching_off, small: true),
                    ),
                  if (inc.confidence != null)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Pill('${(inc.confidence! * 100).round()}% CONF', color: C.text, small: true),
                    ),
                ]),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final t in inc.types)
                    Pill(violationLabels[t] ?? t, color: C.pink, icon: Icons.warning_amber_rounded, small: true),
                ]),
                if (inc.isOpen) ...[
                  const SizedBox(height: 14),
                  BigButton(
                    label: 'Acknowledged / Addressed',
                    icon: Icons.check_circle_outline,
                    busy: busy,
                    onPressed: () => _run(() => st.acknowledge(inc), 'Marked as addressed'),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: BigButton(
                        label: sec.$2,
                        icon: sec.$3,
                        color: C.text,
                        outlined: true,
                        onPressed: busy ? null : () => _run(() => st.fieldAction(inc, sec.$1), '${sec.$2} logged'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: BigButton(
                        label: 'False Alarm',
                        icon: Icons.cancel_outlined,
                        color: C.pink,
                        outlined: true,
                        onPressed: busy ? null : () => _run(() => st.falseAlarm(inc), 'Sent to AI feedback loop'),
                      ),
                    ),
                  ]),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
