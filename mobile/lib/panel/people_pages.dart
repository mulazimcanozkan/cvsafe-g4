import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';

// ======================================================== Subcontractors
class SubcontractorsPage extends StatelessWidget {
  const SubcontractorsPage({super.key});

  Future<void> _edit(BuildContext context, {Subcontractor? sub}) async {
    final st = AppScope.read(context);
    final name = TextEditingController(text: sub?.name ?? '');
    final trade = TextEditingController(text: sub?.trade ?? '');
    final workers = TextEditingController(text: sub == null ? '' : '${sub.workers}');
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: C.panel,
          title: Text(tx(sub == null ? 'Add subcontractor' : 'Edit subcontractor'), style: sans(size: 17, weight: FontWeight.w700)),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: fieldDecoration('Company name', icon: Icons.business_outlined)),
              const SizedBox(height: 10),
              TextField(controller: trade, decoration: fieldDecoration('Trade', hint: tx('Scaffolding'), icon: Icons.construction)),
              const SizedBox(height: 10),
              TextField(
                controller: workers,
                keyboardType: TextInputType.number,
                decoration: fieldDecoration('Workers on site', icon: Icons.groups_outlined),
              ),
              if (error != null) ...[const SizedBox(height: 10), Text(tx(error!), style: sans(size: 12.5, color: C.pink))],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx('Cancel'))),
            TextButton(
              onPressed: () async {
                try {
                  await st.api.saveSubcontractor(
                      id: sub?.id, name: name.text.trim(), trade: trade.text.trim(), workers: int.tryParse(workers.text.trim()) ?? 0);
                  await st.reloadSite();
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  setD(() => error = e.toString());
                }
              },
              child: Text(tx('Save'), style: sans(size: 14, color: C.orange, weight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final canEdit = st.user?.canManage ?? false;
    final subs = st.site?.subcontractors ?? const <Subcontractor>[];
    final cams = st.site?.cameras ?? const <Camera>[];
    return PanelPage(
      title: tx('Subcontractors'),
      subtitle: tx('Companies responsible for each camera area; used in alerts and compliance rankings'),
      actions: [
        if (canEdit) ActionButton(label: tx('Add Subcontractor'), icon: Icons.add, primary: true, onPressed: () => _edit(context)),
      ],
      children: [
        if (subs.isEmpty) EmptyState(icon: Icons.business_outlined, title: tx('No subcontractors yet')),
        if (subs.isNotEmpty)
          TablePanel(
            table: DataTable(
              columns: [
                DataColumn(label: Text(tx('COMPANY'), style: tableHeader)),
                DataColumn(label: Text(tx('TRADE'), style: tableHeader)),
                DataColumn(label: Text(tx('WORKERS'), style: tableHeader), numeric: true),
                DataColumn(label: Text(tx('CAMERAS'), style: tableHeader)),
                DataColumn(label: Text(tx(''), style: tableHeader)),
              ],
              rows: [
                for (final s in subs)
                  DataRow(cells: [
                    DataCell(Text(tx(s.name), style: tableCell.copyWith(fontWeight: FontWeight.w600))),
                    DataCell(Text(tx(s.trade.isEmpty ? '-' : s.trade), style: tableCell)),
                    DataCell(Text(tx('${s.workers}'), style: mono(size: 12.5))),
                    DataCell(Text(
                        tx(cams.where((c) => c.subcontractorId == s.id).map((c) => c.id).join(', ').isEmpty
                            ? '-'
                            : cams.where((c) => c.subcontractorId == s.id).map((c) => c.id).join(', ')),
                        style: mono(size: 12))),
                    DataCell(canEdit
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _edit(context, sub: s)),
                            IconButton(
                              icon: Icon(Icons.delete_outline, size: 18, color: C.pink),
                              onPressed: () async {
                                if (!await confirmDialog(context, 'Delete ${s.name}?',
                                    'Cameras assigned to this company become unassigned.')) {
                                  return;
                                }
                                try {
                                  await st.api.deleteSubcontractor(s.id);
                                  await st.reloadSite();
                                } catch (e) {
                                  if (context.mounted) toast(context, e.toString(), error: true);
                                }
                              },
                            ),
                          ])
                        : const SizedBox.shrink()),
                  ]),
              ],
            ),
          ),
      ],
    );
  }
}

