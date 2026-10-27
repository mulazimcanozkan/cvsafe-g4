import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Page frame used by every web-panel page: title row, actions, scrollable body.
class PanelPage extends StatelessWidget {
  const PanelPage({super.key, required this.title, this.subtitle, this.actions = const [], required this.children});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(28, 22, 28, 32), children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 10,
        spacing: 12,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: sans(size: 24, weight: FontWeight.w800)),
            if (subtitle != null) Text(subtitle!, style: sans(size: 13, color: C.muted)),
          ]),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
      const SizedBox(height: 20),
      ...children,
    ]);
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({super.key, required this.label, required this.value, this.sub, required this.icon, this.color = C.blue});
  final String label;
  final String value;
  final String? sub;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 230,
        child: Panel(
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: alpha(color, 0.15), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: mono(size: 10, color: C.muted, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(value, style: mono(size: 22, weight: FontWeight.w800)),
                if (sub != null) Text(sub!, style: sans(size: 11.5, color: C.muted), overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
      );
}

/// Small dependency-free bar chart: violations per bucket, scanned workers as a faint bar behind.
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.points, this.height = 180});
  final List<TrendPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(height: height, child: Center(child: Text('No data yet', style: sans(size: 13, color: C.muted))));
    }
    final maxV = points.map((p) => p.violations).fold<int>(1, (a, b) => a > b ? a : b);
    final maxS = points.map((p) => p.scanned).fold<int>(1, (a, b) => a > b ? a : b);
    final step = (points.length / 8).ceil().clamp(1, 1000);
    return Column(children: [
      SizedBox(
        height: height,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final p in points)
            Expanded(
              child: Tooltip(
                message: '${p.label}\n${p.violations} violations · ${p.scanned} workers scanned',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Stack(alignment: Alignment.bottomCenter, children: [
                    FractionallySizedBox(
                      heightFactor: p.scanned / maxS * 0.95,
                      child: Container(
                          decoration: BoxDecoration(color: alpha(C.blue, 0.12), borderRadius: BorderRadius.circular(3))),
                    ),
                    FractionallySizedBox(
                      widthFactor: 0.6,
                      heightFactor: p.violations == 0 ? 0.004 : p.violations / maxV * 0.95,
                      child: Container(decoration: BoxDecoration(color: C.orange, borderRadius: BorderRadius.circular(3))),
                    ),
                  ]),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 6),
      Row(children: [
        for (var i = 0; i < points.length; i++)
          Expanded(
            child: Text(i % step == 0 ? points[i].label : '',
                textAlign: TextAlign.center, style: mono(size: 9.5, color: C.dim), overflow: TextOverflow.clip, maxLines: 1),
          ),
      ]),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Container(width: 10, height: 10, color: C.orange),
        const SizedBox(width: 6),
        Text('Violations', style: sans(size: 11.5, color: C.muted)),
        const SizedBox(width: 14),
        Container(width: 10, height: 10, color: alpha(C.blue, 0.35)),
        const SizedBox(width: 6),
        Text('Workers scanned', style: sans(size: 11.5, color: C.muted)),
      ]),
    ]);
  }
}

/// Range chips (today / week / month) used by dashboard and reports.
class RangeChips extends StatelessWidget {
  const RangeChips({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, children: [
        for (final r in const [('today', 'Today'), ('week', 'This Week'), ('month', 'Month')])
          ChoiceChip(
            selected: value == r.$1,
            onSelected: (_) => onChanged(r.$1),
            showCheckmark: false,
            label: Text(r.$2, style: mono(size: 12, weight: FontWeight.w700, color: value == r.$1 ? Colors.white : C.text)),
            selectedColor: C.orange,
            backgroundColor: C.panel,
            side: BorderSide(color: value == r.$1 ? C.orange : C.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
      ]);
}

InputDecoration fieldDecoration(String label, {String? hint, IconData? icon}) => InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: sans(size: 13, color: C.muted),
      hintStyle: sans(size: 13, color: C.dim),
      prefixIcon: icon == null ? null : Icon(icon, size: 19, color: C.muted),
      filled: true,
      fillColor: C.panel2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    );

Future<bool> confirmDialog(BuildContext context, String title, String message, {String action = 'Delete'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.panel,
      title: Text(title, style: sans(size: 17, weight: FontWeight.w700)),
      content: Text(message, style: sans(size: 13.5, color: C.muted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action, style: sans(size: 14, color: C.pink, weight: FontWeight.w600))),
      ],
    ),
  );
  return r == true;
}

/// Small header-row button used in page action bars.
class ActionButton extends StatelessWidget {
  const ActionButton({super.key, required this.label, required this.icon, required this.onPressed, this.primary = false});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) => primary
      ? ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18, color: Colors.white),
          label: Text(label, style: mono(size: 12.5, weight: FontWeight.w700, color: Colors.white)),
          style: ElevatedButton.styleFrom(
              backgroundColor: C.orange,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        )
      : OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18, color: C.text),
          label: Text(label, style: mono(size: 12.5, weight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: C.border),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        );
}

/// Wraps a data table in a panel with horizontal scrolling for narrow windows.
class TablePanel extends StatelessWidget {
  const TablePanel({super.key, required this.table});
  final Widget table;
  @override
  Widget build(BuildContext context) => Panel(
        padding: const EdgeInsets.all(4),
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(constraints: BoxConstraints(minWidth: c.maxWidth), child: table),
          ),
        ),
      );
}

TextStyle get tableHeader => mono(size: 11, color: C.muted, weight: FontWeight.w700);
TextStyle get tableCell => sans(size: 13);
