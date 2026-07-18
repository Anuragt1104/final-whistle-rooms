/// Tracks which live room the user is actively viewing so goal push alerts
/// can be suppressed (they're already watching the feed).
class RoomPresence {
  static String? activeRoomId;
  static String? activeFixtureId;
  static bool _foreground = true;

  /// True only while the app is foregrounded AND a room screen is mounted.
  static bool get isInRoom => _foreground && activeRoomId != null;

  static void enter(String roomId, {String? fixtureId}) {
    activeRoomId = roomId;
    activeFixtureId = fixtureId;
  }

  static void leave(String roomId) {
    if (activeRoomId == roomId) {
      activeRoomId = null;
      activeFixtureId = null;
    }
  }

  /// Phone locked / app backgrounded → treat as not viewing so pushes fire.
  static void setForeground(bool value) {
    _foreground = value;
  }

  static bool isViewingRoom(String roomId) =>
      _foreground && activeRoomId == roomId;

  static bool isViewingFixture(String fixtureId) =>
      _foreground && activeFixtureId == fixtureId;
}
