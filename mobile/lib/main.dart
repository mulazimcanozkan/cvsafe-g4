import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'login_screen.dart';
import 'models.dart';
import 'screens/alerts_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/evidence_screen.dart';
import 'screens/live_screen.dart';
import 'screens/scan_screen.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  state.init();
  runApp(CvsafeApp(state: state));
}

class CvsafeApp extends StatelessWidget {
  const CvsafeApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'CVSAFE',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const _Root(),
      ),
    );
  }
}

/// Login screen when the server asks for a session, otherwise the app.
class _Root extends StatelessWidget {
  const _Root();
  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    return st.needsLogin ? const LoginScreen() : const HomeShell();
  }
}

class _Tab {
  const _Tab(this.label, this.icon, this.title);
  final String label;
  final IconData icon;
  final String title;
}

const _tabs = [
  _Tab('Alerts', Icons.notifications_none, 'Alerts'),
  _Tab('Evidence', Icons.verified_user_outlined, 'Evidence'),
  _Tab('AI Scan', Icons.document_scanner_outlined, 'AI Scan'),
  _Tab('Live CCTV', Icons.videocam_outlined, 'Live CCTV'),
  _Tab('Analytics', Icons.insert_chart_outlined, 'Analytics'),
];

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  StreamSubscription<Incident>? _sub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub ??= AppScope.read(context).newAlerts.listen(_onNewAlert);
  }

  void _onNewAlert(Incident inc) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    final st = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      backgroundColor: inc.isCritical ? C.redDark : C.panel2,
      content: Row(children: [
        Icon(Icons.warning_amber_rounded, color: inc.isCritical ? Colors.white : C.orange),
        const SizedBox(width: 10),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('NEW ${inc.severity.toUpperCase()} ALERT · ${inc.cameraId ?? 'UPLOAD'}',
                style: mono(size: 10.5, weight: FontWeight.w700, color: Colors.white)),
            Text(inc.title, style: sans(size: 13.5, weight: FontWeight.w600, color: Colors.white)),
          ]),
        ),
      ]),
      action: SnackBarAction(label: 'VIEW', textColor: C.orange, onPressed: () => st.openEvidence(inc.id)),
    ));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final tab = st.tab;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          AppHeader(title: _tabs[tab].title),
          Expanded(
            child: IndexedStack(index: tab, children: const [
              AlertsScreen(),
              EvidenceScreen(),
              ScanScreen(),
              LiveScreen(),
              AnalyticsScreen(),
            ]),
          ),
        ]),
      ),
      bottomNavigationBar: _BottomBar(
        index: tab,
        alertCount: st.openIncidents.length,
        onTap: (i) {
          st.setTab(i);
          if (i == 4) st.loadAnalytics(st.analyticsRange); // fresh numbers each visit
        },
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.index, required this.onTap, required this.alertCount});
  final int index;
  final ValueChanged<int> onTap;
  final int alertCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: C.bg, border: Border(top: BorderSide(color: C.border))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(children: [
            for (var i = 0; i < _tabs.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Stack(clipBehavior: Clip.none, children: [
                      Icon(_tabs[i].icon, color: i == index ? C.orange : C.muted, size: i == 2 ? 27 : 24),
                      if (i == 0 && alertCount > 0)
                        Positioned(
                          right: -8,
                          top: -6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: C.red, borderRadius: BorderRadius.circular(10)),
                            child: Text('$alertCount', style: mono(size: 10, color: Colors.white, weight: FontWeight.w800)),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 4),
                    Text(_tabs[i].label,
                        style: sans(size: 11, color: i == index ? C.orange : C.muted, weight: FontWeight.w600)),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
