// Mobile-specific widgets bound to [AppState]. Shared, state-free widgets live in cvsafe_core.
import 'package:cvsafe_core/cvsafe_core.dart';
import 'package:flutter/material.dart';

import 'state.dart';

/// Gives every widget access to [AppState] and rebuilds dependants on change.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

// ------------------------------------------------------------------ header
class AppHeader extends StatelessWidget {
  const AppHeader({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final h = st.health;
    final site = st.site;
    return Container(
      color: C.bg,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.orange, width: 2)),
            child: const Icon(Icons.shield_outlined, color: C.orange, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('CVSAFE_101', style: mono(size: 11, color: C.orange, weight: FontWeight.w700)),
                const SizedBox(width: 6),
                Pill('ISG-6331', color: C.muted, small: true),
              ]),
              Text(title, style: sans(size: 21, weight: FontWeight.w700), overflow: TextOverflow.ellipsis),
            ]),
          ),
          Container(
            constraints: const BoxConstraints(maxWidth: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.border)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.apartment, color: C.orange, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('SITE ZONE', style: mono(size: 9, color: C.muted)),
                  Text((site?.name ?? '-').toUpperCase(),
                      style: mono(size: 11, weight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => showSettings(context),
            child: Stack(children: [
              const CircleAvatar(radius: 17, backgroundColor: C.panel2, child: Icon(Icons.person, color: C.muted, size: 20)),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: st.online ? C.green : C.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: C.bg, width: 2)),
                ),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Dot(color: st.online ? C.green : C.yellow),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              st.online
                  ? 'AI ONLINE · ${h?.streamsActive ?? 0} STREAMS · ${(h?.mode ?? '').toUpperCase()}'
                  : st.demo
                      ? 'OFFLINE · DEMO DATA'
                      : 'CONNECTION LOST · LAST SYNC ${st.lastSync == null ? '-' : clock(st.lastSync!)}',
              style: mono(size: 10.5, color: C.muted, weight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.speed, size: 14, color: C.blue),
          const SizedBox(width: 4),
          Text(st.online ? '${(h?.latencyMs ?? 0).round()}ms LATENCY' : 'TAP AVATAR TO CONNECT',
              style: mono(size: 10.5, color: C.blue, weight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    if (st.online) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        color: alpha(C.yellow, 0.08),
        borderColor: alpha(C.yellow, 0.4),
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Icon(Icons.cloud_off, color: C.yellow, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                st.demo
                    ? 'Server not reachable at ${st.serverUrl}. Showing demo data.'
                    : 'Connection lost. Showing alerts from the last sync; retrying every 5 s.',
                style: sans(size: 12.5, color: C.yellow)),
          ),
          TextButton(onPressed: () => showSettings(context), child: Text('SET', style: mono(size: 12, color: C.orange))),
        ]),
      ),
    );
  }
}

// --------------------------------------------------------------- settings
Future<void> showSettings(BuildContext context) {
  final st = AppScope.read(context);
  final ctrl = TextEditingController(text: st.serverUrl);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.panel,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.of(ctx).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Server connection', style: sans(size: 18, weight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
            'Address of the CVSAFE AI server.\n'
            '• Android emulator: http://10.0.2.2:8000\n'
            '• Real phone: http://<computer LAN IP>:8000 (same Wi-Fi)',
            style: sans(size: 12.5, color: C.muted, height: 1.4)),
        const SizedBox(height: 14),
        TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          style: mono(size: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: C.panel2,
            hintText: 'http://192.168.1.20:8000',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 14),
        BigButton(
          label: 'Save & Connect',
          icon: Icons.link,
          onPressed: () async {
            Navigator.of(ctx).pop();
            await st.setServer(ctrl.text);
            if (context.mounted) {
              toast(context, st.online ? 'Connected to ${st.serverUrl}' : 'Could not reach ${st.serverUrl}',
                  error: !st.online);
            }
          },
        ),
        if (st.user != null) ...[
          const SizedBox(height: 18),
          const Divider(color: C.border),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.account_circle_outlined, color: C.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(st.user!.name, style: sans(size: 14, weight: FontWeight.w600)),
                Text('${st.user!.username} · ${st.user!.roleLabel}', style: mono(size: 11, color: C.muted)),
              ]),
            ),
            TextButton.icon(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await st.logout();
              },
              icon: const Icon(Icons.logout, color: C.pink, size: 18),
              label: Text('Sign out', style: sans(size: 13, color: C.pink, weight: FontWeight.w600)),
            ),
          ]),
        ],
      ]),
    ),
  );
}
