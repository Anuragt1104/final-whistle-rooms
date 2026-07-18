import crypto from "crypto";
import { AXES, type Axis } from "@/lib/cards/types";
import { arenaLineageBonus, finalizeScore } from "./arena-rules";
import {
  assertCardLegal,
  availableCards,
  earlyFinishWinner,
  houseAxisChoice,
  lowestUnusedCard,
  stadiumOpponentId,
  stadiumParticipant,
} from "./stadium-rules";
import type {
  DuelCommand,
  DuelRoundResolution,
  DuelSkillSnapshot,
  DuelState,
  DuelView,
  HiddenSubmission,
  ScoreBreakdown,
} from "./types";

export const TURN_MS = 60_000;
export const RECONNECT_GRACE_MS = 15_000;

export interface DuelEngine {
  apply(state: DuelState, actorId: string, command: DuelCommand, now?: number): DuelState;
  applyTimeout(state: DuelState, now?: number): DuelState;
  view(state: DuelState, actorId: string): DuelView;
}

export function cardCommitment(duelId: string, index: number, cardId: string, salt: string) {
  return crypto
    .createHash("sha256")
    .update(`${duelId}:${index}:${cardId}:${salt}`)
    .digest("hex");
}

function clone<T>(value: T): T {
  return structuredClone(value);
}

function skillBonus(skill: DuelSkillSnapshot | undefined, axis: Axis, base: number): number {
  if (!skill) return 0;
  if (skill.effect.kind === "axisBoost" && skill.effect.axis === axis) return skill.effect.amount;
  if (skill.effect.kind === "doubleAura" && axis === "aura") return base;
  return 0;
}

function breakdown(
  state: DuelState,
  card: Parameters<typeof arenaLineageBonus>[0],
  skill: DuelSkillSnapshot | undefined,
  axis: Axis,
): ScoreBreakdown {
  const base = card.axes[axis];
  const lineage =
    state.mode === "arena" && state.arena
      ? arenaLineageBonus(card, state.arena.moment)
      : { resonance: 0, calledIt: 0 };
  return finalizeScore({
    base,
    resonance: lineage.resonance,
    calledIt: lineage.calledIt,
    skill: skillBonus(skill, axis, base),
  });
}

function setTurn(state: DuelState, now: number) {
  state.turnStartedAt = now;
  state.turnDeadlineAt = now + TURN_MS;
  state.updatedAt = now;
}

function beginRound(state: DuelState, now: number) {
  state.axis = undefined;
  state.submissions = {};
  if (state.mode === "arena") {
    state.axis = state.arena!.script[state.rounds.length];
    state.phase = "cardSelection";
  } else if (state.attackerId === "house") {
    state.axis = houseAxisChoice(state.house!.cards[state.rounds.length]);
    state.phase = "cardSelection";
  } else {
    state.phase = "axisSelection";
  }
  if (state.opponentType === "house") {
    const card = state.house!.cards[state.rounds.length];
    state.submissions.house = { cardId: card.id };
  }
  setTurn(state, now);
}

function resolve(state: DuelState, now: number) {
  const aId = state.challengerId;
  const bId = state.opponentType === "house" ? "house" : state.opponentId!;
  const a = stadiumParticipant(state, aId);
  const b = stadiumParticipant(state, bId);
  const aSub = state.submissions[aId];
  const bSub = state.submissions[bId];
  if (!aSub || !bSub || !state.axis) return;
  state.phase = "resolving";

  const aCard = a.cards.find((card) => card.id === aSub.cardId)!;
  const bCard = b.cards.find((card) => card.id === bSub.cardId)!;
  const aSkill = a.skills.find((skill) => skill.id === aSub.skillId);
  const bSkill = b.skills.find((skill) => skill.id === bSub.skillId);
  const aScore = breakdown(state, aCard, aSkill, state.axis);
  const bScore = breakdown(state, bCard, bSkill, state.axis);
  const winnerId = aScore.total > bScore.total ? aId : bScore.total > aScore.total ? bId : null;
  const index = state.rounds.length;
  const reveal = bId === "house" ? state.commitments[index] : undefined;
  const round: DuelRoundResolution = {
    round: index + 1,
    axis: state.axis,
    attackerId: state.attackerId,
    aFanId: aId,
    bFanId: bId,
    aCard,
    bCard,
    aSkill,
    bSkill,
    aScore,
    bScore,
    winnerId,
    aAutoPlayed: !!aSub.autoPlayed,
    bAutoPlayed: !!bSub.autoPlayed,
    houseReveal: reveal?.cardId && reveal.salt
      ? { index, cardId: reveal.cardId, salt: reveal.salt }
      : undefined,
  };
  state.rounds.push(round);
  a.usedCardIds.push(aCard.id);
  b.usedCardIds.push(bCard.id);
  if (aSkill) a.usedSkillIds.push(aSkill.id);
  if (bSkill) b.usedSkillIds.push(bSkill.id);
  if (winnerId) state.wins[winnerId] = (state.wins[winnerId] ?? 0) + 1;

  const early = earlyFinishWinner(state.wins);
  if (early || state.rounds.length === 3) {
    state.phase = "finished";
    if (early) {
      state.winnerId = early;
    } else {
      const aWins = state.wins[aId] ?? 0;
      const bWins = state.wins[bId] ?? 0;
      state.winnerId = aWins === bWins ? null : aWins > bWins ? aId : bId;
    }
  } else {
    if (winnerId) state.attackerId = winnerId;
    if (aSkill?.effect.kind === "swapAttacker") state.attackerId = aId;
    if (bSkill?.effect.kind === "swapAttacker") state.attackerId = bId;
    state.phase = "roundComplete";
  }
  state.submissions = {};
  state.updatedAt = now;
}

