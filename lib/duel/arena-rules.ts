import type { Axis, Moment } from "@/lib/cards/types";
import type { DuelPlayerSnapshot, ScoreBreakdown } from "./types";

/**
 * Deterministic Arena script: Event → Pressure → Aftershock.
 * Event axis follows Moment kind; Pressure uses minute; Aftershock fills the gap.
 */
export function arenaScript(moment: Pick<Moment, "kind" | "minute">): Axis[] {
  const event: Axis =
    moment.kind === "goal"
      ? "finishing"
      : moment.kind === "yellow" || moment.kind === "red" || moment.kind === "chaos"
        ? "chaos"
        : moment.kind === "corner"
          ? "clutch"
          : "marketShock";
  const pressure: Axis = moment.minute >= 60 ? "clutch" : "aura";
  const used = new Set<Axis>([event, pressure]);
  const aftershock: Axis = !used.has("marketShock")
    ? "marketShock"
    : (["aura", "finishing", "chaos", "clutch"] as Axis[]).find((axis) => !used.has(axis))!;
  return [event, pressure, aftershock];
}

/**
 * Arena effective score = Base Axis + Lineage + Called It + Skill.
 * same-kind +6, same fixture-or-team (non-stacking) +3, Called It +2,
 * lineage cap +8, final cap 120. Rarity never changes power.
 */
export function arenaLineageBonus(
  card: DuelPlayerSnapshot,
  seed: Pick<Moment, "kind" | "fixtureId" | "teamCode">,
): { resonance: number; calledIt: number } {
  if (!card.lineage) return { resonance: 0, calledIt: 0 };
  let resonance = 0;
  let calledIt = 0;
  if (card.lineage.kind === seed.kind) resonance += 6;
  if (
    card.lineage.fixtureId === seed.fixtureId ||
    (!!card.lineage.teamCode && card.lineage.teamCode === seed.teamCode)
  ) {
    resonance += 3;
  }
  if (card.lineage.calledIt) calledIt = 2;
  const capped = Math.min(8, resonance + calledIt);
  if (capped <= resonance) return { resonance: capped, calledIt: 0 };
  return { resonance, calledIt: capped - resonance };
}

export function finalizeScore(parts: Omit<ScoreBreakdown, "total">): ScoreBreakdown {
  return {
    ...parts,
    total: Math.min(120, parts.base + parts.resonance + parts.calledIt + parts.skill),
  };
}
