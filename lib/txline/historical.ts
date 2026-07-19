/**
 * Historical / replay feed for finished fixtures.
 *
 * Prefer TxLINE GET /api/scores/historical/{fixtureId}. If that window misses
 * (fixtures outside 6h–2wk), fall back to the finite /api/scores/updates log
 * (same source the Feed Explorer uses).
 *
 * Emits paced ScoreSnapshot ticks so the room engine's applyTick can mint
 * Moments and run Micro-Plays identically to live. Supports pause / seek / speed.
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
  if (!r.Score && !r.Stats && r.Clock == null) return null;
  try {
    return mapScores(r as never, r.Seq ?? seq, new Date(r.Ts ?? Date.now()).toISOString());
  } catch {
    return null;
  }
}

export async function loadHistoricalScores(fixtureId: string): Promise<ScoreSnapshot[]> {
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
    const terminal =
      raw.phase === GamePhase.FullTime ||
      raw.phase === GamePhase.Finished ||
      raw.phase === GamePhase.Abandoned;
    const hasPlay =
      raw.running ||
      raw.minute > 0 ||
      raw.goals.home + raw.goals.away + raw.corners.home + raw.corners.away > 0;
    const clockZero = raw.minute <= 0 && raw.clockSeconds <= 0;
    // TxLINE reset frames are not consistently labelled PreMatch. Some retain
    // the surrounding half/extra-time phase and cumulative 1–1 statistics.
    // Once play has begun, clock-zero is therefore the stable reset signal.
    if (started && clockZero) continue;
    if (hasPlay) started = true;
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
  onStateChange?(state: HistoricalReplayControlState): void;
}

export interface HistoricalReplayControlState {
  active: boolean;
  paused: boolean;
  currentMinute: number;
  totalMinutes: number;
  speed: number;
}

export interface HistoricalFeedHandle {
  close(): void;
  pause(): void;
  play(): void;
  setSpeed(speed: number): void;
  seek(minute: number): void;
  /** Stream every intermediate frame rapidly, then pause at the target. */
  advanceTo(minute: number): void;
  getState(): HistoricalReplayControlState;
}

export function eventsForReplayFrame(
  events: MatchEvent[],
  emittedEventIds: ReadonlySet<string>,
  frameMinute: number,
): MatchEvent[] {
  return events
    .filter(
      (event) =>
        event.minute <= frameMinute &&
        !emittedEventIds.has(
          event.sourceEventId ?? `${event.seq}:${event.kind}:${event.side ?? "-"}`,
        ),
    )
    .sort((a, b) => a.minute - b.minute || a.seq - b.seq);
}

/** Pin lagging cumulative frames to actions confirmed for the visible minute. */
export function reconcileReplayScore(
  score: ScoreSnapshot,
  confirmedThroughFrame: MatchEvent[],
): ScoreSnapshot {
  const counts = {
    goals: { home: 0, away: 0 },
    yellow: { home: 0, away: 0 },
    red: { home: 0, away: 0 },
    corners: { home: 0, away: 0 },
  };
  for (const event of confirmedThroughFrame) {
    if (!event.side) continue;
    if (event.kind === "goal") counts.goals[event.side] += 1;
    if (event.kind === "yellow") counts.yellow[event.side] += 1;
    if (event.kind === "red") counts.red[event.side] += 1;
    if (event.kind === "corner") counts.corners[event.side] += 1;
  }
  return {
    ...score,
    goals: {
      home: Math.max(score.goals.home, counts.goals.home),
      away: Math.max(score.goals.away, counts.goals.away),
    },
    yellow: {
      home: Math.max(score.yellow.home, counts.yellow.home),
      away: Math.max(score.yellow.away, counts.yellow.away),
    },
    red: {
      home: Math.max(score.red.home, counts.red.home),
      away: Math.max(score.red.away, counts.red.away),
    },
    corners: {
      home: Math.max(score.corners.home, counts.corners.home),
      away: Math.max(score.corners.away, counts.corners.away),
    },
  };
}

/**
 * A guided beat represents the complete observable state of a match minute.
 * TxLINE may emit several frames at 9′ (clock, then confirmed goal). Pause only
 * before the first later-minute frame so the event is never left behind.
 */
export function shouldPauseBeforeReplayFrame(
  _currentMinute: number,
  nextMinute: number,
  targetMinute: number,
): boolean {
  return nextMinute > targetMinute;
}

export function interpolateReplayCheckpoint(
  previous: ScoreSnapshot,
  targetMinute: number,
): ScoreSnapshot {
  return {
    ...previous,
    minute: targetMinute,
    clockSeconds: targetMinute * 60,
    running: true,
  };
}

/**
 * Pace historical snapshots into the room. Returns a handle with pause/seek/speed.
 */
