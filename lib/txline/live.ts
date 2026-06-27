/**
 * LiveSource — the real TxLINE client (TXLINE_MODE=live).
 *
 * Maps TxLINE's normalized PascalCase schema into our consumer types:
 *  - GET /api/fixtures/snapshot  -> Fixture[]
 *  - GET /api/scores/snapshot    -> ScoreSnapshot
 *  - GET /api/odds/snapshot      -> OddsSnapshot
 *  - GET /api/scores|odds/stream -> FeedTick via SSE
 *
 * Verified against docs.yaml v1.5.2 (see docs/TXLINE_API.md). Simulation mode is
 * the default and the demo path; this adapter is the production data path.
 */
import {
  GamePhase,
  type Fixture,
  type MatchEvent,
  type OddsMarket,
  type OddsSnapshot,
  type ScoreSnapshot,
  type StatPair,
  type Team,
} from "@/lib/txline/types";
import type { TxLineSource } from "@/lib/txline/source";
import { getApiToken, getGuestJwt, refreshJwt, txlineBase, txlineHeaders } from "@/lib/txline/auth";

// FIFA World Cup 2026 competition id (override via env if TxLINE uses another).
const WORLD_CUP_COMPETITION_ID = process.env.TXLINE_COMPETITION_ID
  ? Number(process.env.TXLINE_COMPETITION_ID)
  : undefined;

const FLAGS: Record<string, string> = {
  argentina: "🇦🇷", brazil: "🇧🇷", france: "🇫🇷", spain: "🇪🇸", germany: "🇩🇪",
  england: "🏴󠁧󠁢󠁥󠁮󠁧󠁿", portugal: "🇵🇹", netherlands: "🇳🇱", belgium: "🇧🇪", croatia: "🇭🇷",
  uruguay: "🇺🇾", mexico: "🇲🇽", usa: "🇺🇸", "united states": "🇺🇸", japan: "🇯🇵",
  morocco: "🇲🇦", senegal: "🇸🇳", denmark: "🇩🇰", switzerland: "🇨🇭", serbia: "🇷🇸",
  poland: "🇵🇱", "south korea": "🇰🇷", korea: "🇰🇷", canada: "🇨🇦", colombia: "🇨🇴",
  nigeria: "🇳🇬", ecuador: "🇪🇨", ghana: "🇬🇭", cameroon: "🇨🇲", australia: "🇦🇺",
};

function flagFor(name: string): string {
  return FLAGS[name.toLowerCase()] ?? "🏳️";
}
function codeFor(name: string): string {
  return name.replace(/[^A-Za-z]/g, "").slice(0, 3).toUpperCase();
}
function teamFrom(id: number | string, name: string): Team {
  return { id: String(id), name, code: codeFor(name), flag: flagFor(name), rating: 75 };
}

/** TxLINE Fixture (subset we read). */
interface TxFixture {
  Ts: number;
  StartTime: number;
  Competition: string;
  CompetitionId: number;
  FixtureGroupId?: number;
  Participant1Id: number;
  Participant1: string;
  Participant2Id: number;
  Participant2: string;
  FixtureId: number;
  Participant1IsHome?: boolean;
}

function mapFixture(f: TxFixture): Fixture {
  const p1 = teamFrom(f.Participant1Id, f.Participant1);
  const p2 = teamFrom(f.Participant2Id, f.Participant2);
  const homeIsP1 = f.Participant1IsHome !== false;
  const home = homeIsP1 ? p1 : p2;
  const away = homeIsP1 ? p2 : p1;
  const kickoff = new Date(f.StartTime).toISOString();
  const now = Date.now();
  const status: Fixture["status"] =
    f.StartTime > now ? "scheduled" : now - f.StartTime > 2.5 * 3600_000 ? "finished" : "live";
  return {
    id: String(f.FixtureId),
    competition: f.Competition,
    stage: f.Competition,
    groupId: f.FixtureGroupId != null ? String(f.FixtureGroupId) : undefined,
    home,
    away,
    kickoff,
    venue: "—",
    status,
  };
}