function submit(state: DuelState, actorId: string, submission: HiddenSubmission, now: number) {
  if (state.phase !== "cardSelection") throw new Error("cards cannot be submitted now");
  const p = stadiumParticipant(state, actorId);
  assertCardLegal(p, submission, !!state.submissions[actorId]);
  state.submissions[actorId] = submission;
  resolve(state, now);
}

function actorIds(state: DuelState) {
  return state.opponentType === "house"
    ? [state.challengerId]
    : [state.challengerId, state.opponentId!].filter(Boolean);
}

export class AuthoritativeDuelEngine implements DuelEngine {
  apply(input: DuelState, actorId: string, command: DuelCommand, now = Date.now()): DuelState {
    const state = clone(input);
    stadiumParticipant(state, actorId);
    if (state.phase === "finished" && command.type !== "rematch") throw new Error("duel is finished");

    if (command.type === "choose_axis") {
      if (state.phase !== "axisSelection") throw new Error("axis cannot be chosen now");
      if (state.attackerId !== actorId) throw new Error("only the attacker chooses the axis");
      if (!AXES.includes(command.axis)) throw new Error("invalid axis");
      state.axis = command.axis;
      state.phase = "cardSelection";
      setTurn(state, now);
    } else if (command.type === "submit_card") {
      submit(state, actorId, { cardId: command.cardId, skillId: command.skillId }, now);
    } else if (command.type === "acknowledge_round") {
      if (state.phase !== "roundComplete") throw new Error("round is not complete");
      beginRound(state, now);
    } else {
      throw new Error("rematch requires a new duel");
    }
    state.version++;
    state.updatedAt = now;
    return state;
  }

  applyTimeout(input: DuelState, now = Date.now()): DuelState {
    if (
      input.phase === "finished" ||
      input.phase === "waitingForOpponent" ||
      now < input.turnDeadlineAt + RECONNECT_GRACE_MS
    ) {
      return input;
    }
    const state = clone(input);
    if (state.phase === "axisSelection") {
      const attacker = stadiumParticipant(state, state.attackerId);
      state.axis = houseAxisChoice(lowestUnusedCard(attacker));
      state.phase = "cardSelection";
    }
    for (const fanId of actorIds(state)) {
      if (!state.submissions[fanId]) {
        submit(state, fanId, {
          cardId: lowestUnusedCard(stadiumParticipant(state, fanId)).id,
          autoPlayed: true,
        }, now);
      }
    }
    state.version++;
    state.updatedAt = now;
    return state;
  }

  view(state: DuelState, actorId: string): DuelView {
    const actor = stadiumParticipant(state, actorId);
    const waiting =
      state.opponentType === "friend" &&
      (state.phase === "waitingForOpponent" || !state.opponentId);
    const otherId = waiting ? null : stadiumOpponentId(state, actorId);
    const other = otherId ? stadiumParticipant(state, otherId) : null;
    return {
      id: state.id,
      code: state.code,
      mode: state.mode,
      opponentType: state.opponentType,
      phase: state.phase,
      version: state.version,
      actorId,
      attackerId: state.attackerId,
      axis: state.axis,
      scores: { ...state.wins },
      winnerId: state.winnerId,
      rounds: clone(state.rounds),
      hand: clone(actor.cards),
      skills: clone(actor.skills),
      usedCardIds: [...actor.usedCardIds],
      usedSkillIds: [...actor.usedSkillIds],
      hasSubmitted: !!state.submissions[actorId],
      opponent: {
        id: otherId,
        submitted: otherId ? !!state.submissions[otherId] : false,
        cardsRemaining: other ? availableCards(other).length : 3,
      },
      timer: {
        startedAt: state.turnStartedAt,
        deadlineAt: state.turnDeadlineAt,
        graceEndsAt: state.turnDeadlineAt + RECONNECT_GRACE_MS,
      },
      commitments: state.commitments.map(({ index, hash }, round) => {
        const resolved = round < state.rounds.length;
        const full = state.commitments[round];
        return resolved ? clone(full) : { index, hash };
      }),
      arena: state.arena ? clone(state.arena) : undefined,
    };
  }
}
