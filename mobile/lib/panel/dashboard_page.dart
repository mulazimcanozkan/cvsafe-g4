import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.onOpenIncident, required this.onGoto});
  final void Function(Incident) onOpenIncident;
  final void Function(String page) onGoto;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final range = st.analyticsRange;
    final a = st.analytics[range];
    if (a == null && !st.analyticsLoading && st.analyticsError == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (st.analytics[st.analyticsRange] == null && !st.analyticsLoading && st.analyticsError == null) {
          st.loadAnalytics(st.analyticsRange);
        }
      });
    }
    final open = st.openIncidents;
    final cams = st.site?.cameras ?? const <Camera>[];
    final h = st.health;
    return PanelPage(
      title: 'Dashboard',
      subtitle: '${st.site?.name ?? ''} ${st.site?.block ?? ''} · live overview',
      actions: [
        RangeChips(value: range, onChanged: st.loadAnalytics),
        ActionButton(label: 'Refresh', icon: Icons.refresh, onPressed: () {
          st.refresh();
          st.loadAnalytics(range);
        }),
      ],
      children: [
        if (a == null && st.analyticsError != null)
          Panel(child: Text('Could not load analytics: ${st.analyticsError}', style: sans(size: 13, color: C.pink)))
        else if (a == null)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
        else ...[
          Wrap(spacing: 12, runSpacing: 12, children: [
            KpiCard(
                label: 'COMPLIANCE INDEX',
                value: '${a.complianceIndex.round()} / 100',
                sub: 'Grade ${a.grade} · ${a.risk}',
                icon: Icons.verified_user_outlined,
                color: a.complianceIndex >= 90 ? C.green : (a.complianceIndex >= 75 ? C.yellow : C.red)),
            KpiCard(
                label: 'OPEN VIOLATIONS',
                value: '${open.length}',
                sub: '${st.criticalOpen} critical',
                icon: Icons.warning_amber_rounded,
                color: open.isEmpty ? C.green : C.red),
            KpiCard(
                label: 'WORKERS SCANNED',
                value: '${a.totalScanned}',
                sub: '${a.violations} violations in period',
                icon: Icons.center_focus_strong,
                color: C.blue),
            KpiCard(
                label: 'PPE RATE',
                value: a.ppeRate == null ? '-' : '${a.ppeRate!.toStringAsFixed(1)}%',
                sub: a.falseAlarmRate == null ? 'No feedback yet' : '${(a.falseAlarmRate! * 100).round()}% false alarms',
                icon: Icons.health_and_safety_outlined,
                color: C.green),
            KpiCard(
                label: 'MEAN RESPONSE',
                value: a.mttrSeconds == null ? '-' : '${a.mttrSeconds! ~/ 60}m ${a.mttrSeconds! % 60}s',
                sub: 'Alert to acknowledge',
                icon: Icons.timer_outlined,
                color: C.yellow),
            KpiCard(
                label: 'AI ENGINE',
                value: '${(h?.latencyMs ?? 0).round()} ms',
                sub: '${h?.streamsActive ?? 0}/${h?.streamsTotal ?? 0} streams · ${h?.mode ?? '-'}',
                icon: Icons.memory,
                color: C.orange),
          ]),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth > 1000;
            final trend = Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SectionTitle('Violations over time', icon: Icons.bar_chart),
                TrendChart(points: a.trend),
              ]),
            );
            final breakdown = Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SectionTitle('By violation type', icon: Icons.pie_chart_outline),
                if (a.breakdown.isEmpty) Text('No violations in this period.', style: sans(size: 13, color: C.muted)),
                for (final b in a.breakdown) _barRow(b.title, b.count, a.totalEvents, C.orange),
                const SizedBox(height: 14),
                SectionTitle('By camera', icon: Icons.videocam_outlined),
                if (a.byCamera.isEmpty) Text('No data.', style: sans(size: 13, color: C.muted)),
                for (final b in a.byCamera) _barRow('${b.cameraId} · ${b.name}', b.count, a.violations, C.blue),
              ]),
            );
            return wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 3, child: trend),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: breakdown),
                  ])
                : Column(children: [trend, const SizedBox(height: 16), breakdown]);
          }),
        ],
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth > 1000;
          final openPanel = Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionTitle('Open alerts', icon: Icons.notifications_active_outlined,
                  trailing: TextButton(onPressed: () => onGoto('incidents'), child: const Text('View all'))),
              if (open.isEmpty) Text('No open alerts. All zones compliant.', style: sans(size: 13, color: C.green)),
              for (final i in open.take(6))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => onOpenIncident(i),
                  leading: Dot(color: severityColor(i.severity), size: 10),
                  title: Text(i.title, style: sans(size: 13.5, weight: FontWeight.w600)),
                  subtitle: Text('${i.cameraId ?? 'UPLOAD'} · ${i.zoneName ?? i.cameraName ?? ''} · ${timeAgo(i.createdAt)}',
                      style: mono(size: 10.5, color: C.muted)),
                  trailing: const Icon(Icons.chevron_right, color: C.muted),
                ),
            ]),
          );
          final camPanel = Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionTitle('Cameras', icon: Icons.videocam_outlined,
                  trailing: TextButton(onPressed: () => onGoto('cameras'), child: const Text('Manage'))),
              for (final cam in cams)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(cam.live ? Icons.videocam : Icons.videocam_off_outlined, color: cam.live ? C.green : C.dim),
                  title: Text('${cam.id} · ${cam.name}', style: sans(size: 13.5, weight: FontWeight.w600)),
                  subtitle: Text(
                      '${cam.live ? 'LIVE · ${cam.fps.toStringAsFixed(1)} fps' : 'offline'} · ${cam.zones.length} zones · ${cam.subcontractor ?? 'no subcontractor'}',
                      style: mono(size: 10.5, color: C.muted)),
                  trailing: cam.openViolations > 0
                      ? Pill('${cam.openViolations} OPEN', color: C.red, small: true)
                      : Pill('OK', color: C.green, small: true),
                ),
            ]),
          );
          return wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: openPanel),
                  const SizedBox(width: 16),
                  Expanded(child: camPanel),
                ])
              : Column(children: [openPanel, const SizedBox(height: 16), camPanel]);
        }),
      ],
    );
  }

  Widget _barRow(String label, int count, int total, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: sans(size: 13), overflow: TextOverflow.ellipsis)),
            Text('$count', style: mono(size: 12, weight: FontWeight.w700, color: color)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                value: total == 0 ? 0 : count / total, minHeight: 6, color: color, backgroundColor: C.border),
          ),
        ]),
      );
}
