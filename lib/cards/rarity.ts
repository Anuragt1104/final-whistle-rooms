/** Market Rarity from odds likelihood / swing (ADR-0004). */
import type { OddsSandwich, RarityStars } from "./types";

/**
 * Stars from how unlikely the event was before it happened + swing size.
 * priorHomeProb in 0..1; for away goals use 1 - prior - draw approx via sandwich.
 */
export function marketRarity(
  kind: string,
  priorImplied: number,
  sandwich: OddsSandwich,
): RarityStars {
  const before = Math.max(0.01, Math.min(0.99, priorImplied));
  const afterHome = sandwich.after.home;
  const swing = Math.abs(afterHome - sandwich.before.home);

  // rarer when prior was low (upset) or swing was large
  let score = (1 - before) * 3 + swing * 8;
  if (kind === "red") score += 1.2;
  if (kind === "goal") score += 0.4;
  if (kind === "market-swing") score += swing * 4;

  if (score >= 4.2) return 5;
  if (score >= 3.2) return 4;
  if (score >= 2.2) return 3;
  if (score >= 1.2) return 2;
  return 1;
}

/** Pack weight contribution from a Moment (rarity + Called It). */
export function momentPackWeight(rarity: RarityStars, calledIt: boolean): number {
  const base = [0, 1, 1.4, 2, 3, 4.5][rarity] ?? 1;
  return calledIt ? base * 1.35 : base;
}