// ── GameState (SoccerFixtureStatus) -> GamePhase ─────────────────────────────
const PHASE_MAP: Record<string, GamePhase> = {
  NS: GamePhase.PreMatch,
  H1: GamePhase.FirstHalf,
  HT: GamePhase.HalfTime,
  H2: GamePhase.SecondHalf,
  ET1: GamePhase.ExtraTimeFirstHalf,
  HTET: GamePhase.ExtraTimeHalfTime,
  ET2: GamePhase.ExtraTimeSecondHalf,
  PE: GamePhase.Penalties,
  F: GamePhase.FullTime,
  FET: GamePhase.FullTime,
  FPE: GamePhase.FullTime,
  A: GamePhase.Abandoned,
};
function mapPhase(gameState?: string): GamePhase {
  if (!gameState) return GamePhase.PreMatch;
  return PHASE_MAP[gameState] ?? GamePhase.FirstHalf;
}
function defaultMinuteFor(phase: GamePhase): number {
  switch (phase) {
    case GamePhase.PreMatch: return 0;
    case GamePhase.FirstHalf: return 25;
    case GamePhase.HalfTime: return 45;
    case GamePhase.SecondHalf: return 70;
    default: return 90;
  }
}

// Real TxLINE Scores record (snapshot/stream). Totals live in the numeric
// `Stats` map (1..8 = P1/P2 goals, yellow, red, corners); `Score` carries the
// per-period named breakdown; `Clock.Seconds` is the live match clock.
type Sc = { Goals?: number; YellowCards?: number; RedCards?: number; Corners?: number };
type ScoreObj = { H1?: Sc; HT?: Sc; H2?: Sc; Total?: Sc };
interface TxScores {
  FixtureId?: number;
  fixtureId?: number;
  GameState?: string;
  Seq?: number;
  Ts?: number;
  Participant1IsHome?: boolean;
  Clock?: { Running?: boolean; Seconds?: number };
  Score?: { Participant1?: ScoreObj; Participant2?: ScoreObj };
  Stats?: Record<string, number>;
}

function phaseFrom(gameState: string | undefined, running: boolean, minute: number): GamePhase {
  const gs = (gameState ?? "").toLowerCase();
  if (gs.includes("ht") || gs.includes("half")) return GamePhase.HalfTime;
  if (gs === "ft" || gs.includes("finish") || gs.includes("full") || gs === "f") return GamePhase.FullTime;
  if (gs.includes("pen")) return GamePhase.Penalties;
  if (running) return minute < 45 ? GamePhase.FirstHalf : GamePhase.SecondHalf;
  if (minute >= 90) return GamePhase.FullTime;
  if (minute === 0) return GamePhase.PreMatch;
  return GamePhase.HalfTime;
}

function mapScores(s: TxScores, seq: number, ts: string): ScoreSnapshot {
  const fixtureId = String(s.FixtureId ?? s.fixtureId ?? "");
  const p1Home = s.Participant1IsHome !== false;
  const stats = s.Stats ?? {};
  const hasStats = Object.keys(stats).length > 0;
  const sc1 = s.Score?.Participant1;
  const sc2 = s.Score?.Participant2;

  // total pair from Stats keys (p1key,p2key), oriented to home/away
  const st = (k: number) => Number(stats[String(k)] ?? 0);
  const total = (p1k: number, p2k: number, named: keyof Sc): StatPair => {
    const v1 = hasStats ? st(p1k) : (sc1?.Total?.[named] ?? 0);
    const v2 = hasStats ? st(p2k) : (sc2?.Total?.[named] ?? 0);
    return p1Home ? { home: v1, away: v2 } : { home: v2, away: v1 };
  };
  const per = (half: "H1" | "H2", k: keyof Sc): StatPair => {
    const v1 = sc1?.[half]?.[k] ?? 0;
    const v2 = sc2?.[half]?.[k] ?? 0;
    return p1Home ? { home: v1, away: v2 } : { home: v2, away: v1 };
  };

  const running = s.Clock?.Running === true;
  const minute = Math.min(130, Math.floor((s.Clock?.Seconds ?? 0) / 60));
  const phase = phaseFrom(s.GameState, running, minute);

  return {
    fixtureId,
    seq,
    ts,
    phase,
    minute,
    goals: total(1, 2, "Goals"),
    yellow: total(3, 4, "YellowCards"),
    red: total(5, 6, "RedCards"),
    corners: total(7, 8, "Corners"),
    periods: {
      firstHalf: { goals: per("H1", "Goals"), yellow: per("H1", "YellowCards"), red: per("H1", "RedCards"), corners: per("H1", "Corners") },
      secondHalf: { goals: per("H2", "Goals"), yellow: per("H2", "YellowCards"), red: per("H2", "RedCards"), corners: per("H2", "Corners") },
    },
  };
}

