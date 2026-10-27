import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'cameras_page.dart';
import 'dashboard_page.dart';
import 'incidents_page.dart';
import 'people_pages.dart';

class _NavItem {
  const _NavItem(this.key, this.label, this.icon, {this.adminOnly = false});
  final String key;
  final String label;
  final IconData icon;
  final bool adminOnly;
}

const _nav = [
  _NavItem('dashboard', 'Dashboard', Icons.space_dashboard_outlined),
  _NavItem('incidents', 'Incidents', Icons.notifications_none),
  _NavItem('cameras', 'Cameras & Zones', Icons.videocam_outlined),
  _NavItem('subcontractors', 'Subcontractors', Icons.business_outlined),
  _NavItem('reports', 'Reports', Icons.description_outlined),
  _NavItem('users', 'Users', Icons.manage_accounts_outlined, adminOnly: true),
];

/// Desktop layout of the web panel: side navigation + page.
class PanelShell extends StatefulWidget {
  const PanelShell({super.key});
  @override
  State<PanelShell> createState() => _PanelShellState();
}

class _PanelShellState extends State<PanelShell> {
  String page = 'dashboard';
  StreamSubscription<Incident>? _sub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub ??= AppScope.read(context).newAlerts.listen(_onNewAlert);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onNewAlert(Incident inc) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      width: 460,
      backgroundColor: inc.isCritical ? C.redDark : C.panel2,
      content: Text('New ${inc.severity} alert · ${inc.cameraId ?? 'upload'}: ${inc.title}',
          style: sans(size: 13.5, color: Colors.white, weight: FontWeight.w600)),
      action: SnackBarAction(label: 'OPEN', textColor: C.orange, onPressed: () => showIncidentDialog(context, inc)),
    ));
  }

  Widget _page() {
    switch (page) {
      case 'incidents':
        return const IncidentsPage();
      case 'cameras':
        return const CamerasPage();
      case 'subcontractors':
        return const SubcontractorsPage();
      case 'reports':
        return const ReportsPage();
      case 'users':
        return const UsersPage();
      default:
        return DashboardPage(
          onOpenIncident: (i) => showIncidentDialog(context, i),
          onGoto: (p) => setState(() => page = p),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final items = _nav.where((n) => !n.adminOnly || (st.user?.isAdmin ?? false)).toList();
    if (!items.any((n) => n.key == page)) page = 'dashboard';
    final h = st.health;
    return Scaffold(
      body: LayoutBuilder(builder: (context, c) {
        final extended = c.maxWidth > 1100;
        return Row(children: [
          Container(
            width: extended ? 240 : 76,
            decoration: const BoxDecoration(color: C.panel, border: Border(right: BorderSide(color: C.border))),
            child: Column(children: [
              const SizedBox(height: 18),
              Row(mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center, children: [
                if (extended) const SizedBox(width: 18),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.orange, width: 2)),
                  child: const Icon(Icons.shield_outlined, color: C.orange, size: 20),
                ),
                if (extended) ...[
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('CVSAFE', style: mono(size: 16, weight: FontWeight.w800, color: C.orange)),
                    Text('Web Panel', style: sans(size: 11.5, color: C.muted)),
                  ]),
                ],
              ]),
              const SizedBox(height: 24),
              for (final n in items)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  child: Material(
                    color: page == n.key ? alpha(C.orange, 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => page = n.key),
                      child: Tooltip(
                        message: extended ? '' : n.label,
                        child: Container(
                          height: 44,
                          padding: EdgeInsets.symmetric(horizontal: extended ? 12 : 0),
                          child: Row(
                              mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center,
                              children: [
                                Stack(clipBehavior: Clip.none, children: [
                                  Icon(n.icon, color: page == n.key ? C.orange : C.muted, size: 21),
                                  if (n.key == 'incidents' && st.openIncidents.isNotEmpty)
                                    Positioned(right: -6, top: -5, child: Dot(color: C.red, size: 9)),
                                ]),
                                if (extended) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(n.label,
                                        style: sans(
                                            size: 13.5,
                                            weight: FontWeight.w600,
                                            color: page == n.key ? C.orange : C.text)),
                                  ),
                                  if (n.key == 'incidents' && st.openIncidents.isNotEmpty)
                                    Pill('${st.openIncidents.length}', color: C.red, small: true),
                                ],
                              ]),
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              if (extended)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                  child: Row(children: [
                    Dot(color: st.online ? C.green : C.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(st.online ? 'AI online · ${(h?.latencyMs ?? 0).round()} ms' : 'Server offline',
                          style: mono(size: 10.5, color: C.muted)),
                    ),
                  ]),
                ),
              const Divider(color: C.border, height: 1),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center, children: [
                  if (extended) ...[
                    const CircleAvatar(radius: 16, backgroundColor: C.panel2, child: Icon(Icons.person, size: 18, color: C.muted)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(st.user?.name ?? '', style: sans(size: 13, weight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                        Text(st.user?.roleLabel ?? '', style: mono(size: 10, color: C.muted)),
                      ]),
                    ),
                  ],
                  IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout, color: C.pink, size: 20), onPressed: st.logout),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: Column(children: [
              if (!st.online)
                Container(
                  width: double.infinity,
                  color: alpha(C.yellow, 0.12),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text('Connection to the server lost · showing the last synced data, retrying every 5 s',
                      style: sans(size: 12.5, color: C.yellow)),
                ),
              Expanded(child: KeyedSubtree(key: ValueKey(page), child: _page())),
            ]),
          ),
        ]);
      }),
    );
  }
}
