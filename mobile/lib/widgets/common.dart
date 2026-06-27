import 'package:flutter/material.dart';
import '../theme.dart';

class Brand extends StatelessWidget {
  final bool small;
  const Brand({super.key, this.small = false});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: small ? 28 : 34,
        height: small ? 28 : 34,
        decoration: BoxDecoration(color: AppColors.lime, borderRadius: BorderRadius.circular(10)),
        alignment: Alignment.center,
        child: const Text('⚽', style: TextStyle(fontSize: 16)),
      ),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('Final Whistle',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: small ? 14 : 16, height: 1)),
        if (!small)
          const Text('ROOMS',
              style: TextStyle(fontSize: 9, letterSpacing: 3, color: AppColors.mut, height: 1.6)),
      ]),
    ]);
  }
}

class AppChip extends StatelessWidget {
  final String text;
  final Color? color;
  final Widget? leading;
  final Color? border;
  final VoidCallback? onTap;
  const AppChip(this.text, {super.key, this.color, this.leading, this.border, this.onTap});
  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: chipDecoration(border: border),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (leading != null) ...[leading!, const SizedBox(width: 5)],
        Text(text,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: color ?? AppColors.mut)),
      ]),
    );
    return onTap == null ? child : GestureDetector(onTap: onTap, child: child);
  }
}

class LiveDot extends StatefulWidget {
  final Color color;
  final double size;
  const LiveDot({super.key, this.color = AppColors.lime, this.size = 7});
  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.3).animate(_c),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool expand;
  final bool busy;
  const PrimaryButton(this.label, {super.key, this.onTap, this.expand = false, this.busy = false});
  @override
  Widget build(BuildContext context) {
    final btn = Opacity(
      opacity: onTap == null || busy ? 0.6 : 1,
      child: Material(
        color: AppColors.lime,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Text(busy ? 'Working…' : label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF0A1320), fontWeight: FontWeight.w700, fontSize: 15)),
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
      color: const Color(0x80243650),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13), border: Border.all(color: AppColors.line)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.mut)),
      );
}

InputDecoration fwrInput(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.mut),
      filled: true,
      fillColor: const Color(0x99070B14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.line)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.line)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.lime)),
    );

Color accentColor(String accent) {
  switch (accent) {
    case 'home':
      return AppColors.home;
    case 'away':
      return AppColors.away;
    case 'hot':
      return AppColors.gold;
    case 'good':
      return AppColors.lime;
    case 'bad':
      return AppColors.away;
    default:
      return AppColors.line;
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
