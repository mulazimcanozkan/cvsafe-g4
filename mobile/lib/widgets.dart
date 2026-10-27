import 'package:flutter/material.dart';

import 'state.dart';
import 'theme.dart';

/// Gives every widget access to [AppState] and rebuilds dependants on change.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

// ------------------------------------------------------------------ helpers
String timeAgo(double ts) {
  final s = (DateTime.now().millisecondsSinceEpoch / 1000 - ts).round();
  if (s < 0) return 'now';
  if (s < 60) return '${s}s ago';
  if (s < 3600) return '${s ~/ 60}m ago';
  if (s < 86400) return '${s ~/ 3600}h ago';
  return '${s ~/ 86400}d ago';
}

String clock(double ts) {
  final d = DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

String dateTime(double ts) {
  final d = DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: sans(size: 13, color: error ? C.pink : C.text)),
    duration: const Duration(seconds: 3),
  ));
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

// ----------------------------------------------------------------- pieces
class Dot extends StatelessWidget {
  const Dot({super.key, required this.color, this.size = 8});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color, this.filled = false, this.small = false, this.icon});
  final String text;
  final Color color;
  final bool filled;
  final bool small;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 9, vertical: small ? 2 : 4),
      decoration: BoxDecoration(
        color: filled ? color : alpha(color, 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: alpha(color, filled ? 1 : 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: small ? 11 : 13, color: filled ? Colors.white : color), const SizedBox(width: 4)],
        Text(text,
            style: mono(size: small ? 9 : 10.5, color: filled ? Colors.white : color, weight: FontWeight.w700)),
      ]),
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color, this.borderColor});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? C.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor ?? C.border),
        ),
        child: child,
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.icon, this.trailing});
  final String text;
  final IconData? icon;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, color: C.orange, size: 18), const SizedBox(width: 8)],
          Expanded(child: Text(text, style: sans(size: 16, weight: FontWeight.w700))),
          if (trailing != null) trailing!,
        ]),
      );
}

class BigButton extends StatelessWidget {
  const BigButton({super.key, required this.label, required this.onPressed, this.icon, this.color = C.orange,
      this.textColor = Colors.white, this.outlined = false, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final Color textColor;
  final bool outlined;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: textColor))
        : Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 18, color: outlined ? color : textColor), const SizedBox(width: 8)],
            Flexible(
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: mono(size: 13, weight: FontWeight.w700, color: outlined ? color : textColor)),
            ),
          ]);
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: outlined
          ? OutlinedButton(
              onPressed: busy ? null : onPressed,
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: alpha(color, 0.5)),
                  backgroundColor: alpha(color, 0.06),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: child)
          : ElevatedButton(
              onPressed: busy ? null : onPressed,
              style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  disabledBackgroundColor: alpha(color, 0.4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: child),
    );
  }
}

/// Network image with a placeholder for incidents that have no snapshot.
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.height = 200, this.fit = BoxFit.cover, this.radius = 10});
  final String? url;
  final double height;
  final BoxFit fit;
  final double radius;

  @override
  Widget build(BuildContext context) {
    Widget placeholder(String text, IconData icon) => Container(
          height: height,
          color: C.panel2,
          alignment: Alignment.center,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: C.dim, size: 30),
            const SizedBox(height: 6),
            Text(text, style: mono(size: 11, color: C.dim)),
          ]),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url == null
          ? placeholder('NO SNAPSHOT STORED', Icons.image_not_supported_outlined)
          : Image.network(
              url!,
              height: height,
              width: double.infinity,
              fit: fit,
              gaplessPlayback: true,
              loadingBuilder: (c, child, p) => p == null ? child : placeholder('LOADING...', Icons.hourglass_top),
              errorBuilder: (c, e, s) => placeholder('IMAGE UNAVAILABLE', Icons.broken_image_outlined),
            ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.label, required this.value, this.sub, this.valueColor});
  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.panel2, borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: C.muted),
          const SizedBox(width: 10),
          SizedBox(width: 92, child: Text(label, style: sans(size: 13, color: C.muted))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(value,
                  textAlign: TextAlign.right,
                  style: mono(size: 12.5, weight: FontWeight.w700, color: valueColor ?? C.text)),
              if (sub != null)
                Text(sub!, textAlign: TextAlign.right, style: mono(size: 10, color: C.blue, weight: FontWeight.w600)),
            ]),
          ),
        ]),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.text});
  final IconData icon;
  final String title;
  final String? text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(children: [
          Icon(icon, size: 44, color: C.dim),
          const SizedBox(height: 12),
          Text(title, style: sans(size: 16, weight: FontWeight.w600), textAlign: TextAlign.center),
          if (text != null) ...[
            const SizedBox(height: 6),
            Text(text!, style: sans(size: 13, color: C.muted), textAlign: TextAlign.center),
          ],
        ]),
      );
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
