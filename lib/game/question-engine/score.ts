/**
 * Deterministic candidate ranking — urgency, relevance, resolvability, novelty.
 * Stable hash tie-break; never Math.random.
 */
import { stableHash } from "./ids";
import type { MatchContext, QuestionCandidate } from "./types";

export interface RankedCandidate extends QuestionCandidate {
  score: number;
}

function relevance(c: QuestionCandidate, ctx: MatchContext): number {
  let r = 0.5;
  if (ctx.majorEvent && (c.category === "next-event" || c.category === "scoreboard")) r += 0.35;
  if ((ctx.goalsLast10Min ?? 0) >= 2 && c.ruleId.includes("goal")) r += 0.25;
  if ((ctx.cardsLast5Min ?? 0) >= 2 && c.category === "discipline") r += 0.3;
  if (ctx.redCardActive && c.ruleId.includes("goal")) r += 0.2;
  if (ctx.isComeback && c.ruleId.includes("lead")) r += 0.2;
  if (ctx.waterBreakActive && c.lane === "hydration") r += 0.5;
  if (ctx.atHalftime && c.lane === "break") r += 0.5;
  if (c.category === "market" && ctx.win) {
    const edge = Math.abs(ctx.win.home - ctx.win.away);
    r += Math.min(0.25, edge / 200);
  }
  return Math.min(1, r);
}

function resolvability(c: QuestionCandidate, ctx: MatchContext): number {
  const window = Math.max(1, c.resolutionDeadlineMinute - ctx.score.minute);
  // Shorter windows more likely to resolve cleanly in live play.
  let r = window <= 8 ? 0.9 : window <= 20 ? 0.7 : 0.5;
  if (c.requiresSecondary && !ctx.coverageSecondary) return 0;
  if (c.requiresOnPitchPlayerId && !ctx.onPitchPlayerIds.has(c.requiresOnPitchPlayerId)) return 0;
  if (ctx.feedFreshness === "stale" || ctx.feedFreshness === "paused") r *= 0.2;
  return r;
}

function novelty(c: QuestionCandidate, recentNoveltyKeys: Set<string>): number {
  return recentNoveltyKeys.has(c.noveltyKey) ? 0.15 : 1;
}

export function rankCandidates(
  candidates: QuestionCandidate[],
  ctx: MatchContext,
  recentNoveltyKeys: Set<string>,
  tieSalt = "",
): RankedCandidate[] {
  const ranked = candidates.map((c) => {
    const urg = Math.min(1, Math.max(0, c.urgency));
    const rel = relevance(c, ctx);
    const res = resolvability(c, ctx);
    const nov = novelty(c, recentNoveltyKeys);
    // Weighted sum — deterministic.
    const score =
      urg * 0.35 +
      rel * 0.3 +
      res * 0.25 +
      nov * 0.1 +
      c.priority * 0.01;
    return { ...c, score };
  });

  ranked.sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score;
    const ha = stableHash(`${a.ruleId}:${a.noveltyKey}:${tieSalt}`);
    const hb = stableHash(`${b.ruleId}:${b.noveltyKey}:${tieSalt}`);
    return ha - hb;
  });

  return ranked.filter((c) => resolvability(c, ctx) > 0);
}
