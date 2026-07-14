import 'models.dart';

int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

class VerifiedPlayerStats {
  final int goals, yellowCards, redCards, starts, squadSelections;
  const VerifiedPlayerStats({
    required this.goals,
    required this.yellowCards,
    required this.redCards,
    required this.starts,
    required this.squadSelections,
  });
  factory VerifiedPlayerStats.fromJson(Map<String, dynamic>? j) {
    final data = j ?? const <String, dynamic>{};
    return VerifiedPlayerStats(
      goals: _int(data['goals']),
      yellowCards: _int(data['yellowCards']),
      redCards: _int(data['redCards']),
      starts: _int(data['starts']),
      squadSelections: _int(data['squadSelections']),
    );
  }
}

class VerifiedPlayer {
  final String id, name, position, portraitKind;
  final String? fixturePlayerId, country, dateOfBirth, shirtNumber, photoUrl;
  final bool starter, onPitch;
  final VerifiedPlayerStats stats;
  const VerifiedPlayer({
    required this.id,
    required this.name,
    required this.position,
    required this.portraitKind,
    required this.starter,
    required this.onPitch,
    required this.stats,
    this.fixturePlayerId,
    this.country,
    this.dateOfBirth,
    this.shirtNumber,
    this.photoUrl,
  });
  factory VerifiedPlayer.fromJson(Map<String, dynamic> j) => VerifiedPlayer(
    id: '${j['id'] ?? ''}',
    name: '${j['name'] ?? 'Player'}',
    position: '${j['position'] ?? 'UNK'}',
    portraitKind: '${j['portraitKind'] ?? 'illustration'}',
    starter: j['starter'] == true,
    onPitch: j['onPitch'] == true,
    stats: VerifiedPlayerStats.fromJson(
      j['stats'] is Map ? Map<String, dynamic>.from(j['stats']) : null,
    ),
    fixturePlayerId: j['fixturePlayerId']?.toString(),
    country: j['country']?.toString(),
    dateOfBirth: j['dateOfBirth']?.toString(),
    shirtNumber: j['shirtNumber']?.toString(),
    photoUrl: j['photoUrl']?.toString(),
  );
}

class VerifiedTeamLineup {
  final String id, name, code;
  final String? formation;
  final List<VerifiedPlayer> players;
  const VerifiedTeamLineup({
    required this.id,
    required this.name,
    required this.code,
    this.formation,
    required this.players,
  });
  factory VerifiedTeamLineup.fromJson(Map<String, dynamic> j) =>
      VerifiedTeamLineup(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        code: '${j['code'] ?? ''}',
        formation: j['formation']?.toString(),
        players: ((j['players'] ?? const []) as List)
            .map((p) => VerifiedPlayer.fromJson(Map<String, dynamic>.from(p)))
            .toList(),
      );
}

class VerifiedMatchEvent {
  final String id, sourceEventId, kind, side, teamCode, label;
  final int seq, ts, minute;
  final String? playerId, playerName, secondaryPlayerId, secondaryPlayerName;
  const VerifiedMatchEvent({
    required this.id,
    required this.sourceEventId,
    required this.kind,
    required this.side,
    required this.teamCode,
    required this.label,
    required this.seq,
    required this.ts,
    required this.minute,
    this.playerId,
    this.playerName,
    this.secondaryPlayerId,
    this.secondaryPlayerName,
  });
  factory VerifiedMatchEvent.fromJson(Map<String, dynamic> j) =>
      VerifiedMatchEvent(
        id: '${j['id'] ?? ''}',
        sourceEventId: '${j['sourceEventId'] ?? j['id'] ?? ''}',
        kind: '${j['kind'] ?? ''}',
        side: '${j['side'] ?? 'home'}',
        teamCode: '${j['teamCode'] ?? ''}',
        label: '${j['label'] ?? ''}',
        seq: _int(j['seq']),
        ts: _int(j['ts']),
        minute: _int(j['minute']),
        playerId: j['playerId']?.toString(),
        playerName: j['playerName']?.toString(),
        secondaryPlayerId: j['secondaryPlayerId']?.toString(),
        secondaryPlayerName: j['secondaryPlayerName']?.toString(),
      );
}

