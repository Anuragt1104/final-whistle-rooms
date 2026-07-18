import crypto from "crypto";
import { ROSTER } from "@/lib/cards/roster";
import { cardCommitment } from "./engine";
import type { CardCommitment, DuelParticipant, DuelPlayerSnapshot, DuelState } from "./types";

const HOUSE_ID = "house";

function hash(...parts: string[]) {
  return crypto.createHash("sha256").update(parts.join(":")).digest("hex");
}

function averageRating(cards: DuelPlayerSnapshot[]) {
  return (
    cards.reduce(
      (total, card) =>
        total + Object.values(card.axes).reduce((sum, value) => sum + value, 0) / 5,
      0,
    ) / cards.length
  );
}

/** Fixed approved roster, rating-band matching, ordered-hand SHA-256 commitments. */
export function buildHouseParticipant(
  duelId: string,
  fanCards: DuelPlayerSnapshot[],
): DuelParticipant {
  const target = averageRating(fanCards);
  const seed = Buffer.from(hash(duelId), "hex");
  const candidates = ROSTER.map((card) => ({
    card,
    distance: Math.abs(
      Object.values(card.axes).reduce((sum, value) => sum + value, 0) / 5 - target,
    ),
  })).sort((a, b) => a.distance - b.distance || a.card.id.localeCompare(b.card.id));
  const band = candidates.slice(0, Math.max(6, Math.ceil(candidates.length / 3)));
  const chosen = [...band]
    .sort(
      (a, b) =>
        seed[a.card.id.length % seed.length] - seed[b.card.id.length % seed.length] ||
        a.card.id.localeCompare(b.card.id),
    )
    .slice(0, 3);
  return {
    fanId: HOUSE_ID,
    cards: chosen.map(({ card }, index) => ({
      id: `house_${duelId}_${index}`,
      playerId: card.id,
      ownerId: HOUSE_ID,
      name: card.name,
      teamCode: card.teamCode,
      axes: { ...card.axes },
    })),
    skills: [],
    usedCardIds: [],
    usedSkillIds: [],
  };
}

export function buildHouseCommitments(state: DuelState): CardCommitment[] {
  return state.house!.cards.map((card, index) => {
    const salt = hash(state.id, card.id, String(index), "house-plan").slice(0, 32);
    return {
      index,
      hash: cardCommitment(state.id, index, card.id, salt),
      cardId: card.id,
      salt,
    };
  });
}

/** Verify a revealed House card against the pre-committed ordered hand. */
export function verifyHouseReveal(
  duelId: string,
  commitment: CardCommitment,
  cardId: string,
  salt: string,
): boolean {
  if (!commitment.hash) return false;
  return cardCommitment(duelId, commitment.index, cardId, salt) === commitment.hash;
}
