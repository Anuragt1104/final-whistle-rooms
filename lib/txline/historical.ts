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
  type OddsSnapshot,
  type ScoreSnapshot,
} from "@/lib/txline/types";

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
      if (snaps.length >= 2) return thinSnapshots(snaps);
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
  return thinSnapshots(snaps);
}

function thinSnapshots(snaps: ScoreSnapshot[]): ScoreSnapshot[] {
  if (snaps.length === 0) return snaps;
  const out: ScoreSnapshot[] = [snaps[0]];
  for (let i = 1; i < snaps.length; i++) {
    const prev = out[out.length - 1];
    const cur = snaps[i];
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
  // ensure a terminal full-time snapshot
  const last = out[out.length - 1];
  if (last.phase < GamePhase.FullTime) {
    out.push({ ...last, phase: GamePhase.FullTime, running: false });
  }
  return out;
}

export interface HistoricalFeedHandlers {
  onScore(s: ScoreSnapshot): void;
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

    let idx = 0;
    const tick = () => {
      if (closed) return;
      if (idx >= snaps.length) {
        handlers.onDone?.();
        return;
      }
      const cur = snaps[idx++];
      handlers.onScore(cur);
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
