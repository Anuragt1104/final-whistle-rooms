/**
 * Canonical FootballSignal stream derived from TxLINE scores + action ledger.
 */
import type { RawRecord } from "@/lib/explorer/types";
import { STATUS_IDS } from "@/lib/explorer/spec";
import type { GamePhase, MatchEvent, ScoreSnapshot } from "@/lib/txline/types";
import { GamePhase as GP } from "@/lib/txline/types";
import type { FeedFreshness } from "./types";

export type FootballSignal =
  | { kind: "kickoff"; fixtureId: string; seq: number; clockSec: number; ts: number }
  | { kind: "status"; fixtureId: string; seq: number; phase: GamePhase; statusCode: string; note?: string; clockSec: number; ts: number }
  | { kind: "score"; fixtureId: string; seq: number; score: ScoreSnapshot; feedFreshness: FeedFreshness; ts: number }
  | { kind: "goal"; fixtureId: string; seq: number; side: "home" | "away"; playerId?: string; playerName?: string; clockSec: number; actionId: string; ts: number }
  | { kind: "penalty"; fixtureId: string; seq: number; side: "home" | "away"; clockSec: number; actionId: string; ts: number }
  | { kind: "shot"; fixtureId: string; seq: number; side: "home" | "away"; onTarget?: boolean; clockSec: number; actionId: string; ts: number }
  | { kind: "corner"; fixtureId: string; seq: number; side: "home" | "away"; clockSec: number; actionId: string; ts: number }
  | { kind: "danger"; fixtureId: string; seq: number; side: "home" | "away"; clockSec: number; actionId: string; ts: number }
  | { kind: "card"; fixtureId: string; seq: number; side: "home" | "away"; color: "yellow" | "red"; playerId?: string; clockSec: number; actionId: string; ts: number }
  | { kind: "var"; fixtureId: string; seq: number; clockSec: number; actionId: string; ts: number }
  | { kind: "substitution"; fixtureId: string; seq: number; side: "home" | "away"; playerOutId?: string; playerInId?: string; clockSec: number; actionId: string; ts: number }
  | { kind: "injury"; fixtureId: string; seq: number; side: "home" | "away"; playerId?: string; clockSec: number; actionId: string; ts: number }
  | { kind: "lineups"; fixtureId: string; seq: number; confirmed: boolean; onPitchIds: string[]; ts: number }
  | { kind: "water-break"; fixtureId: string; seq: number; active: boolean; clockSec: number; actionId: string; ts: number }
  | { kind: "amend"; fixtureId: string; seq: number; targetActionId: string; ts: number }
  | { kind: "discard"; fixtureId: string; seq: number; targetActionId: string; ts: number }
  | { kind: "reliability"; fixtureId: string; seq: number; level: "ok" | "unreliable_secondary" | "coverage_paused" | "stale"; reason?: string; ts: number }
  | { kind: "tick"; fixtureId: string; seq: number; score: ScoreSnapshot; events: MatchEvent[]; feedFreshness: FeedFreshness; ts: number };

const WATER_BREAK_TEXT = "Water-drinking break";

export function isWaterBreakComment(text: unknown): boolean {
  return typeof text === "string" && text.trim() === WATER_BREAK_TEXT;
}

export function phaseFromStatusId(statusId: number | undefined): GamePhase | undefined {
  if (statusId == null) return undefined;
  const code = STATUS_IDS[statusId]?.code;
  if (!code) return undefined;
  switch (code) {
    case "NS":
    case "P":
      return GP.PreMatch;
    case "H1":
      return GP.FirstHalf;
    case "HT":
      return GP.HalfTime;
    case "H2":
      return GP.SecondHalf;
    case "F":
    case "WET":
      return GP.FullTime;
    case "ET1":
      return GP.ExtraTimeFirstHalf;
    case "HTET":
      return GP.ExtraTimeHalfTime;
    case "ET2":
      return GP.ExtraTimeSecondHalf;
    case "PE":
    case "WPE":
      return GP.Penalties;
    case "FET":
    case "FPE":
      return GP.Finished;
    case "A":
      return GP.Abandoned;
    case "C":
      return GP.Cancelled;
    case "TXCC":
    case "TXCS":
      return GP.CoveragePaused;
    case "I":
      return GP.HalfTime; // paused mid-match
    default:
      return undefined;
  }
}

export function freshnessFrom(lastFeedAt: number, now = Date.now(), phase?: GamePhase): FeedFreshness {
  if (phase === GP.CoveragePaused || phase === GP.Cancelled) return "paused";
  if (lastFeedAt <= 0) return "waiting";
  if (now - lastFeedAt > 20_000) return "stale";
  return "fresh";
}

type AnyMap = Record<string, unknown>;
const asMap = (v: unknown): AnyMap =>
  v && typeof v === "object" && !Array.isArray(v) ? (v as AnyMap) : {};
const str = (v: unknown): string | undefined => {
  if (v == null) return undefined;
  const s = String(v).trim();
  return s || undefined;
};
const num = (v: unknown, fb = 0): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : fb;
};

/** Parse raw TxLINE action records into FootballSignals (pre-ledger). */
export function signalsFromRawActions(fixtureId: string, records: RawRecord[]): FootballSignal[] {
  const out: FootballSignal[] = [];
  const ordered = [...records].sort((a, b) => num(a.Seq) - num(b.Seq));
  for (const record of ordered) {
    const seq = num(record.Seq);
    const ts = num(record.Ts, Date.now());
    const clockSec = Math.max(0, Math.floor(num(record.Clock?.Seconds)));
    const data = asMap(record.Data);
    const action = record.Action ?? "";
    const actionId = str(record.Id) ?? `${action}:${seq}`;

    if (action === "action_discarded") {
      const target = str(data.ActionId ?? data.TargetId ?? data.Id);
      if (target) out.push({ kind: "discard", fixtureId, seq, targetActionId: target, ts });
      continue;
    }
    if (action === "action_amend") {
      const target = str(data.ActionId ?? data.TargetId ?? data.Id);
      if (target) out.push({ kind: "amend", fixtureId, seq, targetActionId: target, ts });
      continue;
    }
    if (action === "comment" || action === "match_comment") {
      const text = data.Text ?? data.text;
      if (isWaterBreakComment(text)) {
        out.push({ kind: "water-break", fixtureId, seq, active: true, clockSec, actionId, ts });
      }
      continue;
    }
    if (action === "unreliable_secondary" || action === "coverage_secondary_off") {
      out.push({ kind: "reliability", fixtureId, seq, level: "unreliable_secondary", reason: action, ts });
      continue;
    }
    // Match events are emitted after ledger confirm — raw parser only tags kinds.
  }
  return out;
}

/** Build a tick signal from room applyTick inputs. */
export function tickSignal(
  score: ScoreSnapshot,
  events: MatchEvent[],
  feedFreshness: FeedFreshness,
): FootballSignal {
  return {
    kind: "tick",
    fixtureId: score.fixtureId,
    seq: score.seq,
    score,
    events,
    feedFreshness,
    ts: score.updatedAt ?? Date.now(),
  };
}
