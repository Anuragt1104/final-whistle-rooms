import 'package:flutter/material.dart';
import '../theme.dart';
import 'common.dart';

class BottomNav extends StatelessWidget {
  final String active; // rooms | fixtures | inbox | you
  final void Function(String key) onSelect;
  final VoidCallback onCreate;
  const BottomNav({super.key, required this.active, required this.onSelect, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: 8, bottom: MediaQuery.of(context).padding.bottom + 6, left: 8, right: 8),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      // equal-width slots so the centre "+" sits exactly in the middle.
      // Align(heightFactor: 1) centres horizontally WITHOUT expanding to the
      // navbar's unbounded height (plain Center would blow up vertically).
      child: Row(children: [
        Expanded(child: Align(heightFactor: 1, child: _item('rooms', Icons.confirmation_num_outlined, 'Rooms'))),
        Expanded(child: Align(heightFactor: 1, child: _item('fixtures', Icons.grid_view_rounded, 'Fixtures'))),
        Expanded(child: Align(heightFactor: 1, child: _create())),
        Expanded(child: Align(heightFactor: 1, child: _item('inbox', Icons.notifications_none_rounded, 'Inbox'))),
        Expanded(child: Align(heightFactor: 1, child: _item('you', Icons.person_outline_rounded, 'You'))),
      ]),
    );
  }

  Widget _item(String key, IconData icon, String text) {
    final on = active == key;
    return Pressable(
      haptic: HapticFeedbackType.selection,
      onTap: () => onSelect(key),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // active icon springs up a touch
        AnimatedScale(
          scale: on ? 1.18 : 1,
          duration: const Duration(milliseconds: 320),
          curve: Curves.elasticOut,
          child: Icon(icon, size: 22, color: on ? AppColors.orange : AppColors.mut),
        ),
        const SizedBox(height: 3),
        Text(text.toUpperCase(),
            style: label(color: on ? AppColors.orange : AppColors.mut, size: 8.5, weight: FontWeight.w700)),
      ]),
    );
  }

  Widget _create() {
    return Pressable(
      haptic: HapticFeedbackType.medium,
      onTap: onCreate,
      child: Container(
        width: 50,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.orange,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Color(0x33E9531E), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 26),
      ),
    );
  }
}
