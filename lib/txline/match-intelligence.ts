import type { RawRecord } from "@/lib/explorer/types";
import { mapScores } from "@/lib/txline/live";
import type { Fixture, ScoreSnapshot } from "@/lib/txline/types";
import { portraitForPlayerId } from "@/lib/txline/player-art";

export type LineupStatus = "unavailable" | "provisional" | "confirmed";
export type PortraitKind = "photo" | "illustration";

export interface VerifiedPlayerStats {
  goals: number;
  yellowCards: number;
  redCards: number;
  starts: number;
  squadSelections: number;
}

export interface VerifiedPlayerView {
  id: string;
  fixturePlayerId?: string;
  name: string;
  country?: string;
  dateOfBirth?: string;
  shirtNumber?: string;
  position: "GK" | "DF" | "MF" | "FW" | "UNK";
  starter: boolean;
  onPitch: boolean;
  photoUrl?: string;
  portraitKind: PortraitKind;
  stats: VerifiedPlayerStats;
}

export interface VerifiedTeamLineup {
  id: string;
  name: string;
  code: string;
  formation?: string;
  players: VerifiedPlayerView[];
}

export interface VerifiedMatchEvent {
  id: string;
  sourceEventId: string;
  seq: number;
  ts: number;
  minute: number;
  kind: "goal" | "yellow" | "red" | "corner" | "substitution";
  side: "home" | "away";
  teamCode: string;
  playerId?: string;
  playerName?: string;
  playerPhotoUrl?: string;
  secondaryPlayerId?: string;
  secondaryPlayerName?: string;
  label: string;
  confirmed: boolean;
}

export interface MatchIntelligenceView {
  fixtureId: string;
  fixture: Fixture;
  source: "txline";
  lineupStatus: LineupStatus;
  teams: { home: VerifiedTeamLineup; away: VerifiedTeamLineup };
  events: VerifiedMatchEvent[];
  score?: ScoreSnapshot;
  updatedAt: number;
  stale: boolean;
}

export interface LeaderboardEntry {
  playerId: string;
  name: string;
  teamId: string;
  teamCode: string;
  photoUrl?: string;
  portraitKind: PortraitKind;
  value: number;
}

export interface TournamentLeaders {
  goals: LeaderboardEntry[];
  yellowCards: LeaderboardEntry[];
  redCards: LeaderboardEntry[];
  asOf: number;
}

type AnyMap = Record<string, unknown>;

const asMap = (value: unknown): AnyMap =>
  value && typeof value === "object" && !Array.isArray(value) ? (value as AnyMap) : {};

const num = (value: unknown, fallback = 0): number => {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
};

const str = (value: unknown): string | undefined => {
  if (value == null) return undefined;
  const s = String(value).trim();
  return s || undefined;
};

/** TxLINE commonly sends "Surname, Given names"; the UI always uses natural order. */
export function normalizePlayerName(raw: string): string {
  const clean = raw.replace(/\s+/g, " ").trim();
  const comma = clean.indexOf(",");
  if (comma < 0) return clean;
  const family = clean.slice(0, comma).trim();
  const given = clean.slice(comma + 1).trim();
  return `${given} ${family}`.trim();
}

function positionFor(id: unknown): VerifiedPlayerView["position"] {
  switch (num(id, -1)) {
    case 34: return "GK";
    case 35: return "DF";
    case 36: return "MF";
    case 37: return "FW";
    default: return "UNK";
  }
}

function emptyTeam(fixture: Fixture, side: "home" | "away"): VerifiedTeamLineup {
  const team = fixture[side];
  return { id: team.id, name: team.name, code: team.code, players: [] };
}

function participantSide(record: RawRecord, participant: unknown): "home" | "away" {
  const p = num(participant, 1);
  const p1Home = record.Participant1IsHome !== false;
  return (p === 1) === p1Home ? "home" : "away";
}

