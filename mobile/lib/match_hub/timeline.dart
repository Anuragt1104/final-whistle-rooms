import '../api/live_data.dart';
import '../api/models.dart';
import 'models.dart';

List<MatchTimelineItem> buildMatchTimeline({
  required RoomView room,
  MatchData? matchData,
  int? frameMinute,
}) {
  final items = <MatchTimelineItem>[];
  final events = matchData?.events ?? const <VerifiedMatchEvent>[];

  for (final e in events) {
    if (frameMinute != null && e.minute > frameMinute) continue;
    items.add(
      MatchTimelineItem(
        id: e.id.isNotEmpty ? e.id : e.sourceEventId,
        sourceEventId: e.sourceEventId,
        kind: e.kind,
        phase: _phaseForMinute(e.minute),
        clockSec: e.minute * 60,
        teamId: e.side,
        playerId: e.playerId,
        title: e.label,
        detail: [
          if (e.playerName != null && e.playerName!.isNotEmpty) e.playerName!,
          if (e.teamCode.isNotEmpty) e.teamCode,
        ].join(' · '),
        status: TimelineStatus.verified,
        createdAt: e.ts,
      ),
    );
  }

  // Pulse cards that aren't already joined via sourceEventId.
  final seen = items.map((i) => i.sourceEventId).whereType<String>().toSet();
  for (final p in room.pulse) {
    final sid = p.sourceEventId;
    if (sid != null && seen.contains(sid)) continue;
    if (frameMinute != null && p.minute > frameMinute) continue;
    items.add(
      MatchTimelineItem(
        id: sid ?? p.id,
        sourceEventId: sid,
        kind: p.kind,
        phase: _phaseForMinute(p.minute),
        clockSec: p.minute * 60,
        teamId: p.side ?? p.accent,
        title: p.headline,
        detail: p.detail,
        status: TimelineStatus.verified,
        createdAt: p.minute * 60,
        artwork: p.emoji,
      ),
    );
  }

  for (final prompt in room.prompts) {
    if (prompt.status != 'settled' &&
        prompt.status != 'void' &&
        prompt.status != 'corrected') {
      continue;
    }
    if (frameMinute != null && prompt.locksAtMinute > frameMinute) continue;
    final status = switch (prompt.status) {
      'corrected' => TimelineStatus.corrected,
      'void' => TimelineStatus.discarded,
      _ => TimelineStatus.verified,
    };
    items.add(
      MatchTimelineItem(
        id: 'call:${prompt.id}',
        sourceEventId: 'call:${prompt.id}',
        kind: 'call',
        phase: _phaseForMinute(prompt.locksAtMinute),
        clockSec: prompt.locksAtMinute * 60,
        title: prompt.question,
        detail: prompt.status == 'settled'
            ? 'Call settled · ${prompt.winningKey ?? '—'}'
            : 'Call ${prompt.status}',
        status: status,
        createdAt: prompt.createdAt,
      ),
    );
  }

  for (final drop in room.momentDrops) {
    if (frameMinute != null && drop.minute > frameMinute) continue;
    items.add(
      MatchTimelineItem(
        id: 'moment:${drop.id}',
        sourceEventId: drop.sourceEventId,
        kind: 'moment',
        phase: _phaseForMinute(drop.minute),
        clockSec: drop.minute * 60,
        title: drop.label,
        detail: 'Moment drop · ${drop.kind}',
        status: TimelineStatus.verified,
        createdAt: drop.createdAt,
        artwork: drop.artworkKind,
      ),
    );
  }

  items.sort((a, b) {
    final byClock = a.clockSec.compareTo(b.clockSec);
    if (byClock != 0) return byClock;
    return a.createdAt.compareTo(b.createdAt);
  });
  return items;
}

int _phaseForMinute(int minute) {
  if (minute <= 45) return 1;
  if (minute <= 90) return 3;
  if (minute <= 120) return 5;
  return 8;
}

/// Verified-event pressure strip (not xG): rolling intensity from event density.
List<int> buildMatchPulse(List<MatchTimelineItem> timeline, {int buckets = 12}) {
  if (timeline.isEmpty) return List<int>.filled(buckets, 0);
  final maxMin = timeline.map((t) => t.clockSec ~/ 60).fold<int>(1, (a, b) => a > b ? a : b);
  final out = List<int>.filled(buckets, 0);
  for (final t in timeline) {
    if (t.kind == 'call' || t.kind == 'moment') continue;
    final m = t.clockSec ~/ 60;
    final idx = ((m / maxMin) * (buckets - 1)).floor().clamp(0, buckets - 1);
    final weight = switch (t.kind) {
      'goal' => 4,
      'red' => 3,
      'yellow' || 'corner' => 2,
      _ => 1,
    };
    out[idx] = (out[idx] + weight).clamp(0, 8);
  }
  return out;
}