class MatchData {
  final String fixtureId, source, lineupStatus;
  final Fixture fixture;
  final VerifiedTeamLineup home, away;
  final List<VerifiedMatchEvent> events;
  final ScoreView? score;
  final int updatedAt;
  final bool stale;
  const MatchData({
    required this.fixtureId,
    required this.source,
    required this.lineupStatus,
    required this.fixture,
    required this.home,
    required this.away,
    required this.events,
    required this.score,
    required this.updatedAt,
    required this.stale,
  });
  factory MatchData.fromJson(Map<String, dynamic> j) {
    final teams = Map<String, dynamic>.from(j['teams'] ?? const {});
    return MatchData(
      fixtureId: '${j['fixtureId'] ?? ''}',
      source: '${j['source'] ?? 'txline'}',
      lineupStatus: '${j['lineupStatus'] ?? 'unavailable'}',
      fixture: Fixture.fromJson(Map<String, dynamic>.from(j['fixture'])),
      home: VerifiedTeamLineup.fromJson(
        Map<String, dynamic>.from(teams['home'] ?? const {}),
      ),
      away: VerifiedTeamLineup.fromJson(
        Map<String, dynamic>.from(teams['away'] ?? const {}),
      ),
      events: ((j['events'] ?? const []) as List)
          .map((e) => VerifiedMatchEvent.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      score: j['score'] is Map
          ? ScoreView.fromJson(Map<String, dynamic>.from(j['score']))
          : null,
      updatedAt: _int(j['updatedAt']),
      stale: j['stale'] == true,
    );
  }
}

class TeamResult {
  final String fixtureId, kickoff, stage, status;
  final Team opponent;
  final int? goalsFor, goalsAgainst;
  const TeamResult({
    required this.fixtureId,
    required this.kickoff,
    required this.stage,
    required this.status,
    required this.opponent,
    this.goalsFor,
    this.goalsAgainst,
  });
  factory TeamResult.fromJson(Map<String, dynamic> j) {
    final score = j['score'] is Map
        ? Map<String, dynamic>.from(j['score'])
        : null;
    return TeamResult(
      fixtureId: '${j['fixtureId'] ?? ''}',
      kickoff: '${j['kickoff'] ?? ''}',
      stage: '${j['stage'] ?? ''}',
      status: '${j['status'] ?? 'scheduled'}',
      opponent: Team.fromJson(Map<String, dynamic>.from(j['opponent'])),
      goalsFor: score == null ? null : _int(score['for']),
      goalsAgainst: score == null ? null : _int(score['against']),
    );
  }
}

class TeamTournamentData {
  final Team team;
  final String lineupStatus;
  final String? sourceFixtureId;
  final int sourceUpdatedAt;
  final List<VerifiedPlayer> players;
  final List<TeamResult> recentResults;
  const TeamTournamentData({
    required this.team,
    required this.lineupStatus,
    required this.sourceUpdatedAt,
    required this.players,
    required this.recentResults,
    this.sourceFixtureId,
  });
  factory TeamTournamentData.fromJson(Map<String, dynamic> j) =>
      TeamTournamentData(
        team: Team.fromJson(Map<String, dynamic>.from(j['team'])),
        lineupStatus: '${j['lineupStatus'] ?? 'unavailable'}',
        sourceFixtureId: j['sourceFixtureId']?.toString(),
        sourceUpdatedAt: _int(j['sourceUpdatedAt']),
        players: ((j['players'] ?? const []) as List)
            .map((p) => VerifiedPlayer.fromJson(Map<String, dynamic>.from(p)))
            .toList(),
        recentResults: ((j['recentResults'] ?? const []) as List)
            .map((r) => TeamResult.fromJson(Map<String, dynamic>.from(r)))
            .toList(),
      );
}

class LeaderEntry {
  final String playerId, name, teamId, teamCode, portraitKind;
  final String? photoUrl;
  final int value;
  const LeaderEntry({
    required this.playerId,
    required this.name,
    required this.teamId,
    required this.teamCode,
    required this.portraitKind,
    required this.value,
    this.photoUrl,
  });
  factory LeaderEntry.fromJson(Map<String, dynamic> j) => LeaderEntry(
    playerId: '${j['playerId'] ?? ''}',
    name: '${j['name'] ?? ''}',
    teamId: '${j['teamId'] ?? ''}',
    teamCode: '${j['teamCode'] ?? ''}',
    portraitKind: '${j['portraitKind'] ?? 'illustration'}',
    value: _int(j['value']),
    photoUrl: j['photoUrl']?.toString(),
  );
}

class TeamRecordData {
  final String teamId, teamCode, teamName;
  final int played,
      wins,
      draws,
      losses,
      goalsFor,
      goalsAgainst,
      yellowCards,
      redCards;
  const TeamRecordData({
    required this.teamId,
    required this.teamCode,
    required this.teamName,
    required this.played,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.yellowCards,
    required this.redCards,
  });
  factory TeamRecordData.fromJson(Map<String, dynamic> j) => TeamRecordData(
    teamId: '${j['teamId'] ?? ''}',
    teamCode: '${j['teamCode'] ?? ''}',
    teamName: '${j['teamName'] ?? ''}',
    played: _int(j['played']),
    wins: _int(j['wins']),
    draws: _int(j['draws']),
    losses: _int(j['losses']),
    goalsFor: _int(j['goalsFor']),
    goalsAgainst: _int(j['goalsAgainst']),
    yellowCards: _int(j['yellowCards']),
    redCards: _int(j['redCards']),
  );
}

class TournamentLeadersData {
  final List<LeaderEntry> goals, yellowCards, redCards;
  final List<TeamRecordData> teamRecords;
  final int asOf;
  const TournamentLeadersData({
    required this.goals,
    required this.yellowCards,
    required this.redCards,
    required this.teamRecords,
    required this.asOf,
  });
  factory TournamentLeadersData.fromJson(Map<String, dynamic> j) =>
      TournamentLeadersData(
        goals: ((j['goals'] ?? const []) as List)
            .map((e) => LeaderEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        yellowCards: ((j['yellowCards'] ?? const []) as List)
            .map((e) => LeaderEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        redCards: ((j['redCards'] ?? const []) as List)
            .map((e) => LeaderEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        teamRecords: ((j['teamRecords'] ?? const []) as List)
            .map((e) => TeamRecordData.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        asOf: _int(j['asOf']),
      );
}