function latestWith<T>(records: RawRecord[], read: (r: RawRecord) => T | undefined): { record: RawRecord; value: T } | undefined {
  let found: { record: RawRecord; value: T } | undefined;
  for (const record of records) {
    const value = read(record);
    if (value === undefined) continue;
    if (!found || num(record.Seq) >= num(found.record.Seq)) found = { record, value };
  }
  return found;
}

function lineupArray(record: RawRecord): AnyMap[] {
  const direct = (record as AnyMap).Lineups;
  if (Array.isArray(direct)) return direct.map(asMap);
  const data = asMap(record.Data);
  const nested = data.Lineups ?? data.lineups;
  return Array.isArray(nested) ? nested.map(asMap) : [];
}

function statsFor(record: RawRecord | undefined, participant: 1 | 2): Record<string, AnyMap> {
  if (!record?.PlayerStats) return {};
  const group = asMap(record.PlayerStats[`Participant${participant}`]);
  return Object.fromEntries(Object.entries(group).map(([id, value]) => [id, asMap(value)]));
}

function onPitchIds(records: RawRecord[], participant: 1 | 2): Set<string> {
  const latest = latestWith(records, (r) => r.Action === "players_on_the_pitch" ? r : undefined)?.record;
  if (!latest) return new Set();
  const top = latest as AnyMap;
  const candidates = [
    top.PlayersOnThePitch,
    top.PlayersOnPitch,
    asMap(latest.Data).PlayersOnThePitch,
    latest.Data,
  ];
  for (const candidate of candidates) {
    const group = asMap(asMap(candidate)[`Participant${participant}`]);
    if (Object.keys(group).length) {
      return new Set(Object.entries(group).filter(([, value]) => num(value) > 0).map(([id]) => id));
    }
  }
  return new Set();
}

function deriveFormation(players: VerifiedPlayerView[]): string | undefined {
  const starters = players.filter((p) => p.starter);
  if (starters.length !== 11) return undefined;
  const count = (position: VerifiedPlayerView["position"]) => starters.filter((p) => p.position === position).length;
  const df = count("DF");
  const mf = count("MF");
  const fw = count("FW");
  return df + mf + fw === 10 ? `${df}-${mf}-${fw}` : undefined;
}

function buildPlayers(
  rawPlayers: unknown[],
  statMap: Record<string, AnyMap>,
  pitch: Set<string>,
): VerifiedPlayerView[] {
  return rawPlayers.map((raw) => {
    const row = asMap(raw);
    const data = asMap(row.player);
    const id = str(data.normativeId) ?? str(row.fixturePlayerId) ?? "unknown";
    const fixturePlayerId = str(row.fixturePlayerId);
    const stats = statMap[id] ?? (fixturePlayerId ? statMap[fixturePlayerId] : undefined) ?? {};
    const starter = row.starter === true;
    const photoUrl = portraitForPlayerId(id);
    return {
      id,
      fixturePlayerId,
      name: normalizePlayerName(str(data.preferredName) ?? `Player ${id}`),
      country: str(data.country),
      dateOfBirth: str(data.dateOfBirth),
      shirtNumber: str(row.rosterNumber),
      position: positionFor(row.positionId),
      starter,
      onPitch: pitch.has(id) || (!!fixturePlayerId && pitch.has(fixturePlayerId)) || (pitch.size === 0 && starter),
      photoUrl,
      portraitKind: photoUrl ? "photo" as const : "illustration" as const,
      stats: {
        goals: num(stats.goals),
        yellowCards: num(stats.yellowCards),
        redCards: num(stats.redCards),
        starts: starter ? 1 : 0,
        squadSelections: 1,
      },
    };
  }).sort((a, b) => {
    const order = { GK: 0, DF: 1, MF: 2, FW: 3, UNK: 4 } as const;
    return Number(b.starter) - Number(a.starter) || order[a.position] - order[b.position] || num(a.shirtNumber, 999) - num(b.shirtNumber, 999);
  });
}

