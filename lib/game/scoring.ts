/** Points rules shared by Tournament Draft (team bonus) and Next Swing. */
import type { MatchEvent } from "@/lib/txline/types";

export const TEAM_BONUS = {
  goal: 50,
  corner: 4,
  opponentRed: 20,
  leadAtFullTime: 30,
};

/** Points a member earns from a single event for the side they drafted. */
export function teamBonusForEvent(event: MatchEvent, side: "home" | "away"): number {
  if (!event.side) return 0;
  if (event.kind === "goal" && event.side === side) return TEAM_BONUS.goal;
  if (event.kind === "corner" && event.side === side) return TEAM_BONUS.corner;
  if (event.kind === "red" && event.side !== side) return TEAM_BONUS.opponentRed;
  return 0;
}

/** Streak multiplier — rewards consecutive correct Next Swing calls. */
export function streakMultiplier(streak: number): number {
  return 1 + Math.min(streak, 6) * 0.2;
}

/** Points for a correct prediction, given the member's CURRENT streak. */
export function swingPoints(basePoints: number, streak: number): number {
  return Math.round(basePoints * streakMultiplier(streak));
}
