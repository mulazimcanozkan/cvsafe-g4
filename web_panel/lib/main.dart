// Entry point of the CVSAFE web panel (desktop browser).
// Run from web_panel/:  flutter run -d chrome
import 'package:cvsafe_core/cvsafe_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: CvsafeWebPanelApp()));
}

class CvsafeWebPanelApp extends ConsumerWidget {
  const CvsafeWebPanelApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'CVSAFE Web Panel',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: router,
    );
  }
}