function playerIndexes(teams: MatchIntelligenceView["teams"]): Map<string, VerifiedPlayerView> {
  const out = new Map<string, VerifiedPlayerView>();
  for (const player of [...teams.home.players, ...teams.away.players]) {
    out.set(player.id, player);
    if (player.fixturePlayerId) out.set(player.fixturePlayerId, player);
  }
  return out;
}

function actionTarget(record: RawRecord): string | undefined {
  const data = asMap(record.Data);
  return str(data.ActionId ?? data.TargetId ?? data.Id ?? (record as AnyMap).ActionId);
}

function normalizedEvents(fixture: Fixture, records: RawRecord[], teams: MatchIntelligenceView["teams"]): VerifiedMatchEvent[] {
  const kinds: Record<string, VerifiedMatchEvent["kind"]> = {
    goal: "goal",
    yellow_card: "yellow",
    red_card: "red",
    corner: "corner",
    substitution: "substitution",
  };
  const ledger = new Map<string, { record: RawRecord; data: AnyMap }>();
  const discarded = new Set<string>();
  const ordered = [...records].sort((a, b) => num(a.Seq) - num(b.Seq));

  for (const record of ordered) {
    if (record.Confirmed === false) continue;
    if (record.Action === "action_discarded") {
      const target = actionTarget(record);
      if (target) discarded.add(target);
      continue;
    }
    if (record.Action === "action_amend") {
      const target = actionTarget(record);
      if (!target) continue;
      const prior = ledger.get(target);
      if (!prior) continue;
      const data = asMap(record.Data);
      prior.data = { ...prior.data, ...asMap(data.New) };
      continue;
    }
    if (!record.Action || !kinds[record.Action]) continue;
    const key = str(record.Id) ?? str(record.Seq) ?? `${record.Action}:${record.Ts}`;
    if (!key) continue;
    ledger.set(key, { record, data: asMap(record.Data) });
  }

  const players = playerIndexes(teams);
  const out: VerifiedMatchEvent[] = [];
  for (const [key, value] of ledger) {
    if (discarded.has(key)) continue;
    const { record, data } = value;
    const kind = kinds[record.Action ?? ""];
    if (!kind) continue;
    const participant = data.Participant ?? record.Participant;
    const side = participantSide(record, participant);
    const primaryRaw = kind === "substitution" ? data.PlayerOutId : data.PlayerId;
    const secondaryRaw = kind === "substitution" ? data.PlayerInId : undefined;
    const playerId = str(primaryRaw);
    const secondaryPlayerId = str(secondaryRaw);
    const player = playerId ? players.get(playerId) : undefined;
    const secondary = secondaryPlayerId ? players.get(secondaryPlayerId) : undefined;
    const team = fixture[side];
    const noun = kind === "yellow" ? "Yellow card" : kind === "red" ? "Red card" : kind === "substitution" ? "Substitution" : kind[0].toUpperCase() + kind.slice(1);
    const detail = kind === "substitution"
      ? [secondary?.name, player?.name].filter(Boolean).join(" on · ")
      : player?.name;
    const seq = num(record.Seq);
    const sourceEventId = `tx:${fixture.id}:${key}`;
    out.push({
      id: sourceEventId,
      sourceEventId,
      seq,
      ts: num(record.Ts),
      minute: Math.max(0, Math.floor(num(record.Clock?.Seconds) / 60)),
      kind,
      side,
      teamCode: team.code,
      playerId: player?.id ?? playerId,
      playerName: player?.name,
      playerPhotoUrl: player?.photoUrl,
      secondaryPlayerId: secondary?.id ?? secondaryPlayerId,
      secondaryPlayerName: secondary?.name,
      label: `${noun} — ${detail || team.name}`,
      confirmed: record.Confirmed !== false,
    });
  }
  return out.sort((a, b) => a.seq - b.seq || a.ts - b.ts);
}

