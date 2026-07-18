/**
 * Live Call cadence:
 * - 1 main + optional quick (max 2 active)
 * - 3–4′ refresh (2′ on major events)
 * - continue past 86′ through AT/ET/pens
 * - HT break deck + hydration 2-question deck
 */
import { GamePhase, isLivePhase } from "@/lib/txline/types";
import type { MatchContext, QuestionLane, QuestionSpec } from "./types";

export const MAX_ACTIVE = 2;
export const NORMAL_GAP_MIN = 4;
export const MAJOR_GAP_MIN = 2;
export const HYDRATION_DECK_SIZE = 2;
export const HT_DECK_SIZE = 2;

export function canGenerate(ctx: MatchContext, active: QuestionSpec[], lastOpenClockSec: number): boolean {
  if (ctx.feedFreshness === "stale" || ctx.feedFreshness === "paused") return false;
  if (ctx.phase === GamePhase.Cancelled || ctx.phase === GamePhase.CoveragePaused) return false;
  if (ctx.phase === GamePhase.Finished || ctx.phase === GamePhase.Abandoned) return false;

  // HT / water-break decks are allowed while not "live".
  if (ctx.atHalftime || ctx.waterBreakActive) {
    return active.filter((q) => q.status === "open" || q.status === "locked").length < MAX_ACTIVE;
  }

  if (!isLivePhase(ctx.phase) && ctx.phase !== GamePhase.ExtraTimeHalfTime) {
    // Allow FullTime waiting ET / pens waiting — only if clock still advancing zones.
    if (
      ctx.phase !== GamePhase.FullTime &&
      ctx.phase !== GamePhase.Penalties &&
      ctx.phase !== GamePhase.ExtraTimeFirstHalf &&
      ctx.phase !== GamePhase.ExtraTimeSecondHalf
    ) {
      return false;
    }
  }

  const live = active.filter((q) => q.status === "open" || q.status === "locked" || q.status === "scheduled");
  if (live.length >= MAX_ACTIVE) return false;

  const gapMin = ctx.majorEvent ? MAJOR_GAP_MIN : NORMAL_GAP_MIN;
  const gapSec = gapMin * 60;
  if (lastOpenClockSec > 0 && ctx.clockSec - lastOpenClockSec < gapSec && !ctx.majorEvent) {
    return false;
  }
  // Major events only need 2′ gap.
  if (ctx.majorEvent && lastOpenClockSec > 0 && ctx.clockSec - lastOpenClockSec < MAJOR_GAP_MIN * 60) {
    return false;
  }

  return true;
}

export function preferredLane(ctx: MatchContext, active: QuestionSpec[]): QuestionLane {
  if (ctx.waterBreakActive) return "hydration";
  if (ctx.atHalftime) return "break";
  const hasMain = active.some(
    (q) => q.lane === "main" && (q.status === "open" || q.status === "locked"),
  );
  if (!hasMain) return "main";
  return "quick";
}

export function slotsToOpen(ctx: MatchContext, active: QuestionSpec[]): number {
  if (ctx.waterBreakActive) {
    const open = active.filter((q) => q.lane === "hydration" && q.status !== "settled" && q.status !== "void").length;
    return Math.max(0, HYDRATION_DECK_SIZE - open);
  }
  if (ctx.atHalftime) {
    const open = active.filter((q) => q.lane === "break" && q.status !== "settled" && q.status !== "void").length;
    return Math.max(0, HT_DECK_SIZE - open);
  }
  const live = active.filter((q) => q.status === "open" || q.status === "locked" || q.status === "scheduled");
  return Math.max(0, MAX_ACTIVE - live.length);
}
