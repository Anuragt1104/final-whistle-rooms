/**
 * Settlement resolvers — reuses nextswing tryResolve / forceResolve and
 * adds correction-safe void handling for the V2 coordinator.
 */
import {
  forceResolve,
  lockSnapshot,
  tryResolve,
  type SwingPrompt,
} from "@/lib/game/nextswing";
import type { MatchEvent, ScoreSnapshot } from "@/lib/txline/types";
import type { WinChance } from "@/lib/engine/pulse";
import type { QuestionSpec } from "./types";

export { tryResolve, forceResolve, lockSnapshot };

export function asSwingPrompt(q: QuestionSpec): SwingPrompt {
  return {
    id: q.id,
    question: q.question,
    options: q.options,
    resolver: q.resolver,
    basePoints: q.basePoints,
    locksAtMinute: q.locksAtMinute,
    status: q.status === "settled" || q.status === "void" || q.status === "corrected"
      ? "settled"
      : q.status === "locked"
        ? "locked"
        : "open",
    winningKey: q.winningKey,
    createdAt: q.createdAt,
    openedAtMinute: q.openedAtMinute,
    openedAtSeq: q.openedAtSeq,
    lockState: q.lockState,
  };
}

export function resolveQuestion(
  q: QuestionSpec,
  events: MatchEvent[],
  score: ScoreSnapshot,
  win: WinChance,
): string | null {
  if (q.status !== "locked") return null;
  return tryResolve(asSwingPrompt(q), events, score, win);
}

export function forceResolveQuestion(
  q: QuestionSpec,
  score: ScoreSnapshot,
  win: WinChance,
): string {
  return forceResolve(asSwingPrompt(q), score, win);
}

/** Deadline clock (seconds) for force-settle when evidence never arrives. */
export function pastResolutionDeadline(q: QuestionSpec, clockSec: number, phaseTerminal: boolean): boolean {
  if (phaseTerminal) return true;
  return clockSec >= q.resolutionDeadlineClockSec;
}