export function normalizeMatchRecords(fixture: Fixture, input: RawRecord[]): MatchIntelligenceView {
  const records = [...input].sort((a, b) => num(a.Seq) - num(b.Seq));
  const lineup = latestWith(records, (r) => lineupArray(r).length ? lineupArray(r) : undefined);
  const latestStats = latestWith(records, (r) => r.PlayerStats ? r.PlayerStats : undefined)?.record;
  const p1Home = lineup?.record.Participant1IsHome !== false;
  const homeParticipant: 1 | 2 = p1Home ? 1 : 2;
  const awayParticipant: 1 | 2 = p1Home ? 2 : 1;
  const lineups = lineup?.value ?? [];

  const findLineup = (teamId: string, participant: 1 | 2): AnyMap => {
    const exact = lineups.find((entry) => str(entry.normativeId) === teamId);
    return exact ?? lineups[participant - 1] ?? {};
  };
  const rawPlayers = (entry: AnyMap): unknown[] => {
    const value = entry.lineups ?? entry.players;
    return Array.isArray(value) ? value : [];
  };

  const homeEntry = findLineup(fixture.home.id, homeParticipant);
  const awayEntry = findLineup(fixture.away.id, awayParticipant);
  const homePlayers = buildPlayers(rawPlayers(homeEntry), statsFor(latestStats, homeParticipant), onPitchIds(records, homeParticipant));
  const awayPlayers = buildPlayers(rawPlayers(awayEntry), statsFor(latestStats, awayParticipant), onPitchIds(records, awayParticipant));
  const teams = {
    home: { ...emptyTeam(fixture, "home"), formation: deriveFormation(homePlayers), players: homePlayers },
    away: { ...emptyTeam(fixture, "away"), formation: deriveFormation(awayPlayers), players: awayPlayers },
  };

  const scoreRecord = latestWith(records, (r) => (r.Score || r.Stats || r.Clock) ? r : undefined)?.record;
  let score: ScoreSnapshot | undefined;
  if (scoreRecord) {
    try {
      score = mapScores(scoreRecord as never, num(scoreRecord.Seq), new Date(num(scoreRecord.Ts, Date.now())).toISOString());
    } catch {
      score = undefined;
    }
  }
  const updatedAt = records.reduce((max, r) => Math.max(max, num(r.Ts)), 0);
  return {
    fixtureId: fixture.id,
    fixture,
    source: "txline",
    lineupStatus: !lineup ? "unavailable" : lineup.record.Confirmed === true ? "confirmed" : "provisional",
    teams,
    events: normalizedEvents(fixture, records, teams),
    score,
    updatedAt,
    stale: updatedAt > 0 && Date.now() - updatedAt > 2 * 60_000 && fixture.status === "live",
  };
}

export function aggregateTournamentLeaders(matches: MatchIntelligenceView[]): TournamentLeaders {
  const totals = new Map<string, { player: VerifiedPlayerView; team: VerifiedTeamLineup; goals: number; yellowCards: number; redCards: number }>();
  let asOf = 0;
  for (const match of matches) {
    asOf = Math.max(asOf, match.updatedAt);
    for (const team of [match.teams.home, match.teams.away]) {
      for (const player of team.players) {
        const key = `${team.id}:${player.id}`;
        const prior = totals.get(key) ?? { player, team, goals: 0, yellowCards: 0, redCards: 0 };
        prior.goals += player.stats.goals;
        prior.yellowCards += player.stats.yellowCards;
        prior.redCards += player.stats.redCards;
        totals.set(key, prior);
      }
    }
  }
  const list = (field: "goals" | "yellowCards" | "redCards") => [...totals.values()]
    .filter((row) => row[field] > 0)
    .map((row) => ({
      playerId: row.player.id,
      name: row.player.name,
      teamId: row.team.id,
      teamCode: row.team.code,
      photoUrl: row.player.photoUrl,
      portraitKind: row.player.portraitKind,
      value: row[field],
    }))
    .sort((a, b) => b.value - a.value || a.name.localeCompare(b.name));
  return { goals: list("goals"), yellowCards: list("yellowCards"), redCards: list("redCards"), asOf };
}
