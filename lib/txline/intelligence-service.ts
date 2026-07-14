import { fetchFullLog, fetchRawSnapshot } from "@/lib/explorer/txodds";
import type { RawRecord } from "@/lib/explorer/types";
import { getSource, sourceMode } from "@/lib/txline/source";
import {
  aggregateTournamentLeaders,
  normalizeMatchRecords,
  type MatchIntelligenceView,
  type TournamentLeaders,
  type VerifiedPlayerView,
} from "@/lib/txline/match-intelligence";
import type { Fixture } from "@/lib/txline/types";

const LIVE_TTL_MS = 15_000;
const LEADERS_TTL_MS = 5 * 60_000;

interface CachedMatch {
  at: number;
  terminal: boolean;
  full: boolean;
  view: MatchIntelligenceView;
}

interface TeamTournamentView {
  team: Fixture["home"];
  lineupStatus: MatchIntelligenceView["lineupStatus"];
  sourceFixtureId?: string;
  sourceUpdatedAt: number;
  players: VerifiedPlayerView[];
  recentResults: Array<{
    fixtureId: string;
    kickoff: string;
    stage: string;
    opponent: Fixture["home"];
    score?: { for: number; against: number };
    status: Fixture["status"];
  }>;
}

interface TeamRecord {
  teamId: string;
  teamCode: string;
  teamName: string;
  played: number;
  wins: number;
  draws: number;
  losses: number;
  goalsFor: number;
  goalsAgainst: number;
  yellowCards: number;
  redCards: number;
}

export interface TournamentOverview extends TournamentLeaders {
  teamRecords: TeamRecord[];
}

type IntelligenceStore = {
  matches: Map<string, CachedMatch>;
  pending: Map<string, Promise<MatchIntelligenceView>>;
  overview: { at: number; value: TournamentOverview } | null;
};

const globalStore = globalThis as unknown as { __fwr_intelligence?: IntelligenceStore };
const store = globalStore.__fwr_intelligence ?? (globalStore.__fwr_intelligence = {
  matches: new Map(),
  pending: new Map(),
  overview: null,
});

async function loadRecords(fixture: Fixture, full: boolean): Promise<RawRecord[]> {
  if (sourceMode() !== "live") return [];
  if (full && fixture.status !== "scheduled") {
    try {
      const log = await fetchFullLog(fixture.id);
      if (log.records.length) return log.records;
    } catch {
      // A current free-tier fixture may not expose its finite history yet.
    }
  }
  return fetchRawSnapshot(fixture.id);
}

async function loadView(fixture: Fixture, full: boolean): Promise<MatchIntelligenceView> {
  const key = `${fixture.id}:${full ? "full" : "snapshot"}`;
  const cached = store.matches.get(key);
  if (cached && (cached.terminal || Date.now() - cached.at < LIVE_TTL_MS)) return cached.view;
  const pending = store.pending.get(key);
  if (pending) return pending;

  const work = (async () => {
    try {
      const records = await loadRecords(fixture, full);
      const view = normalizeMatchRecords(fixture, records);
      const terminal = fixture.status === "finished";
      store.matches.set(key, { at: Date.now(), terminal, full, view });
      return view;
    } catch (error) {
      if (cached) return { ...cached.view, stale: true };
      throw error;
    } finally {
      store.pending.delete(key);
    }
  })();
  store.pending.set(key, work);
  return work;
}

export async function getFixtureMatchData(fixtureId: string): Promise<MatchIntelligenceView | null> {
  const fixture = await getSource().getFixture(fixtureId);
  if (!fixture) return null;
  return loadView(fixture, true);
}

async function mapLimit<T, R>(items: T[], limit: number, fn: (item: T) => Promise<R>): Promise<R[]> {
  const out = new Array<R>(items.length);
  let cursor = 0;
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (cursor < items.length) {
      const index = cursor++;
      out[index] = await fn(items[index]);
    }
  }));
  return out;
}

