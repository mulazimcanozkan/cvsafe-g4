import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Site safety KPIs computed by the server from every AI scan and incident.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {

  static const _ranges = [('today', 'Today'), ('week', 'This Week'), ('month', 'Month')];
  static const _barColors = [C.orange, C.pink, Color(0xFFFDBA74), C.blue, C.green, C.yellow];

  void _setRange(String r) => AppScope.read(context).loadAnalytics(r);

  Future<void> _openReport() async {
    final st = AppScope.read(context);
    if (!st.online) {
      toast(context, 'Reports need the server connection.', error: true);
      return;
    }
    final ok = await launchUrl(Uri.parse(st.api.reportUrl(st.analyticsRange)), mode: LaunchMode.externalApplication);
    if (!ok && mounted) toast(context, 'Could not open the PDF report', error: true);
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final range = st.analyticsRange;
    final a = st.analytics[range];
    if (a == null && !st.analyticsLoading && !st.loading && st.analyticsError == null) {
      // nothing cached for this range yet (first open, or the server just connected)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && st.analytics[st.analyticsRange] == null && !st.analyticsLoading && st.analyticsError == null) {
          st.loadAnalytics(st.analyticsRange);
        }
      });
    }
    return RefreshIndicator(
      color: C.orange,
      onRefresh: () => st.loadAnalytics(range),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        const OfflineBanner(),
        SizedBox(
          height: 38,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final r in _ranges)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: range == r.$1,
                  onSelected: (_) => _setRange(r.$1),
                  showCheckmark: false,
                  avatar: r.$1 == 'today'
                      ? Icon(Icons.calendar_today, size: 14, color: range == r.$1 ? Colors.white : C.muted)
                      : null,
                  label: Text(r.$2, style: mono(size: 12, weight: FontWeight.w700, color: range == r.$1 ? Colors.white : C.text)),
                  selectedColor: C.orange,
                  backgroundColor: C.panel,
                  side: BorderSide(color: range == r.$1 ? C.orange : C.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        if (a == null && st.analyticsError != null)
          Panel(
            child: Column(children: [
              Text('Could not load analytics: ${st.analyticsError}', style: sans(size: 13, color: C.pink)),
              const SizedBox(height: 10),
              BigButton(label: 'Retry', icon: Icons.refresh, onPressed: () => st.loadAnalytics(range)),
            ]),
          )
        else if (a == null)
          const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()))
        else ...[
          _complianceCard(a),
          const SizedBox(height: 12),
          _kpiGrid(a),
          const SizedBox(height: 14),
          _breakdown(a),
          const SizedBox(height: 14),
          _leaderboard(a),
          const SizedBox(height: 14),
          _legal(a, st.health?.mode ?? 'baseline'),
        ],
      ]),
    );
  }

  Widget _complianceCard(Analytics a) {
    final good = a.complianceIndex >= 90;
    final color = good ? C.green : (a.complianceIndex >= 75 ? C.yellow : C.red);
    final change = a.complianceChange;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('SITE SAFETY COMPLIANCE INDEX', style: mono(size: 11, color: C.muted, weight: FontWeight.w700))),
          Pill('GRADE ${a.grade} · ${a.risk.toUpperCase()}', color: color, small: true),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(a.complianceIndex.round().toString(), style: sans(size: 46, weight: FontWeight.w800)),
                Padding(
                  padding: const EdgeInsets.only(bottom: 9, left: 4),
                  child: Text('/ 100', style: sans(size: 16, color: C.dim)),
                ),
              ]),
              if (change != null)
                Row(children: [
                  Icon(change >= 0 ? Icons.trending_up : Icons.trending_down, size: 16, color: change >= 0 ? C.green : C.red),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text('${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)} vs previous period',
                        style: sans(size: 12.5, color: change >= 0 ? C.green : C.red)),
                  ),
                ]),
            ]),
          ),
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 72,
                height: 72,
                child: CircularProgressIndicator(
                  value: a.complianceIndex / 100,
                  strokeWidth: 6,
                  color: color,
                  backgroundColor: C.panel2,
                ),
              ),
              Text('${a.complianceIndex.round()}%', style: mono(size: 12, color: color, weight: FontWeight.w700)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: C.panel2, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(Icons.emoji_events_outlined, size: 16, color: C.yellow),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                a.daysSinceCritical == null
                    ? 'NO CRITICAL AI ALERTS RECORDED'
                    : a.daysSinceCritical == 0
                        ? 'CRITICAL AI ALERT RECORDED TODAY'
                        : '${a.daysSinceCritical} DAYS WITHOUT A CRITICAL AI ALERT',
                style: mono(size: 10.5, weight: FontWeight.w700),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _kpi(String label, String value, String sub, IconData icon, Color iconColor) => Expanded(
        child: Panel(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(label, style: mono(size: 9.5, color: C.muted, weight: FontWeight.w700))),
              Icon(icon, size: 16, color: iconColor),
            ]),
            const SizedBox(height: 6),
            Text(value, style: mono(size: 21, weight: FontWeight.w800, color: iconColor == C.red ? C.pink : C.text)),
            const SizedBox(height: 2),
            Text(sub, style: mono(size: 10, color: C.green)),
          ]),
        ),
      );

  Widget _kpiGrid(Analytics a) {
    final mttr = a.mttrSeconds;
    final ch = a.violationsChange;
    return Column(children: [
      Row(children: [
        _kpi('TOTAL AI SCANNED', a.totalScanned.toString(), 'Workers checked', Icons.center_focus_strong, C.blue),
        const SizedBox(width: 8),
        _kpi('ACTIVE VIOLATIONS', a.activeViolations.toString(),
            '${a.violations} in period (${ch > 0 ? '+' : ''}$ch)', Icons.warning_amber_rounded, C.red),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _kpi('MEAN RESPONSE', mttr == null ? '-' : '${mttr ~/ 60}m ${mttr % 60}s', 'Alert to acknowledge', Icons.timer_outlined, C.yellow),
        const SizedBox(width: 8),
        _kpi('PPE RATE', a.ppeRate == null ? '-' : '${a.ppeRate!.toStringAsFixed(1)}%',
            a.falseAlarmRate == null ? 'No feedback yet' : '${(a.falseAlarmRate! * 100).round()}% false alarms',
            Icons.health_and_safety_outlined, C.green),
      ]),
    ]);
  }

  Widget _breakdown(Analytics a) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle('Violation Breakdown', icon: Icons.pie_chart_outline,
              trailing: Text('TOTAL: ${a.totalEvents} EVENTS', style: mono(size: 10.5, color: C.muted))),
          if (a.breakdown.isEmpty)
            Text('No violations in this period.', style: sans(size: 13, color: C.muted))
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: Row(children: [
                  for (var i = 0; i < a.breakdown.length; i++)
                    Expanded(
                      flex: (a.breakdown[i].share * 1000).round().clamp(1, 1000).toInt(),
                      child: Container(color: _barColors[i % _barColors.length]),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < a.breakdown.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: C.panel2, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Dot(color: _barColors[i % _barColors.length], size: 10),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.breakdown[i].title, style: sans(size: 14, weight: FontWeight.w600)),
                      Text(a.breakdown[i].topLocation, style: mono(size: 10.5, color: C.muted)),
                    ]),
                  ),
                  Text('${(a.breakdown[i].share * 100).round()}% (${a.breakdown[i].count})',
                      style: mono(size: 11.5, color: _barColors[i % _barColors.length], weight: FontWeight.w700)),
                ]),
              ),
          ],
        ]),
      );

  Widget _leaderboard(Analytics a) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle('Subcontractor Leaderboard', icon: Icons.groups_outlined,
              trailing: Text('SHIFT AUDIT', style: mono(size: 10.5, color: C.blue))),
          for (var i = 0; i < a.leaderboard.length; i++) _leaderRow(i + 1, a.leaderboard[i]),
        ]),
      );

  Widget _leaderRow(int rank, LeaderRow l) {
    final (String label, Color color) = switch (l.status) {
      'top' => ('TOP PERFORMER', C.green),
      'satisfactory' => ('SATISFACTORY', C.blue),
      'warning' => ('WARNING ISSUED', C.red),
      _ => ('NO DATA', C.dim),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: C.panel2, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Row(children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: alpha(color, 0.2),
            child: Text('$rank', style: mono(size: 11, color: color, weight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.name, style: sans(size: 14.5, weight: FontWeight.w700)),
              Text('${l.workers} workers on site · ${l.trade}', style: mono(size: 10.5, color: C.muted)),
            ]),
          ),
          Pill(label, color: color, small: true),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (l.compliance ?? 0) / 100,
                minHeight: 6,
                color: color,
                backgroundColor: C.border,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(l.compliance == null ? '-' : '${l.compliance!.round()}%',
              style: mono(size: 12, color: color, weight: FontWeight.w700)),
        ]),
      ]),
    );
  }

  Widget _legal(Analytics a, String mode) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle('Legal & Regulatory Audit', icon: Icons.policy_outlined),
          Text('TURKISH OHS LAW NO. 6331 & KVKK COMPLIANCE', style: mono(size: 10.5, color: C.muted)),
          const SizedBox(height: 12),
          _legalRow(Icons.rule, 'Evidence trail', 'Every alert stored with timestamp, camera and response',
              Icons.check_circle, C.green),
          _legalRow(Icons.face_retouching_off, 'KVKK face masking', 'Faces blurred in all stored images',
              Icons.verified_user_outlined, C.green),
          _legalRow(Icons.memory, 'Detection model', mode == 'ppe-model' ? 'Trained PPE model active' : 'Baseline PPE check (train PPE model)',
              mode == 'ppe-model' ? Icons.check_circle : Icons.info_outline, mode == 'ppe-model' ? C.green : C.yellow),
          const SizedBox(height: 6),
          BigButton(label: 'Download Safety Report (PDF)', icon: Icons.picture_as_pdf_outlined, onPressed: _openReport),
        ]),
      );

  Widget _legalRow(IconData icon, String title, String sub, IconData trail, Color color) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.panel2, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: sans(size: 13.5, weight: FontWeight.w600)),
              Text(sub, style: mono(size: 10.5, color: C.muted)),
            ]),
          ),
          Icon(trail, color: color, size: 20),
        ]),
      );
}
