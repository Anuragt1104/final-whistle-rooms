import '../api/models.dart';

class FeedHealth {
  final bool stale;
  final bool clockFrozen;
  final bool callsPaused;
  final String? reason;
  final String stripLabel;

  const FeedHealth({
    required this.stale,
    required this.clockFrozen,
    required this.callsPaused,
    required this.stripLabel,
    this.reason,
  });
}

FeedHealth evaluateFeedHealth(RoomView room) {
  final freshness = room.feedFreshness;
  final stale = freshness == 'stale' || freshness == 'disconnected';
  final waiting = freshness == 'waiting';
  String? reason;
  if (stale) {
    reason = 'Updates delayed';
  } else if (waiting && room.status == 'live') {
    reason = 'Waiting for match data';
  }
  return FeedHealth(
    stale: stale,
    clockFrozen: stale,
    callsPaused: stale,
    reason: reason,
    stripLabel: stale
        ? 'Feed reconnecting · Calls paused'
        : (waiting ? 'Match data warming up' : 'Live feed healthy'),
  );
}

String lifecycleBadge(RoomView room, {required bool isReplay}) {
  if (isReplay && room.status != 'finished') return 'REPLAY';
  switch (room.lifecycle) {
    case 'finished':
      return 'FULL TIME';
    case 'pregame':
      if (room.status == 'lobby') return 'PREGAME';
      break;
  }
  if (room.status == 'finished') return 'FULL TIME';
  if (room.status == 'lobby') return 'PREGAME';
  final s = room.score;
  if (s == null || s.phase == 0) return 'PREGAME';
  switch (s.phase) {
    case 2:
      return 'HALF-TIME';
    case 4:
    case 9:
      return 'FULL TIME';
    case 5:
    case 7:
      return 'EXTRA TIME';
    case 6:
      return 'ET BREAK';
    case 8:
      return 'PENALTIES';
    default:
      return isReplay ? 'REPLAY' : 'LIVE';
  }
}

String formatClock(RoomView room, {required bool frozen}) {
  final s = room.score;
  if (room.status == 'finished' || (s != null && (s.phase == 4 || s.phase == 9))) {
    return 'FT';
  }
  if (s == null) return room.status == 'lobby' ? 'KO SOON' : '—';
  if (s.phase == 2) return 'HT';
  if (s.phase == 0) return 'KO SOON';
  if (s.phase == 8) return 'PEN';
  final base = "${s.minute}'";
  return frozen ? '$base · DELAYED' : base;
}

String? scoreText(RoomView room, {required bool spoilerHidden}) {
  if (spoilerHidden) return null;
  final s = room.score;
  if (s == null || room.status == 'lobby' || s.phase == 0) return null;
  return '${s.goals.home} - ${s.goals.away}';
}