function recordFor(view: MatchIntelligenceView): TeamRecord[] {
  const score = view.score;
  if (!score || view.fixture.status === "scheduled") return [];
  const home = view.fixture.home;
  const away = view.fixture.away;
  const hg = score.goals.home;
  const ag = score.goals.away;
  return [
    {
      teamId: home.id, teamCode: home.code, teamName: home.name, played: 1,
      wins: hg > ag ? 1 : 0, draws: hg === ag ? 1 : 0, losses: hg < ag ? 1 : 0,
      goalsFor: hg, goalsAgainst: ag, yellowCards: score.yellow.home, redCards: score.red.home,
    },
    {
      teamId: away.id, teamCode: away.code, teamName: away.name, played: 1,
      wins: ag > hg ? 1 : 0, draws: hg === ag ? 1 : 0, losses: ag < hg ? 1 : 0,
      goalsFor: ag, goalsAgainst: hg, yellowCards: score.yellow.away, redCards: score.red.away,
    },
  ];
}

export async function getTournamentOverview(): Promise<TournamentOverview> {
  if (store.overview && Date.now() - store.overview.at < LEADERS_TTL_MS) return store.overview.value;
  const fixtures = (await getSource().listFixtures()).filter((f) => f.status !== "scheduled");
  const views = await mapLimit(fixtures, 8, (fixture) => loadView(fixture, false));
  const leaders = aggregateTournamentLeaders(views);
  const teams = new Map<string, TeamRecord>();
  for (const view of views) {
    for (const next of recordFor(view)) {
      const prior = teams.get(next.teamId);
      if (!prior) teams.set(next.teamId, next);
      else {
        prior.played += next.played;
        prior.wins += next.wins;
        prior.draws += next.draws;
        prior.losses += next.losses;
        prior.goalsFor += next.goalsFor;
        prior.goalsAgainst += next.goalsAgainst;
        prior.yellowCards += next.yellowCards;
        prior.redCards += next.redCards;
      }
    }
  }
  const value = {
    ...leaders,
    teamRecords: [...teams.values()].sort((a, b) => b.wins - a.wins || (b.goalsFor - b.goalsAgainst) - (a.goalsFor - a.goalsAgainst) || a.teamName.localeCompare(b.teamName)),
  };
  store.overview = { at: Date.now(), value };
  return value;
}

export async function getTeamTournamentView(teamId: string): Promise<TeamTournamentView | null> {
  const fixtures = (await getSource().listFixtures()).filter((f) => f.home.id === teamId || f.away.id === teamId);
  if (!fixtures.length) return null;
  const sorted = [...fixtures].sort((a, b) => Date.parse(b.kickoff) - Date.parse(a.kickoff));
  const views = await mapLimit(sorted, 6, (fixture) => loadView(fixture, false));
  const team = sorted[0].home.id === teamId ? sorted[0].home : sorted[0].away;
  const source = views.find((view) => {
    const side = view.fixture.home.id === teamId ? view.teams.home : view.teams.away;
    return side.players.length > 0;
  });
  const sourceTeam = source
    ? (source.fixture.home.id === teamId ? source.teams.home : source.teams.away)
    : undefined;

  const totals = new Map<string, VerifiedPlayerView>();
  for (const view of views) {
    const side = view.fixture.home.id === teamId ? view.teams.home : view.teams.away;
    for (const player of side.players) {
      const prior = totals.get(player.id);
      if (!prior) totals.set(player.id, { ...player, stats: { ...player.stats } });
      else {
        prior.stats.goals += player.stats.goals;
        prior.stats.yellowCards += player.stats.yellowCards;
        prior.stats.redCards += player.stats.redCards;
        prior.stats.starts += player.stats.starts;
        prior.stats.squadSelections += player.stats.squadSelections;
      }
    }
  }
  const players = (sourceTeam?.players ?? []).map((player) => totals.get(player.id) ?? player);
  const recentResults = sorted.slice(0, 8).map((fixture, index) => {
    const view = views[index];
    const home = fixture.home.id === teamId;
    return {
      fixtureId: fixture.id,
      kickoff: fixture.kickoff,
      stage: fixture.stage,
      opponent: home ? fixture.away : fixture.home,
      score: view.score ? {
        for: home ? view.score.goals.home : view.score.goals.away,
        against: home ? view.score.goals.away : view.score.goals.home,
      } : undefined,
      status: fixture.status,
    };
  });
  return {
    team,
    lineupStatus: source?.lineupStatus ?? "unavailable",
    sourceFixtureId: source?.fixtureId,
    sourceUpdatedAt: source?.updatedAt ?? 0,
    players,
    recentResults,
  };
}

export function __resetIntelligenceCacheForTests() {
  store.matches.clear();
  store.pending.clear();
  store.overview = null;
}

