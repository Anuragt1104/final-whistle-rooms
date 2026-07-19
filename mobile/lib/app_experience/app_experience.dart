import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

enum AppDestination {
  home('Home', 'assets/nav/home.svg'),
  fixtures('Fixtures', 'assets/nav/fixtures.svg'),
  cards('Cards', 'assets/nav/cards.svg'),
  arena('Arena', 'assets/nav/arena.svg'),
  profile('Profile', 'assets/nav/profile.svg');

  final String label;
  final String asset;
  const AppDestination(this.label, this.asset);
}

@immutable
class AppShellState {
  final AppDestination destination;
  final int notificationCount;
  final int liveMatchCount;
  final int unopenedPackCount;
  final int duelInviteCount;
  final bool connected;

  const AppShellState({
    required this.destination,
    required this.notificationCount,
    required this.liveMatchCount,
    required this.unopenedPackCount,
    required this.duelInviteCount,
    required this.connected,
  });

  const AppShellState.initial()
    : destination = AppDestination.home,
      notificationCount = 0,
      liveMatchCount = 0,
      unopenedPackCount = 0,
      duelInviteCount = 0,
      connected = true;

  int badgeFor(AppDestination destination) => switch (destination) {
    AppDestination.home => liveMatchCount + notificationCount,
    AppDestination.cards => unopenedPackCount,
    AppDestination.arena => duelInviteCount,
    AppDestination.fixtures || AppDestination.profile => 0,
  };

  AppShellState copyWith({
    AppDestination? destination,
    int? notificationCount,
    int? liveMatchCount,
    int? unopenedPackCount,
    int? duelInviteCount,
    bool? connected,
  }) => AppShellState(
    destination: destination ?? this.destination,
    notificationCount: notificationCount ?? this.notificationCount,
    liveMatchCount: liveMatchCount ?? this.liveMatchCount,
    unopenedPackCount: unopenedPackCount ?? this.unopenedPackCount,
    duelInviteCount: duelInviteCount ?? this.duelInviteCount,
    connected: connected ?? this.connected,
  );
}

/// Owns global destination and badge state. Screens only learn this interface;
/// deep-link parsing, inventory refresh and transport details remain outside it.
class AppExperienceController extends ChangeNotifier {
  AppShellState _state;

  AppExperienceController({AppShellState? initialState})
    : _state = initialState ?? const AppShellState.initial();

  AppShellState get state => _state;

  void select(AppDestination destination) {
    if (_state.destination == destination) return;
    _state = _state.copyWith(destination: destination);
    notifyListeners();
  }

  void updateBadges({
    int? notifications,
    int? liveMatches,
    int? unopenedPacks,
    int? duelInvites,
    bool? connected,
  }) {
    final next = _state.copyWith(
      notificationCount: notifications,
      liveMatchCount: liveMatches,
      unopenedPackCount: unopenedPacks,
      duelInviteCount: duelInvites,
      connected: connected,
    );
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }
}

class AppExperienceShell extends StatelessWidget {
  final AppExperienceController controller;
  final Map<AppDestination, Widget> destinations;
  final PreferredSizeWidget? appBar;

  const AppExperienceShell({
    super.key,
    required this.controller,
    required this.destinations,
    this.appBar,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final state = controller.state;
      return Scaffold(
        backgroundColor: StadiumColors.canvas,
        appBar: appBar,
        body: IndexedStack(
          index: state.destination.index,
          children: [
            for (final destination in AppDestination.values)
              KeyedSubtree(
                key: PageStorageKey(destination.name),
                child: destinations[destination] ?? const SizedBox.shrink(),
              ),
          ],
        ),
        bottomNavigationBar: StadiumNavigationBar(
          state: state,
          onSelect: controller.select,
        ),
      );
    },
  );
}

class StadiumNavigationBar extends StatelessWidget {
  final AppShellState state;
  final ValueChanged<AppDestination> onSelect;

  const StadiumNavigationBar({
    super.key,
    required this.state,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: StadiumColors.navigation,
      border: Border(top: BorderSide(color: StadiumColors.hairline)),
      boxShadow: [
        BoxShadow(
          color: Color(0x66000000),
          blurRadius: 24,
          offset: Offset(0, -8),
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 68,
        child: Row(
          children: [
            for (final destination in AppDestination.values)
              Expanded(
                child: _DestinationButton(
                  destination: destination,
                  selected: state.destination == destination,
                  badge: state.badgeFor(destination),
                  onTap: () => onSelect(destination),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _DestinationButton extends StatelessWidget {
  final AppDestination destination;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  const _DestinationButton({
    required this.destination,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: destination.label,
    child: InkResponse(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      radius: 30,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? StadiumColors.orange.withValues(alpha: .12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: selected
                    ? StadiumColors.orange.withValues(alpha: .34)
                    : Colors.transparent,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  destination.asset,
                  width: 23,
                  height: 23,
                  colorFilter: ColorFilter.mode(
                    selected ? StadiumColors.orange : StadiumColors.muted,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  destination.label.toUpperCase(),
                  style: label(
                    color: selected ? StadiumColors.text : StadiumColors.muted,
                    size: 8,
                    weight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (badge > 0)
            Positioned(
              key: ValueKey('${destination.name}-nav-badge'),
              right: 12,
              top: 3,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: destination == AppDestination.cards
                      ? StadiumColors.lime
                      : StadiumColors.orange,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: StadiumColors.navigation, width: 2),
                ),
                child: Text(
                  badge > 9 ? '9+' : '$badge',
                  style: label(
                    color: StadiumColors.canvas,
                    size: 8,
                    weight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
