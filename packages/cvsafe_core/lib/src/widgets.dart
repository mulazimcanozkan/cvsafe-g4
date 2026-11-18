import 'package:flutter/material.dart';

import 'theme.dart';

// State-free UI building blocks shared by the mobile app and the web panel.

/// Shows a short floating message at the bottom of the screen.
void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: sans(size: 13, color: error ? C.pink : C.text)),
    duration: const Duration(seconds: 3),
  ));
}

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
        child: Material(type: MaterialType.transparency, child: child),
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
