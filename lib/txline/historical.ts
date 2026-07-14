/**
 * Historical / replay feed for finished fixtures.
 *
 * Prefer TxLINE GET /api/scores/historical/{fixtureId}. If that window misses
 * (fixtures outside 6h–2wk), fall back to the finite /api/scores/updates log
 * (same source the Feed Explorer uses).
 *
 * Emits paced ScoreSnapshot ticks so the room engine's applyTick can mint
 * Moments and run Micro-Plays identically to live.
 */
import { fetchFullLog } from "@/lib/explorer/txodds";
import type { RawRecord } from "@/lib/explorer/types";
import { getApiToken, getGuestJwt, refreshJwt, txlineBase } from "@/lib/txline/auth";
import { mapScores } from "@/lib/txline/live";
import {
  GamePhase,
  type Fixture,
  type MatchEvent,
  type OddsSnapshot,
  type ScoreSnapshot,
} from "@/lib/txline/types";
import { normalizeMatchRecords } from "@/lib/txline/match-intelligence";

async function txGet(path: string, accept = "application/json"): Promise<Response> {
  const headers = {
    Authorization: `Bearer ${await getGuestJwt()}`,
    "X-Api-Token": await getApiToken(),
    Accept: accept,
  };
  let res = await fetch(`${txlineBase()}${path}`, { headers, cache: "no-store" });
  if (res.status === 401) {
    await refreshJwt();
    res = await fetch(`${txlineBase()}${path}`, {
      headers: {
        Authorization: `Bearer ${await getGuestJwt()}`,
        "X-Api-Token": await getApiToken(),
        Accept: accept,
      },
      cache: "no-store",
    });
  }
  return res;
}

function recordToScore(r: RawRecord, seq: number): ScoreSnapshot | null {
  // Only records with score/stats/clock are useful for diffs
  if (!r.Score && !r.Stats && r.Clock == null) return null;
  try {
    return mapScores(r as never, r.Seq ?? seq, new Date(r.Ts ?? Date.now()).toISOString());
  } catch {
    return null;
  }
}

/**
 * Build an ordered list of score snapshots for replay.
 * Dedupes consecutive identical scorelines; keeps clock advances.
 */
export async function loadHistoricalScores(fixtureId: string): Promise<ScoreSnapshot[]> {
  // 1) Official historical endpoint
  try {
    const res = await txGet(`/api/scores/historical/${fixtureId}`);
    if (res.ok) {
      const data = await res.json();
      const arr = Array.isArray(data) ? data : data?.scores ?? data?.records ?? [];
      const snaps: ScoreSnapshot[] = [];
      let i = 0;
      for (const raw of arr) {
        const s = recordToScore(raw as RawRecord, ++i);
        if (s) snaps.push(s);
      }
      if (snaps.length >= 2) return canonicalizeHistoricalScores(snaps);
    }
  } catch {
    /* fall through */
  }

  // 2) Full updates log fallback
  const log = await fetchFullLog(fixtureId);
  const snaps: ScoreSnapshot[] = [];
  let i = 0;
  for (const r of log.records) {
    const s = recordToScore(r, ++i);
    if (s) snaps.push(s);
  }
  return canonicalizeHistoricalScores(snaps);
}

/**
 * Turn TxLINE's raw updates log into one replayable match. The upstream log can
 * contain clock-zero reset records and provisional full-time frames at the end
 * of regulation even when extra time later starts. Those frames are valid audit
 * history but are not valid terminal UI states.
 */
export function canonicalizeHistoricalScores(snaps: ScoreSnapshot[]): ScoreSnapshot[] {
  if (snaps.length === 0) return snaps;
  const ordered = [...snaps].sort((a, b) => a.seq - b.seq || a.updatedAt - b.updatedAt);
  const cleaned: ScoreSnapshot[] = [];
  let started = false;
  let maxMinute = 0;
  let maxClock = 0;
  let maxHomeGoals = 0;
  let maxAwayGoals = 0;

  for (const raw of ordered) {
    maxHomeGoals = Math.max(maxHomeGoals, raw.goals.home);
    maxAwayGoals = Math.max(maxAwayGoals, raw.goals.away);
    const terminal = raw.phase === GamePhase.FullTime || raw.phase === GamePhase.Finished || raw.phase === GamePhase.Abandoned;
    const hasPlay = raw.running || raw.minute > 0 || raw.goals.home + raw.goals.away + raw.corners.home + raw.corners.away > 0;
    if (hasPlay) started = true;
    if (started && raw.phase === GamePhase.PreMatch && raw.minute === 0) continue;
    // All terminal frames are collapsed into the single authoritative frame
    // appended below. This is what lets a 1-1 regulation whistle resume into ET.
    if (terminal) continue;

    let cur = raw;
    if (raw.running) {
      maxMinute = Math.max(maxMinute, raw.minute);
      maxClock = Math.max(maxClock, raw.clockSeconds);
      if (raw.minute < maxMinute || raw.clockSeconds < maxClock) {
        cur = { ...raw, minute: maxMinute, clockSeconds: maxClock };
      }
    } else {
      maxMinute = Math.max(maxMinute, raw.minute);
      maxClock = Math.max(maxClock, raw.clockSeconds);
    }
    cleaned.push(cur);
  }

  if (cleaned.length === 0) cleaned.push(ordered[0]);
  const out: ScoreSnapshot[] = [cleaned[0]];
  for (let i = 1; i < cleaned.length; i++) {
    const prev = out[out.length - 1];
    const cur = cleaned[i];
    const changed =
      cur.goals.home !== prev.goals.home ||
      cur.goals.away !== prev.goals.away ||
      cur.corners.home !== prev.corners.home ||
      cur.corners.away !== prev.corners.away ||
      cur.yellow.home !== prev.yellow.home ||
      cur.yellow.away !== prev.yellow.away ||
      cur.red.home !== prev.red.home ||
      cur.red.away !== prev.red.away ||
      cur.phase !== prev.phase ||
      cur.minute !== prev.minute;
    if (changed) out.push(cur);
  }
  const last = out[out.length - 1];
  out.push({
    ...last,
    seq: Math.max(last.seq + 1, ordered[ordered.length - 1].seq),
    phase: GamePhase.Finished,
    minute: maxMinute,
    clockSeconds: maxClock,
    running: false,
    goals: { home: maxHomeGoals, away: maxAwayGoals },
  });
  return out;
}

