// Entry point of the CVSAFE web panel (desktop browser).
// Run:  flutter run -d chrome -t lib/main_panel.dart
import 'package:flutter/material.dart';

import 'login_screen.dart';
import 'panel/panel_shell.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UiPrefs.instance.load(); // language + theme before the first frame
  final state = AppState();
  state.init();
  runApp(AppScope(
    state: state,
    // Rebuild everything when the language or theme changes.
    child: ListenableBuilder(
      listenable: UiPrefs.instance,
      builder: (context, _) => MaterialApp(
        key: ValueKey('${UiPrefs.instance.lang}-${UiPrefs.instance.dark}'),
        title: tx('CVSAFE Web Panel'),
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const _PanelRoot(),
      ),
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
      return LoginScreen(subtitle: tx('Web Panel · site safety management'), wide: true);
    }
    return const PanelShell();
  }
}
