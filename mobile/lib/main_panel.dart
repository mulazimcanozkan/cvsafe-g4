// Entry point of the CVSAFE web panel (desktop browser).
// Run:  flutter run -d chrome -t lib/main_panel.dart
import 'package:flutter/material.dart';

import 'login_screen.dart';
import 'panel/panel_shell.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  state.init();
  runApp(AppScope(
    state: state,
    child: MaterialApp(
      title: 'CVSAFE Web Panel',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const _PanelRoot(),
    ),
  ));
}

class _PanelRoot extends StatelessWidget {
  const _PanelRoot();

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    if (st.loading && !st.everOnline && !st.needsLogin) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // the panel manages real data only: no demo mode, sign-in is always required
    if (st.needsLogin || st.user == null || st.demo) {
      return const LoginScreen(subtitle: 'Web Panel · site safety management', wide: true);
    }
    return const PanelShell();
  }
}
