import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Evidence for one incident: annotated snapshot, field metadata, actions, timeline.
class EvidenceScreen extends StatefulWidget {
  const EvidenceScreen({super.key});
  @override
  State<EvidenceScreen> createState() => _EvidenceScreenState();
}

class _EvidenceScreenState extends State<EvidenceScreen> {
  bool annotated = true;
  bool busy = false;
  int? _loadedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final st = AppScope.of(context);
    final inc = st.selectedIncident;
    if (inc != null && inc.id != _loadedFor) {
      _loadedFor = inc.id;
      annotated = true;
      // the list endpoint has no timeline; fetch the full incident once
      WidgetsBinding.instance.addPostFrameCallback((_) => st.loadIncidentDetail(inc.id));
    }
  }

  Future<void> _run(Future<String?> Function() fn, String ok) async {
    setState(() => busy = true);
    final err = await fn();
    if (!mounted) return;
    setState(() => busy = false);
    toast(context, err ?? ok, error: err != null);
  }

  Future<void> _falseAlarm(Incident inc) async {
    final st = AppScope.read(context);
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.panel,
        title: Text('Mark as false alarm?', style: sans(size: 17, weight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('The snapshot is sent to the AI feedback loop to reduce similar mistakes.',
              style: sans(size: 13, color: C.muted)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            style: sans(size: 14),
            decoration: InputDecoration(
              hintText: 'Reason (optional) e.g. helmet was worn',
              filled: true,
              fillColor: C.panel2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Mark false alarm', style: sans(size: 14, color: C.pink, weight: FontWeight.w600))),
        ],
      ),
    );
    if (confirmed == true) {
      final note = ctrl.text.trim();
      await _run(() => st.falseAlarm(inc, note: note.isEmpty ? null : note), 'Sent to AI feedback loop');
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final inc = st.selectedIncident;
    if (inc == null) {
      return ListView(padding: const EdgeInsets.all(16), children: const [
        OfflineBanner(),
        EmptyState(
            icon: Icons.verified_outlined,
            title: 'No incident selected',
            text: 'Open an alert, or scan a photo/video in AI Scan to create evidence.'),
      ]);
    }
    final sev = severityColor(inc.severity);
    final img = annotated ? inc.imageUrl : (inc.rawUrl ?? inc.imageUrl);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      const OfflineBanner(),
      // headline card
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Pill(
              inc.isOpen
                  ? '${inc.severity.toUpperCase()} VIOLATION'
                  : (inc.status == 'false_alarm' ? 'FALSE ALARM' : 'ADDRESSED'),
              color: inc.isOpen ? sev : (inc.status == 'false_alarm' ? C.muted : C.green),
              filled: inc.isOpen && inc.isCritical,
              icon: Icons.circle,
            ),
            const Spacer(),
            const Icon(Icons.schedule, size: 14, color: C.yellow),
            const SizedBox(width: 4),
            Text('${clock(inc.createdAt)} (${timeAgo(inc.createdAt)})',
                style: mono(size: 11, color: C.yellow, weight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          Text(inc.title, style: sans(size: 21, weight: FontWeight.w800, height: 1.2)),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.videocam_outlined, size: 15, color: C.blue),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${inc.cameraId ?? 'UPLOAD'}: ${inc.cameraName ?? 'Field photo/video'}',
                  style: mono(size: 11.5, color: C.blue, weight: FontWeight.w600)),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      // evidence image
      Stack(children: [
        NetImage(img == null ? null : st.api.url(img), height: 300, radius: 14, fit: BoxFit.contain),
        Positioned(
          left: 10,
          bottom: 10,
          child: Pill(
            '${(inc.mode ?? 'baseline') == 'ppe-model' ? 'YOLO PPE + POSE' : 'YOLO POSE + BASELINE'}'
            '${inc.confidence != null ? ' · ${(inc.confidence! * 100).round()}%' : ''}',
            color: C.text,
            small: true,
          ),
        ),
        if (img != null)
          const Positioned(top: 10, right: 10, child: Pill('KVKK FACE MASKED', color: C.green, small: true)),
      ]),
      const SizedBox(height: 10),
      Panel(
        padding: const EdgeInsets.all(6),
        child: Row(children: [
          Expanded(child: _toggle('ANNOTATED', Icons.accessibility_new, annotated, () => setState(() => annotated = true))),
          Expanded(child: _toggle('RAW (BLURRED)', Icons.videocam_outlined, !annotated, () => setState(() => annotated = false))),
        ]),
      ),
      const SizedBox(height: 14),
      // metadata
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.fact_check_outlined, color: C.blue, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('FIELD INCIDENT METADATA', style: mono(size: 12, color: C.blue, weight: FontWeight.w700))),
            Pill(st.online ? 'SYNCED' : (st.demo ? 'DEMO' : 'OFFLINE'), color: st.online ? C.green : C.yellow, small: true),
          ]),
          const SizedBox(height: 12),
          InfoRow(icon: Icons.handshake_outlined, label: 'Subcontractor', value: inc.subcontractor ?? 'Unassigned'),
          InfoRow(
              icon: Icons.place_outlined,
              label: 'Zone / Location',
              value: inc.zoneName ?? inc.cameraName ?? 'Not in a defined zone',
              sub: inc.cameraId),
          InfoRow(
              icon: Icons.badge_outlined,
              label: 'Worker / Tag',
              value: inc.personIds.isEmpty ? '-' : inc.personIds.map((p) => 'Tracker #W-$p').join(', '),
              sub: inc.count > 1 ? '${inc.count} detections merged' : null),
          InfoRow(
              icon: Icons.gavel_outlined,
              label: 'Legal Framework',
              value: inc.references.isEmpty ? '6331 s. ISG Kanunu' : inc.references.join('\n'),
              valueColor: C.orange,
              sub: 'Confirm article with OHS specialist'),
          InfoRow(icon: Icons.memory_outlined, label: 'Source', value: inc.source.toUpperCase()),
        ]),
      ),
      const SizedBox(height: 16),
      // actions
      SectionTitle('Field Intervention Actions', icon: Icons.bolt, trailing: Pill('REAL-TIME', color: C.muted, small: true)),
      if (inc.isOpen) ...[
        BigButton(
          label: 'Acknowledged & Addressed',
          icon: Icons.check_circle_outline,
          color: C.green,
          textColor: const Color(0xFF052E1C),
          busy: busy,
          onPressed: () => _run(() => st.acknowledge(inc), 'Marked as addressed'),
        ),
        const SizedBox(height: 10),
        BigButton(
          label: 'Mark as False Alarm (AI Feedback Loop)',
          icon: Icons.cancel_outlined,
          color: C.pink,
          outlined: true,
          onPressed: busy ? null : () => _falseAlarm(inc),
        ),
      ] else
        Panel(
          child: Row(children: [
            Icon(inc.status == 'false_alarm' ? Icons.cancel_outlined : Icons.check_circle, color: inc.status == 'false_alarm' ? C.muted : C.green),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  inc.status == 'false_alarm'
                      ? 'Marked as false alarm${inc.ackAt != null ? ' at ${clock(inc.ackAt!)}' : ''}'
                      : 'Addressed${inc.ackAt != null ? ' at ${clock(inc.ackAt!)} · response ${((inc.ackAt! - inc.createdAt) / 60).toStringAsFixed(1)} min' : ''}',
                  style: sans(size: 13.5)),
            ),
          ]),
        ),
      const SizedBox(height: 10),
      Panel(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: C.panel2, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.radio, color: C.blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Field Warden', style: mono(size: 13, weight: FontWeight.w700)),
              Text('Radio dispatch to ${inc.zoneName ?? inc.cameraName ?? 'site'}', style: sans(size: 12, color: C.muted)),
            ]),
          ),
          TextButton(
            onPressed: busy ? null : () => _run(() => st.fieldAction(inc, 'dispatch'), 'Warden dispatched'),
            style: TextButton.styleFrom(backgroundColor: alpha(C.blue, 0.15)),
            child: Text('DISPATCH', style: mono(size: 11, color: C.blue, weight: FontWeight.w700)),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      // timeline
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.history, size: 18, color: C.muted),
            const SizedBox(width: 8),
            Expanded(child: Text('RECENT INCIDENT TIMELINE', style: mono(size: 12, weight: FontWeight.w700))),
            Text('LIVE LOG', style: mono(size: 10, color: C.muted)),
          ]),
          const SizedBox(height: 12),
          if (inc.timeline.isEmpty) Text('Loading timeline...', style: sans(size: 13, color: C.muted)),
          for (var i = 0; i < inc.timeline.length; i++) _timelineRow(inc.timeline[i], i == inc.timeline.length - 1),
        ]),
      ),
      const SizedBox(height: 14),
      Panel(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Icon(Icons.laptop_mac, color: C.muted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Full Law 6331 dossiers & zone configuration are managed on the Desktop Web Portal',
                style: mono(size: 10.5, color: C.muted)),
          ),
        ]),
      ),
    ]);
  }

  Widget _toggle(String label, IconData icon, bool active, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(color: active ? C.orange : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: active ? Colors.white : C.muted),
            const SizedBox(width: 6),
            Text(label, style: mono(size: 11, weight: FontWeight.w700, color: active ? Colors.white : C.muted)),
          ]),
        ),
      );

  Widget _timelineRow(TimelineEvent e, bool last) {
    final color = switch (e.kind) {
      'ai' => C.pink,
      'telemetry' => C.blue,
      'user' => C.green,
      _ => C.orange,
    };
    final label = switch (e.kind) {
      'ai' => 'AI SENSOR',
      'telemetry' => 'TELEMETRY',
      'user' => 'FIELD MANAGER',
      _ => 'ACTION',
    };
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Column(children: [
          const SizedBox(height: 4),
          Dot(color: color, size: 9),
          if (!last) Expanded(child: Container(width: 1.5, color: C.border)),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(clock(e.ts), style: mono(size: 11, color: color, weight: FontWeight.w700)),
                const Spacer(),
                Text(label, style: mono(size: 9.5, color: C.muted, weight: FontWeight.w700)),
              ]),
              const SizedBox(height: 2),
              Text(e.text, style: sans(size: 13)),
            ]),
          ),
        ),
      ]),
    );
  }
}
