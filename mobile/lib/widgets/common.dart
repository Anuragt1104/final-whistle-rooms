import 'package:flutter/material.dart';
import '../theme.dart';

class Brand extends StatelessWidget {
  final bool small;
  const Brand({super.key, this.small = false});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('FINAL WHISTLE', style: display(small ? 18 : 22, spacing: 0.5)),
      const SizedBox(height: 1),
      Text('ROOMS', style: label(color: AppColors.orange, size: small ? 8 : 9.5)),
    ]);
  }
}

class AppChip extends StatelessWidget {
  final String text;
  final Color? color; // text color
  final Color? bg;
  final Widget? leading;
  final VoidCallback? onTap;
  const AppChip(this.text, {super.key, this.color, this.bg, this.leading, this.onTap});
  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg ?? AppColors.cardAlt,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (leading != null) ...[leading!, const SizedBox(width: 5)],
        Text(text, style: label(color: color ?? AppColors.mut, size: 10.5)),
      ]),
    );
    return onTap == null ? child : GestureDetector(onTap: onTap, child: child);
  }
}

class LiveDot extends StatefulWidget {
  final Color color;
  final double size;
  const LiveDot({super.key, this.color = AppColors.orange, this.size = 7});
  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 1.0, end: 0.3).animate(_c),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      );
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool expand;
  final bool busy;
  final IconData? icon;
  const PrimaryButton(this.label, {super.key, this.onTap, this.expand = false, this.busy = false, this.icon});
  @override
  Widget build(BuildContext context) {
    final btn = Opacity(
      opacity: onTap == null || busy ? 0.55 : 1,
      child: Material(
        color: AppColors.orange,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              Text(busy ? 'Working…' : label,
                  style: const TextStyle(
                      fontFamily: kBody, color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              if (icon != null) ...[const SizedBox(width: 6), Icon(icon, color: Colors.white, size: 16)],
            ]),
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

class GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool expand;
  const GhostButton(this.label, {super.key, this.onTap, this.expand = false});
  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
              color: AppColors.cardAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: kBody, color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Row(children: [
          Text(text.toUpperCase(), style: label(color: AppColors.ink, size: 12.5, weight: FontWeight.w800)),
          const Spacer(),
          if (trailing != null) trailing!,
        ]),
      );
}

InputDecoration fwrInput(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: body(color: AppColors.mut, size: 14),
      filled: true,
      fillColor: AppColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.line)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.line)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.orange, width: 1.5)),
    );

Color accentColor(String accent) {
  switch (accent) {
    case 'home':
    case 'good':
      return AppColors.orange;
    case 'away':
    case 'bad':
      return const Color(0xFFD8392B);
    case 'hot':
      return AppColors.gold;
    default:
      return AppColors.ink;
  }
}

/// Round avatar with initials (for chat/members).
class InitialAvatar extends StatelessWidget {
  final String name;
  final double size;
  const InitialAvatar({super.key, required this.name, this.size = 34});
  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).map((w) => w[0]).take(2).join().toUpperCase();
    final colors = [0xFF6A3FA0, 0xFF1F7A3D, 0xFFD8392B, 0xFF1B3A8C, 0xFFEB6A1E, 0xFF0E8C8C];
    var h = 0;
    for (final c in name.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Color(colors[h % colors.length]), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(initials,
          style: TextStyle(fontFamily: kBody, color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.36)),
    );
  }
}

String relativeKickoff(String iso) {
  try {
    final ko = DateTime.parse(iso);
    final diff = ko.difference(DateTime.now());
    final mins = diff.inMinutes;
    if (mins <= 0 && mins > -150) return 'Live window';
    if (mins <= 0) return 'Full-time';
    if (mins < 60) return 'in ${mins}m';
    if (mins < 1440) return 'in ${(mins / 60).round()}h';
    return 'in ${(mins / 1440).round()}d';
  } catch (_) {
    return '';
  }
}

String kickoffClock(String iso) {
  try {
    final ko = DateTime.parse(iso).toLocal();
    return '${ko.hour.toString().padLeft(2, '0')}:${ko.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return '--:--';
  }
}