interface TxOdds {
  FixtureId: number;
  MessageId: string;
  Ts: number;
  SuperOddsType: string;
  InRunning?: boolean;
  PriceNames: string[];
  Prices: number[];
  Pct: string[];
}

// part1/draw/part2 (and 1/X/2) -> home/draw/away
const ODDS_KEY_LABELS: Record<string, string> = {
  part1: "home", draw: "draw", part2: "away", "1": "home", X: "draw", "2": "away",
};

function mapOddsBatch(batch: TxOdds[], fixture: Fixture, seq: number, ts: string): OddsSnapshot {
  const markets: OddsMarket[] = [];
  // freshest 1X2 result line (e.g. "1X2_PARTICIPANT_RESULT"); prefer TxLINE's
  // de-margined stable price when present.
  const x2 = batch
    .filter((o) => (o.SuperOddsType ?? "").toUpperCase().startsWith("1X2"))
    .sort((a, b) => b.Ts - a.Ts)[0];
  if (x2) {
    const selections = x2.PriceNames.map((name, i) => {
      const key = ODDS_KEY_LABELS[name] ?? name.toLowerCase();
      const prob = parsePct(x2.Pct?.[i]);
      const price = (x2.Prices?.[i] ?? 0) / 1000; // scaled int
      const label = key === "home" ? fixture.home.code : key === "away" ? fixture.away.code : "Draw";
      return { key, label, price: price || (prob > 0 ? 1 / prob : 0), prevPrice: price, impliedProb: prob };
    });
    markets.push({ type: "match_result", label: "Match result", selections });
  }
  return { fixtureId: fixture.id, seq, ts, markets };
}

function parsePct(s?: string): number {
  if (!s || s === "NA") return 0;
  const n = Number(s);
  return Number.isFinite(n) ? n / 100 : 0;
}

async function getJson<T>(path: string): Promise<T> {
  const url = `${txlineBase()}${path}`;
  let headers = await txlineHeaders();
  let res = await fetch(url, { headers, cache: "no-store" });
  if (res.status === 401) {
    await refreshJwt();
    headers = await txlineHeaders();
    res = await fetch(url, { headers, cache: "no-store" });
  }
  const body = await res.text();
  if (!res.ok) throw new Error(`TxLINE GET ${path} -> ${res.status}: ${body.slice(0, 200)}`);
  return JSON.parse(body) as T;
}

export class LiveSource implements TxLineSource {
  readonly mode = "live" as const;

  async listFixtures(): Promise<Fixture[]> {
    const startEpochDay = Math.floor(Date.now() / 86400000) - 1;
    const q = new URLSearchParams({ startEpochDay: String(startEpochDay) });
    if (WORLD_CUP_COMPETITION_ID) q.set("competitionId", String(WORLD_CUP_COMPETITION_ID));
    const data = await getJson<TxFixture[]>(`/api/fixtures/snapshot?${q}`);
    return data.map(mapFixture).sort((a, b) => +new Date(a.kickoff) - +new Date(b.kickoff));
  }

  async getFixture(id: string): Promise<Fixture | undefined> {
    const all = await this.listFixtures();
    return all.find((f) => f.id === id);
  }

  async getScoreSnapshot(fixture: Fixture): Promise<ScoreSnapshot> {
    const data = await getJson<TxScores[]>(`/api/scores/snapshot/${fixture.id}`);
    const latest = data[data.length - 1];
    return latest
      ? mapScores(latest, latest.Seq ?? data.length, new Date(latest.Ts ?? Date.now()).toISOString())
      : emptyScore(fixture);
  }