export async function openHistoricalMatchFeed(
  fixture: Fixture,
  handlers: HistoricalFeedHandlers,
): Promise<HistoricalFeedHandle> {
  let closed = false;
  let paused = false;
  let speed = 1;
  let timer: ReturnType<typeof setTimeout> | null = null;
  let idx = 0;
  const emittedEventIds = new Set<string>();
  let snaps: ScoreSnapshot[] = [];
  let verifiedEvents: MatchEvent[] = [];
  let currentMinute = 0;
  let totalMinutes = 90;
  let stopAtMinute: number | null = null;
  let rapidAdvance = false;

  const emitState = () => {
    handlers.onStateChange?.(getState());
  };

  const getState = (): HistoricalReplayControlState => ({
    active: !closed && snaps.length > 0 && idx < snaps.length,
    paused,
    currentMinute,
    totalMinutes,
    speed,
  });

  const clearTimer = () => {
    if (timer) clearTimeout(timer);
    timer = null;
  };

  const scheduleNext = () => {
    clearTimer();
    if (closed || paused || idx >= snaps.length) return;
    const cur = snaps[Math.max(0, idx - 1)] ?? snaps[0];
    const next = snaps[idx];
    if (!next) return;
    const minuteDelta = Math.max(0.25, Math.abs(next.minute - cur.minute) || 0.5);
    const base = (() => {
      const n = Number(process.env.SIM_SECONDS_PER_MATCH_MINUTE);
      return Number.isFinite(n) && n > 0 ? n : 1.5;
    })();
    const delay = rapidAdvance
      ? 24
      : Math.min(8000, Math.max(80, (minuteDelta * base * 1000) / Math.max(0.25, speed)));
    timer = setTimeout(tick, delay);
  };

  const emitAt = (i: number) => {
    const cur = snaps[i];
    if (!cur) return;
    currentMinute = cur.minute;
    const confirmedThroughFrame = verifiedEvents.filter(
      (event) => event.minute <= cur.minute,
    );
    const events = eventsForReplayFrame(verifiedEvents, emittedEventIds, cur.minute)
      .map((event) => ({ ...event, phase: cur.phase }));
    for (const event of events) {
      emittedEventIds.add(
        event.sourceEventId ?? `${event.seq}:${event.kind}:${event.side ?? "-"}`,
      );
    }
    handlers.onScore(reconcileReplayScore(cur, confirmedThroughFrame), events);
    emitState();
  };

  const tick = () => {
    if (closed || paused) return;
    if (idx >= snaps.length) {
      emitState();
      handlers.onDone?.();
      return;
    }
    const next = snaps[idx];
    if (
      stopAtMinute != null &&
      next &&
      shouldPauseBeforeReplayFrame(currentMinute, next.minute, stopAtMinute)
    ) {
      if (currentMinute < stopAtMinute) {
        const previous = snaps[Math.max(0, idx - 1)] ?? snaps[0];
        const checkpoint = interpolateReplayCheckpoint(previous, stopAtMinute);
        currentMinute = checkpoint.minute;
        handlers.onScore(checkpoint, []);
      }
      paused = true;
      rapidAdvance = false;
      stopAtMinute = null;
      emitState();
      return;
    }
    emitAt(idx);
    idx += 1;
    if (idx >= snaps.length) {
      emitState();
      handlers.onDone?.();
      return;
    }
    scheduleNext();
  };

  try {
    snaps = await loadHistoricalScores(fixture.id);
    if (snaps.length === 0) {
      handlers.onError?.(new Error("No historical score data for fixture"));
      handlers.onDone?.();
      return {
        close: () => {
          closed = true;
        },
        pause: () => undefined,
        play: () => undefined,
        setSpeed: () => undefined,
        seek: () => undefined,
        advanceTo: () => undefined,
        getState,
      };
    }
    totalMinutes = Math.max(90, ...snaps.map((s) => s.minute));

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
      /* score-delta fallback */
    }

    emitState();
    tick();
  } catch (e) {
    handlers.onError?.(e);
    handlers.onDone?.();
  }

  return {
    close: () => {
      closed = true;
      clearTimer();
      emitState();
    },
    pause: () => {
      paused = true;
      clearTimer();
      emitState();
    },
    play: () => {
      if (closed) return;
      stopAtMinute = null;
      rapidAdvance = false;
      paused = false;
      emitState();
      scheduleNext();
    },
    setSpeed: (s: number) => {
      speed = Math.min(4, Math.max(0.25, s));
      emitState();
      if (!paused && !closed) scheduleNext();
    },
    seek: (minute: number) => {
      if (!snaps.length) return;
      const target = Math.max(0, minute);
      let best = 0;
      for (let i = 0; i < snaps.length; i++) {
        if (snaps[i].minute <= target) best = i;
      }
      // Reset event high-water so events re-emit from frame (rooms dedupe by id).
      emittedEventIds.clear();
      idx = best;
      paused = true;
      stopAtMinute = null;
      rapidAdvance = false;
      clearTimer();
      emitAt(best);
      idx = best + 1;
      emitState();
    },
    advanceTo: (minute: number) => {
      if (closed || !snaps.length) return;
      const target = Math.max(currentMinute, Math.min(totalMinutes, minute));
      if (currentMinute >= target) {
        paused = true;
        emitState();
        return;
      }
      stopAtMinute = target;
      rapidAdvance = true;
      paused = false;
      emitState();
      scheduleNext();
    },
    getState,
  };
}

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