// ================================================================ Users
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<UserInfo> users = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final u = await AppScope.read(context).api.users();
      if (mounted) setState(() => users = u);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _add() async {
    final st = AppScope.read(context);
    final uname = TextEditingController();
    final name = TextEditingController();
    final pass = TextEditingController();
    var role = 'field';
    String? err;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: C.panel,
          title: Text(tx('Add user'), style: sans(size: 17, weight: FontWeight.w700)),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: fieldDecoration('Full name', icon: Icons.badge_outlined)),
              const SizedBox(height: 10),
              TextField(controller: uname, decoration: fieldDecoration('Username', hint: tx('gorkem'), icon: Icons.person_outline)),
              const SizedBox(height: 10),
              TextField(
                  controller: pass, obscureText: true, decoration: fieldDecoration('Password (min 6)', icon: Icons.lock_outline)),
              const SizedBox(height: 10),
              InputDecorator(
                decoration: fieldDecoration('Role', icon: Icons.admin_panel_settings_outlined)
                    .copyWith(contentPadding: const EdgeInsets.fromLTRB(0, 4, 8, 4)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: role,
                    isExpanded: true,
                    dropdownColor: C.panel2,
                    items: [
                      DropdownMenuItem(value: 'field', child: Text(tx('Site Manager (mobile app)'))),
                      DropdownMenuItem(value: 'ohs', child: Text(tx('OHS Specialist (zones, reports)'))),
                      DropdownMenuItem(value: 'admin', child: Text(tx('Administrator (everything)'))),
                    ],
                    onChanged: (v) => setD(() => role = v ?? 'field'),
                  ),
                ),
              ),
              if (err != null) ...[const SizedBox(height: 10), Text(tx(err!), style: sans(size: 12.5, color: C.pink))],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx('Cancel'))),
            TextButton(
              onPressed: () async {
                try {
                  await st.api.createUser(uname.text.trim(), name.text.trim(), role, pass.text);
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                } catch (e) {
                  setD(() => err = e.toString());
                }
              },
              child: Text(tx('Create'), style: sans(size: 14, color: C.orange, weight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _password(UserInfo u) async {
    final st = AppScope.read(context);
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.panel,
        title: Text(tx('New password for ${u.username}'), style: sans(size: 17, weight: FontWeight.w700)),
        content: SizedBox(
          width: 380,
          child: TextField(controller: pass, obscureText: true, decoration: fieldDecoration('New password (min 6)')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tx('Cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tx('Set password'), style: sans(size: 14, color: C.orange, weight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (u.id == st.user?.id) {
        await st.api.changeOwnPassword(pass.text);
        if (mounted) toast(context, 'Password changed. Please sign in again.');
        await st.logout();
      } else {
        await st.api.resetPassword(u.id, pass.text);
        if (mounted) toast(context, 'Password updated; ${u.username} must sign in again.');
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _delete(UserInfo u) async {
    final st = AppScope.read(context);
    if (!await confirmDialog(context, 'Delete ${u.username}?', 'This user can no longer sign in.')) return;
    try {
      await st.api.deleteUser(u.id);
      await _load();
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    return PanelPage(
      title: tx('Users'),
      subtitle: tx('Who can sign in to the web panel and the mobile app'),
      actions: [ActionButton(label: tx('Add User'), icon: Icons.person_add_alt, primary: true, onPressed: _add)],
      children: [
        if (loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        if (error != null) Text(tx(error!), style: sans(size: 13, color: C.pink)),
        if (!loading && users.isNotEmpty)
          TablePanel(
            table: DataTable(
              columns: [
                DataColumn(label: Text(tx('NAME'), style: tableHeader)),
                DataColumn(label: Text(tx('USERNAME'), style: tableHeader)),
                DataColumn(label: Text(tx('ROLE'), style: tableHeader)),
                DataColumn(label: Text(tx(''), style: tableHeader)),
              ],
              rows: [
                for (final u in users)
                  DataRow(cells: [
                    DataCell(Text(tx(u.name + (u.id == st.user?.id ? '  (you)' : '')),
                        style: tableCell.copyWith(fontWeight: FontWeight.w600))),
                    DataCell(Text(tx(u.username), style: mono(size: 12.5))),
                    DataCell(Pill(u.roleLabel.toUpperCase(),
                        color: u.role == 'admin' ? C.orange : (u.role == 'ohs' ? C.blue : C.green), small: true)),
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(tooltip: tx('Set password'), icon: const Icon(Icons.key_outlined, size: 18), onPressed: () => _password(u)),
                      if (u.id != st.user?.id)
                        IconButton(
                            tooltip: tx('Delete'),
                            icon: Icon(Icons.delete_outline, size: 18, color: C.pink),
                            onPressed: () => _delete(u)),
                    ])),
                  ]),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Text(
          tx('Site Managers use the mobile app (alerts, AI scan). OHS Specialists also edit zones and subcontractors. '
          'Administrators additionally manage cameras and users.'),
          style: sans(size: 12.5, color: C.muted),
        ),
      ],
    );
  }
}

// ============================================================== Reports
class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final range = st.analyticsRange;
    final a = st.analytics[range];
    if (a == null && !st.analyticsLoading && st.analyticsError == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (st.analytics[st.analyticsRange] == null && !st.analyticsLoading) st.loadAnalytics(st.analyticsRange);
      });
    }
    return PanelPage(
      title: tx('Reports'),
      subtitle: tx('Compliance summary for audits (OHS Law No. 6331, KVKK)'),
      actions: [
        RangeChips(value: range, onChanged: st.loadAnalytics),
        ActionButton(
          label: tx('Open PDF Report'),
          icon: Icons.picture_as_pdf_outlined,
          primary: true,
          onPressed: () async {
            final ok = await launchUrl(Uri.parse(st.api.reportUrl(range)), mode: LaunchMode.externalApplication);
            if (!ok && context.mounted) toast(context, 'Could not open the report', error: true);
          },
        ),
      ],
      children: [
        if (a == null)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
        else ...[
          Wrap(spacing: 12, runSpacing: 12, children: [
            KpiCard(label: tx('COMPLIANCE'), value: '${a.complianceIndex.round()}%', sub: 'Grade ${a.grade}', icon: Icons.verified_outlined, color: C.green),
            KpiCard(label: tx('VIOLATIONS'), value: '${a.violations}', sub: 'excluding false alarms', icon: Icons.warning_amber_rounded, color: C.red),
            KpiCard(
                label: tx('FALSE ALARMS'),
                value: a.falseAlarmRate == null ? '-' : '${(a.falseAlarmRate! * 100).round()}%',
                sub: 'AI feedback loop',
                icon: Icons.feedback_outlined,
                color: C.muted),
            KpiCard(
                label: tx('MEAN RESPONSE'),
                value: a.mttrSeconds == null ? '-' : '${a.mttrSeconds! ~/ 60}m ${a.mttrSeconds! % 60}s',
                icon: Icons.timer_outlined,
                color: C.yellow),
          ]),
          const SizedBox(height: 16),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionTitle('Violation breakdown', icon: Icons.pie_chart_outline),
              if (a.breakdown.isEmpty) Text(tx('No violations in this period.'), style: sans(size: 13, color: C.muted)),
              if (a.breakdown.isNotEmpty)
                SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
                  columns: [
                    DataColumn(label: Text(tx('VIOLATION'), style: tableHeader)),
                    DataColumn(label: Text(tx('COUNT'), style: tableHeader), numeric: true),
                    DataColumn(label: Text(tx('SHARE'), style: tableHeader), numeric: true),
                    DataColumn(label: Text(tx('MOST FREQUENT LOCATION'), style: tableHeader)),
                  ],
                  rows: [
                    for (final b in a.breakdown)
                      DataRow(cells: [
                        DataCell(Text(tx(b.title), style: tableCell)),
                        DataCell(Text(tx('${b.count}'), style: mono(size: 12.5))),
                        DataCell(Text(tx('${(b.share * 100).round()}%'), style: mono(size: 12.5))),
                        DataCell(Text(tx(b.topLocation), style: tableCell)),
                      ]),
                  ],
                )),
            ]),
          ),
          const SizedBox(height: 16),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionTitle('Subcontractor compliance', icon: Icons.groups_outlined),
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
                columns: [
                  DataColumn(label: Text(tx('SUBCONTRACTOR'), style: tableHeader)),
                  DataColumn(label: Text(tx('TRADE'), style: tableHeader)),
                  DataColumn(label: Text(tx('COMPLIANCE'), style: tableHeader), numeric: true),
                  DataColumn(label: Text(tx('INCIDENTS'), style: tableHeader), numeric: true),
                ],
                rows: [
                  for (final l in a.leaderboard)
                    DataRow(cells: [
                      DataCell(Text(tx(l.name), style: tableCell)),
                      DataCell(Text(tx(l.trade), style: tableCell)),
                      DataCell(Text(tx(l.compliance == null ? '-' : '${l.compliance!.round()}%'),
                          style: mono(size: 12.5, color: l.status == 'warning' ? C.red : C.text))),
                      DataCell(Text(tx('${l.incidents}'), style: mono(size: 12.5))),
                    ]),
                ],
              )),
            ]),
          ),
        ],
      ],
    );
  }
}