  async getOddsSnapshot(fixture: Fixture): Promise<OddsSnapshot> {
    const data = await getJson<TxOdds[]>(`/api/odds/snapshot/${fixture.id}`);
    return mapOddsBatch(data, fixture, data.length, new Date().toISOString());
  }
}

function emptyScore(fixture: Fixture): ScoreSnapshot {
  const z: StatPair = { home: 0, away: 0 };
  return {
    fixtureId: fixture.id,
    seq: 0,
    ts: new Date().toISOString(),
    phase: GamePhase.PreMatch,
    minute: 0,
    goals: { ...z }, yellow: { ...z }, red: { ...z }, corners: { ...z },
    periods: {
      firstHalf: { goals: { ...z }, yellow: { ...z }, red: { ...z }, corners: { ...z } },
      secondHalf: { goals: { ...z }, yellow: { ...z }, red: { ...z }, corners: { ...z } },
    },
  };
}

/**
 * Open the live TxLINE SSE feed for a fixture and emit normalized snapshots.
 * Used by the room engine in live mode. Returns a close() function.
 */
export async function openLiveMatchFeed(
  fixture: Fixture,
  handlers: { onScore(s: ScoreSnapshot): void; onOdds(o: OddsSnapshot): void; onError?(e: unknown): void },
): Promise<() => void> {
  const controller = new AbortController();
  const jwt = await getGuestJwt();
  const token = await getApiToken();
  const headers = {
    Authorization: `Bearer ${jwt}`,
    "X-Api-Token": token,
    Accept: "text/event-stream",
    "Cache-Control": "no-cache",
  };

  let scoreSeq = 0;
  let oddsBuffer: TxOdds[] = [];

  async function consume(path: string, onData: (json: unknown) => void) {
    const res = await fetch(`${txlineBase()}${path}`, { headers, signal: controller.signal });
    if (!res.body) return;
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buf = "";
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buf += decoder.decode(value, { stream: true });
      const frames = buf.split("\n\n");
      buf = frames.pop() ?? "";
      for (const frame of frames) {
        if (frame.includes("event: heartbeat")) continue;
        const dataLine = frame.split("\n").find((l) => l.startsWith("data:"));
        if (!dataLine) continue;
        try {
          onData(JSON.parse(dataLine.slice(5).trim()));
        } catch {
          /* ignore malformed frame */
        }
      }
    }
  }

  // Hydrate immediately from snapshots — the free tier streams only ~every 60s,
  // so without this the room would sit empty until the first SSE frame.
  const jsonHeaders = { Authorization: `Bearer ${jwt}`, "X-Api-Token": token, Accept: "application/json" };
  try {
    const scRes = await fetch(`${txlineBase()}/api/scores/snapshot/${fixture.id}`, { headers: jsonHeaders, signal: controller.signal });
    if (scRes.ok) {
      const arr = (await scRes.json()) as TxScores[];
      const latest = arr[arr.length - 1];
      if (latest) handlers.onScore(mapScores(latest, ++scoreSeq, new Date(latest.Ts ?? Date.now()).toISOString()));
    }
  } catch (e) {
    handlers.onError?.(e);
  }
  try {
    const odRes = await fetch(`${txlineBase()}/api/odds/snapshot/${fixture.id}`, { headers: jsonHeaders, signal: controller.signal });
    if (odRes.ok) {
      oddsBuffer = (await odRes.json()) as TxOdds[];
      handlers.onOdds(mapOddsBatch(oddsBuffer, fixture, oddsBuffer.length, new Date().toISOString()));
    }
  } catch (e) {
    handlers.onError?.(e);
  }

  consume(`/api/scores/stream?fixtureId=${fixture.id}`, (json) => {
    const s = json as TxScores;
    handlers.onScore(mapScores(s, ++scoreSeq, new Date(s.Ts ?? Date.now()).toISOString()));
  }).catch((e) => handlers.onError?.(e));

  consume(`/api/odds/stream?fixtureId=${fixture.id}`, (json) => {
    oddsBuffer = [json as TxOdds, ...oddsBuffer].slice(0, 40);
    handlers.onOdds(mapOddsBatch(oddsBuffer, fixture, oddsBuffer.length, new Date().toISOString()));
  }).catch((e) => handlers.onError?.(e));

  return () => controller.abort();
}
