import 'dart:async';

import 'package:cvsafe_core/cvsafe_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'common.dart';
import 'incidents_page.dart';
import 'state.dart';

class _NavItem {
  const _NavItem(this.key, this.path, this.label, this.icon, {this.adminOnly = false});
  final String key;
  final String path;
  final String label;
  final IconData icon;
  final bool adminOnly;
}

const _nav = [
  _NavItem('dashboard', '/dashboard', 'Dashboard', Icons.space_dashboard_outlined),
  _NavItem('incidents', '/incidents', 'Incidents', Icons.notifications_none),
  _NavItem('cameras', '/cameras', 'Cameras & Zones', Icons.videocam_outlined),
  _NavItem('subcontractors', '/subcontractors', 'Subcontractors', Icons.business_outlined),
  _NavItem('reports', '/reports', 'Reports', Icons.description_outlined),
  _NavItem('users', '/users', 'Users', Icons.manage_accounts_outlined, adminOnly: true),
];

/// Desktop layout of the web panel: side navigation + routed page content.
class PanelShell extends ConsumerStatefulWidget {
  const PanelShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;
  @override
  ConsumerState<PanelShell> createState() => _PanelShellState();
}

class _PanelShellState extends ConsumerState<PanelShell> {
  StreamSubscription<Incident>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(panelControllerProvider.notifier).newAlerts.listen(_onNewAlert);
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

  String get _activeKey {
    final loc = widget.location;
    if (loc.startsWith('/incidents')) return 'incidents';
    if (loc.startsWith('/cameras')) return 'cameras';
    if (loc.startsWith('/subcontractors')) return 'subcontractors';
    if (loc.startsWith('/reports')) return 'reports';
    if (loc.startsWith('/users')) return 'users';
    return 'dashboard';
  }

  Future<void> _changeOwnPassword() async {
    final st = ref.read(panelControllerProvider);
    final ctrl = ref.read(panelControllerProvider.notifier);
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.panel,
        title: Text('Change password', style: sans(size: 17, weight: FontWeight.w700)),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: pass,
            obscureText: true,
            decoration: fieldDecoration('New password (min 6)', icon: Icons.lock_outline),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Update', style: sans(size: 14, color: C.orange, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    final newPass = pass.text;
    if (ok != true) return;
    try {
      await st.api.changeOwnPassword(newPass);
      if (mounted) toast(context, 'Password changed. Please sign in again.');
      await ctrl.logout();
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(panelControllerProvider);
    final ctrl = ref.read(panelControllerProvider.notifier);
    final items = _nav.where((n) => !n.adminOnly || (st.user?.isAdmin ?? false)).toList();
    final activeKey = _activeKey;
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
                    color: activeKey == n.key ? alpha(C.orange, 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => context.go(n.path),
                      child: Tooltip(
                        message: extended ? '' : n.label,
                        child: Container(
                          height: 44,
                          padding: EdgeInsets.symmetric(horizontal: extended ? 12 : 0),
                          child: Row(
                              mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center,
                              children: [
                                Stack(clipBehavior: Clip.none, children: [
                                  Icon(n.icon, color: activeKey == n.key ? C.orange : C.muted, size: 21),
                                  if (n.key == 'incidents' && st.openIncidents.isNotEmpty)
                                    const Positioned(right: -6, top: -5, child: Dot(color: C.red, size: 9)),
                                ]),
                                if (extended) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(n.label,
                                        style: sans(
                                            size: 13.5,
                                            weight: FontWeight.w600,
                                            color: activeKey == n.key ? C.orange : C.text)),
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
                    const CircleAvatar(
                        radius: 16, backgroundColor: C.panel2, child: Icon(Icons.person, size: 18, color: C.muted)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(st.user?.name ?? '',
                            style: sans(size: 13, weight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                        Text(st.user?.roleLabel ?? '', style: mono(size: 10, color: C.muted)),
                      ]),
                    ),
                    IconButton(
                      tooltip: 'Change password',
                      icon: const Icon(Icons.key_outlined, color: C.muted, size: 18),
                      onPressed: _changeOwnPassword,
                    ),
                  ],
                  IconButton(
                      tooltip: 'Sign out',
                      icon: const Icon(Icons.logout, color: C.pink, size: 20),
                      onPressed: ctrl.logout),
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
              Expanded(child: widget.child),
            ]),
          ),
        ]);
      }),
    );
  }
}
