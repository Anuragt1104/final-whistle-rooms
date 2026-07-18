import { AXES, type Axis } from "@/lib/cards/types";
import type {
  DuelParticipant,
  DuelPlayerSnapshot,
  DuelState,
  HiddenSubmission,
} from "./types";

export function stadiumOpponentId(state: DuelState, actorId: string): string {
  if (state.opponentType === "house") {
    return actorId === "house" ? state.challengerId : "house";
  }
  if (actorId === state.challengerId) {
    if (!state.opponentId) throw new Error("opponent has not joined");
    return state.opponentId;
  }
  return state.challengerId;
}

export function stadiumParticipant(state: DuelState, fanId: string): DuelParticipant {
  const found = fanId === "house" ? state.house : state.participants[fanId];
  if (!found) throw new Error("not a duel participant");
  return found;
}

export function availableCards(p: DuelParticipant) {
  return p.cards.filter((card) => !p.usedCardIds.includes(card.id));
}

export function cardRating(card: DuelPlayerSnapshot): number {
  return AXES.reduce((sum, axis) => sum + card.axes[axis], 0) / AXES.length;
}

/** Deterministic timeout auto-play: lowest unused card, no Skill. */
export function lowestUnusedCard(p: DuelParticipant): DuelPlayerSnapshot {
  const cards = availableCards(p).sort(
    (a, b) => cardRating(a) - cardRating(b) || a.id.localeCompare(b.id),
  );
  if (!cards[0]) throw new Error("no unused cards");
  return cards[0];
}

export function houseAxisChoice(card: DuelPlayerSnapshot): Axis {
  return [...AXES].sort(
    (a, b) => card.axes[b] - card.axes[a] || AXES.indexOf(a) - AXES.indexOf(b),
  )[0];
}

export function assertCardLegal(
  p: DuelParticipant,
  submission: HiddenSubmission,
  alreadySubmitted: boolean,
) {
  if (alreadySubmitted) throw new Error("already submitted");
  const card = p.cards.find((candidate) => candidate.id === submission.cardId);
  if (!card || p.usedCardIds.includes(card.id)) throw new Error("card is unavailable");
  if (submission.skillId) {
    const skill = p.skills.find((candidate) => candidate.id === submission.skillId);
    if (!skill || p.usedSkillIds.includes(skill.id)) throw new Error("skill is unavailable");
  }
}

export function earlyFinishWinner(wins: Record<string, number>): string | null | undefined {
  const reached = Object.entries(wins).find(([, count]) => count >= 2);
  return reached?.[0];
}
