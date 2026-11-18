import 'package:cvsafe_core/cvsafe_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'cameras_page.dart';
import 'dashboard_page.dart';
import 'incidents_page.dart';
import 'login_page.dart';
import 'panel_shell.dart';
import 'people_pages.dart';
import 'state.dart';
import 'zone_editor_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ValueNotifier<int>(0);
  ref.onDispose(refreshNotifier.dispose);

  ref.listen<PanelState>(panelControllerProvider, (prev, next) {
    final prevInitial = prev != null && prev.loading && !prev.everOnline && !prev.needsLogin;
    final nextInitial = next.loading && !next.everOnline && !next.needsLogin;
    if (prev == null ||
        prevInitial != nextInitial ||
        prev.isAuthenticated != next.isAuthenticated ||
        prev.user?.id != next.user?.id ||
        prev.user?.role != next.user?.role) {
      refreshNotifier.value++;
    }
  });

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: refreshNotifier,
    redirect: (context, routerState) {
      final st = ref.read(panelControllerProvider);
      final loc = routerState.matchedLocation;
      final initialLoading = st.loading && !st.everOnline && !st.needsLogin;
      if (initialLoading) {
        return loc == '/loading' ? null : '/loading';
      }
      if (!st.isAuthenticated) {
        return loc == '/login' ? null : '/login';
      }
      if (loc == '/login' || loc == '/loading' || loc == '/') {
        return '/dashboard';
      }
      if (loc.startsWith('/users') && !(st.user?.isAdmin ?? false)) {
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/loading',
        builder: (_, __) => const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginPage(),
      ),
      ShellRoute(
        builder: (context, state, child) => PanelShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (_, __) => const NoTransitionPage(child: DashboardPage()),
          ),
          GoRoute(
            path: '/incidents',
            pageBuilder: (_, __) => const NoTransitionPage(child: IncidentsPage()),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (_, state) => NoTransitionPage(
                  child: IncidentsPage(initialIncidentId: int.tryParse(state.pathParameters['id'] ?? '')),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/cameras',
            pageBuilder: (_, __) => const NoTransitionPage(child: CamerasPage()),
            routes: [
              GoRoute(
                path: ':id/zones',
                pageBuilder: (_, state) {
                  final camId = state.pathParameters['id'] ?? '';
                  return NoTransitionPage(child: _CameraZonesRoute(cameraId: camId));
                },
              ),
            ],
          ),
          GoRoute(
            path: '/subcontractors',
            pageBuilder: (_, __) => const NoTransitionPage(child: SubcontractorsPage()),
          ),
          GoRoute(
            path: '/reports',
            pageBuilder: (_, __) => const NoTransitionPage(child: ReportsPage()),
          ),
          GoRoute(
            path: '/users',
            pageBuilder: (_, __) => const NoTransitionPage(child: UsersPage()),
          ),
        ],
      ),
    ],
  );
});

class _CameraZonesRoute extends ConsumerWidget {
  const _CameraZonesRoute({required this.cameraId});
  final String cameraId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cams = ref.watch(panelControllerProvider).site?.cameras ?? const <Camera>[];
    Camera? cam;
    for (final c in cams) {
      if (c.id == cameraId) {
        cam = c;
        break;
      }
    }
    if (cam == null) {
      return Scaffold(
        body: Center(
          child: EmptyState(
            icon: Icons.videocam_off_outlined,
            title: 'Camera "$cameraId" not found',
            text: 'Return to Cameras & Zones to select an active camera.',
          ),
        ),
      );
    }
    return ZoneEditorPage(camera: cam);
  }
}