export interface HistoricalFeedHandlers {
  onScore(s: ScoreSnapshot, events?: MatchEvent[]): void;
  onOdds?(o: OddsSnapshot): void;
  onError?(e: unknown): void;
  onDone?(): void;
}

/**
 * Pace historical snapshots into the room. Returns a close() that stops the timer.
 * SIM_SECONDS_PER_MATCH_MINUTE controls speed (same as simulation).
 */
export async function openHistoricalMatchFeed(
  fixture: Fixture,
  handlers: HistoricalFeedHandlers,
): Promise<() => void> {
  let closed = false;
  let timer: ReturnType<typeof setTimeout> | null = null;

  try {
    const snaps = await loadHistoricalScores(fixture.id);
    if (snaps.length === 0) {
      handlers.onError?.(new Error("No historical score data for fixture"));
      handlers.onDone?.();
      return () => {
        closed = true;
      };
    }

    const secondsPerMin = (() => {
      const n = Number(process.env.SIM_SECONDS_PER_MATCH_MINUTE);
      return Number.isFinite(n) && n > 0 ? n : 1.5;
    })();

    let verifiedEvents: MatchEvent[] = [];
    try {
      const log = await fetchFullLog(fixture.id);
      const intel = normalizeMatchRecords(fixture, log.records);
      verifiedEvents = intel.events.map((event) => ({
        fixtureId: fixture.id,
        seq: event.seq,
        ts: new Date(event.ts || Date.now()).toISOString(),
        minute: event.minute,
        phase: GamePhase.FirstHalf,
        kind: event.kind,
        side: event.side,
        label: event.label,
        sourceEventId: event.sourceEventId,
        playerId: event.playerId,
        playerName: event.playerName,
        imageUrl: event.playerPhotoUrl,
        secondaryPlayerId: event.secondaryPlayerId,
        secondaryPlayerName: event.secondaryPlayerName,
        teamCode: event.teamCode,
        artKey: `${event.kind}:${event.teamCode.toLowerCase()}`,
      }));
    } catch {
      // Score-delta events remain the verified team-level fallback.
    }

    let idx = 0;
    let lastEventSeq = -1;
    const tick = () => {
      if (closed) return;
      if (idx >= snaps.length) {
        handlers.onDone?.();
        return;
      }
      const cur = snaps[idx++];
      const events = verifiedEvents
        .filter((event) => event.seq > lastEventSeq && event.seq <= cur.seq)
        .map((event) => ({ ...event, phase: cur.phase }));
      if (events.length) lastEventSeq = Math.max(...events.map((event) => event.seq));
      handlers.onScore(cur, events);
      if (idx >= snaps.length) {
        handlers.onDone?.();
        return;
      }
      const next = snaps[idx];
      const minuteDelta = Math.max(0.25, Math.abs(next.minute - cur.minute) || 0.5);
      const delay = Math.min(8000, Math.max(200, minuteDelta * secondsPerMin * 1000));
      timer = setTimeout(tick, delay);
    };
    tick();
  } catch (e) {
    handlers.onError?.(e);
    handlers.onDone?.();
  }

  return () => {
    closed = true;
    if (timer) clearTimeout(timer);
  };
}

/** True when a fixture should use historical replay instead of live SSE. */
export function shouldReplayFixture(fixture: Fixture): boolean {
  if (fixture.status === "finished") return true;
  const kickoffMs = Date.parse(fixture.kickoff);
  if (
    fixture.status === "scheduled" &&
    Number.isFinite(kickoffMs) &&
    kickoffMs < Date.now() - 3 * 3600_000
  ) {
    return true;
  }
  return false;
}
