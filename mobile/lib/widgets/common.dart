import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

class Brand extends StatelessWidget {
  final bool small;
  const Brand({super.key, this.small = false});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('FINAL WHISTLE', style: display(small ? 17 : 21, spacing: 0.5)),
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

/// Tactile press wrapper: scales down + haptic on tap.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final HapticFeedbackType haptic;
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.haptic = HapticFeedbackType.light});
  @override
  State<Pressable> createState() => _PressableState();
}

enum HapticFeedbackType { light, medium, selection }

class _PressableState extends State<Pressable> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 140), value: 1);
  void _fire() {
    switch (widget.haptic) {
      case HapticFeedbackType.medium:
        HapticFeedback.mediumImpact();
        break;
      case HapticFeedbackType.selection:
        HapticFeedback.selectionClick();
        break;
      case HapticFeedbackType.light:
        HapticFeedback.lightImpact();
        break;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _down() => _c.animateTo(0.9, duration: const Duration(milliseconds: 90), curve: Curves.easeOut);
  void _up() => _c.animateTo(1, duration: const Duration(milliseconds: 420), curve: Curves.elasticOut);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap != null ? (_) => _down() : null,
      onTapUp: widget.onTap != null ? (_) => _up() : null,
      onTapCancel: widget.onTap != null ? _up : null,
      onTap: widget.onTap != null
          ? () {
              _fire();
              widget.onTap!();
            }
          : null,
      onLongPress: widget.onLongPress != null
          ? () {
              HapticFeedback.mediumImpact();
              widget.onLongPress!();
            }
          : null,
      child: ScaleTransition(scale: _c, child: widget.child),
    );
  }
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
    final btn = Pressable(
      onTap: busy ? null : onTap,
      haptic: HapticFeedbackType.medium,
      child: Opacity(
        opacity: onTap == null || busy ? 0.55 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.orange,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [BoxShadow(color: Color(0x33E9531E), blurRadius: 14, offset: Offset(0, 6))],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            Text(busy ? 'Working…' : label,
                style: const TextStyle(fontFamily: kBody, color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            if (icon != null) ...[const SizedBox(width: 6), Icon(icon, color: Colors.white, size: 16)],
          ]),
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
    final btn = Pressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: kBody, color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 14)),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// Animated integer that rolls to its new value — used for scores & points.
class AnimatedCount extends StatelessWidget {
  final int value;
  final TextStyle style;
  const AnimatedCount(this.value, {super.key, required this.style});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text('${v.round()}', style: style),
    );
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

/// Smooth slide+fade page transition — makes navigation feel alive.
Route<T> fwrRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
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

/// Minutes until kickoff (negative once started). Big fallback on parse error
/// so a bad timestamp never sneaks into a "kicking off soon" window.
int minutesUntilKickoff(String iso) {
  try {
    return DateTime.parse(iso).difference(DateTime.now()).inMinutes;
  } catch (_) {
    return 1 << 30;
  }
}

/// Human, unambiguous kickoff: "today 21:30", "tomorrow 01:30", "Sat 04:30".
/// A bare clock is confusing for a match days out — this pins the day.
String kickoffWhen(String iso) {
  try {
    final ko = DateTime.parse(iso).toLocal();
    final now = DateTime.now();
    final days = DateTime(ko.year, ko.month, ko.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    final t = '${ko.hour.toString().padLeft(2, '0')}:${ko.minute.toString().padLeft(2, '0')}';
    if (days == 0) return 'today $t';
    if (days == 1) return 'tomorrow $t';
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (days < 7) return '${names[(ko.weekday - 1) % 7]} $t';
    return '${ko.day}/${ko.month} $t';
  } catch (_) {
    return kickoffClock(iso);
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
