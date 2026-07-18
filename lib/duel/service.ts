import crypto from "crypto";
import { inventoryOf, getMoment, momentProof } from "@/lib/cards/economy";
import type { Moment, PlayerCard, SkillCard } from "@/lib/cards/types";
import { ensureStoreHydrated } from "@/lib/db/hydrate";
import { EARN, earn } from "@/lib/platform/ledger";
import { XP, addXp } from "@/lib/platform/pass";
import { notifyDuelTurn } from "@/lib/push/duels";
import { arenaScript } from "./arena-rules";
import { AuthoritativeDuelEngine, TURN_MS } from "./engine";
import { buildHouseCommitments, buildHouseParticipant } from "./house";
import { duelRepository, type DuelRepository } from "./repository";
import type {
  ArenaContext,
  DuelCommand,
  DuelParticipant,
  DuelPlayerSnapshot,
  DuelSkillSnapshot,
  DuelState,
  DuelView,
  OpponentType,
} from "./types";

export { arenaScript };

const engine = new AuthoritativeDuelEngine();
const HOUSE_ID = "house";

function hash(...parts: string[]) {
  return crypto.createHash("sha256").update(parts.join(":")).digest("hex");
}

function inviteCode(id: string) {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = Buffer.from(hash(id), "hex");
  return [...bytes.subarray(0, 6)].map((byte) => alphabet[byte % alphabet.length]).join("");
}

function playerSnapshot(card: PlayerCard): DuelPlayerSnapshot {
  return {
    id: card.id,
    playerId: card.playerId,
    ownerId: card.ownerId,
    name: card.name,
    teamCode: card.teamCode,
    axes: { ...card.axes },
    lineage: card.lineage ? structuredClone(card.lineage) : undefined,
  };
}

function skillSnapshot(card: SkillCard): DuelSkillSnapshot {
  return { id: card.id, ownerId: card.ownerId, name: card.name, effect: structuredClone(card.effect) };
}

function fanParticipant(fanId: string, hand: string[], skillIds: string[] = []): DuelParticipant {
  if (new Set(hand).size !== 3) throw new Error("hand must contain three unique Player Cards");
  const inventory = inventoryOf(fanId);
  const cards = hand.map((id) => inventory.players.find((card) => card.id === id));
  if (cards.some((card) => !card)) throw new Error("hand contains a card the fan does not own");
  const skills = skillIds.map((id) => inventory.skills.find((skill) => skill.id === id));
  if (skills.some((skill) => !skill)) throw new Error("skills contain a card the fan does not own");
  return {
    fanId,
    cards: cards.map((card) => playerSnapshot(card!)),
    skills: skills.map((skill) => skillSnapshot(skill!)),
    usedCardIds: [],
    usedSkillIds: [],
  };
}

function arenaContext(moment: Moment): ArenaContext {
  return {
    moment: {
      id: moment.id,
      fixtureId: moment.fixtureId,
      kind: moment.kind,
      teamCode: moment.teamCode,
      minute: moment.minute,
      sourceEventId: moment.sourceEventId,
      oddsSandwich: structuredClone(moment.oddsSandwich),
      rarity: moment.rarity,
    },
    proofVerified: momentProof(moment.id)?.verified ?? false,
    script: arenaScript(moment),
  };
}

function publicEvent() {
  return { type: "state_changed" };
}

export class DuelCommandService {
  constructor(private readonly repository: DuelRepository = duelRepository()) {}

  async create(input: {
    fanId: string;
    mode: "stadium" | "arena";
    opponentType?: OpponentType;
    hand: string[];
    skillIds?: string[];
    seedMomentId?: string;
    actionId: string;
    now?: number;
  }): Promise<DuelView> {
    await ensureStoreHydrated();
    if (!input.actionId) throw new Error("actionId is required");
    const id = `duel_${hash(input.fanId, input.actionId).slice(0, 20)}`;
    const existing = await this.repository.get(id);
    if (existing) return engine.view(existing, input.fanId);
    const now = input.now ?? Date.now();
    const fan = fanParticipant(input.fanId, input.hand, input.skillIds);
    const opponentType = input.mode === "arena" ? "house" : input.opponentType ?? "house";
    const state: DuelState = {
      id,
      code: inviteCode(id),
      mode: input.mode,
      opponentType,
      phase: opponentType === "friend" ? "waitingForOpponent" : input.mode === "arena" ? "cardSelection" : "axisSelection",
      version: 1,
      challengerId: input.fanId,
      opponentId: opponentType === "house" ? HOUSE_ID : null,
      participants: { [input.fanId]: fan },
      attackerId: input.fanId,
      submissions: {},
      rounds: [],
      wins: { [input.fanId]: 0, ...(opponentType === "house" ? { [HOUSE_ID]: 0 } : {}) },
      commitments: [],
      turnStartedAt: now,
      turnDeadlineAt: now + TURN_MS,
      createdAt: now,
      updatedAt: now,
    };
    if (opponentType === "house") {
      state.house = buildHouseParticipant(id, fan.cards);
      state.commitments = buildHouseCommitments(state);
      state.submissions.house = { cardId: state.house.cards[0].id };
    }
    if (input.mode === "arena") {
      const moment = getMoment(String(input.seedMomentId ?? ""));
      if (!moment || moment.ownerId !== input.fanId) throw new Error("verified seed Moment not found");
      state.arena = arenaContext(moment);
      state.axis = state.arena.script[0];
    }
    await this.repository.create(state, publicEvent());
    return engine.view(state, input.fanId);
  }

  async join(input: {
    fanId: string;
    code: string;
    hand: string[];
    skillIds?: string[];
    actionId: string;
    now?: number;
  }) {
    await ensureStoreHydrated();
    const found = await this.repository.findByCode(input.code);
    if (!found) throw new Error("duel not found");
    const result = await this.repository.applyAction(
      found.id,
      input.fanId,
      input.actionId,
      (state) => {
        if (state.phase !== "waitingForOpponent" || state.opponentType !== "friend") throw new Error("duel is not joinable");
        if (state.challengerId === input.fanId) throw new Error("cannot join your own duel");
        state.opponentId = input.fanId;
        state.participants[input.fanId] = fanParticipant(input.fanId, input.hand, input.skillIds);
        state.wins[input.fanId] = 0;
        state.phase = "axisSelection";
        state.version++;
        state.turnStartedAt = input.now ?? Date.now();
        state.turnDeadlineAt = state.turnStartedAt + TURN_MS;
        state.updatedAt = state.turnStartedAt;
        return state;
      },
      publicEvent,
    );
    await notifyDuelTurn(this.repository, found.id, found.challengerId);
    return engine.view(result.state, input.fanId);
  }

  async action(id: string, fanId: string, command: DuelCommand, now = Date.now()) {
    await ensureStoreHydrated();
    if (command.type === "rematch") {
      const current = await this.repository.get(id);
      if (!current || current.phase !== "finished") throw new Error("rematch requires a finished duel");
      if (!current.participants[fanId]) throw new Error("not a duel participant");
      const hand = current.participants[fanId].cards.map((card) => card.id);
      const skillIds = current.participants[fanId].skills.map((skill) => skill.id);
      return this.create({
        fanId,
        mode: current.mode,
        opponentType: current.opponentType,
        hand,
        skillIds,
        seedMomentId: current.arena?.moment.id,
        actionId: command.actionId,
        now,
      });
    }
    const result = await this.repository.applyAction(
      id,
      fanId,
      command.actionId,
      (state) => engine.apply(engine.applyTimeout(state, now), fanId, command, now),
      publicEvent,
    );
    await this.settle(result.state);
    if (!result.duplicate) await this.notifyActorIfNeeded(result.state, fanId);
    return engine.view(result.state, fanId);
  }

  async get(id: string, fanId: string, now = Date.now()) {
    await ensureStoreHydrated();
    let state = await this.repository.get(id);
    if (!state) throw new Error("duel not found");
    if (now >= state.turnDeadlineAt + 15_000 && state.phase !== "finished") {
      const result = await this.repository.applyAction(
        id,
        "system",
        `timeout:${state.version}:${state.turnDeadlineAt}`,
        (current) => engine.applyTimeout(current, now),
        publicEvent,
      );
      state = result.state;
      await this.settle(state);
    }
    return engine.view(state, fanId);
  }

  async events(id: string, fanId: string, afterVersion: number) {
    const events = await this.repository.events(id, afterVersion);
    const state = await this.repository.get(id);
    if (!state) throw new Error("duel not found");
    // Stored events are deliberately sanitized; the view is rendered for this actor.
    return events.map((event) => ({ ...event, event: { ...event.event, view: engine.view(state, fanId) } }));
  }

  private async settle(state: DuelState) {
    if (state.phase !== "finished") return;
    for (const fanId of Object.keys(state.participants)) {
      const result = state.winnerId === null ? "draw" : state.winnerId === fanId ? "win" : "loss";
      if (!(await this.repository.grantRewardOnce(state.id, fanId, result))) continue;
      const won = result === "win";
      earn(fanId, won ? EARN.duelWin : EARN.duelLoss, won ? "duel win" : "duel played");
      addXp(fanId, won ? XP.duelWin : XP.duelLoss, "duel");
    }
  }

  private async notifyActorIfNeeded(state: DuelState, actingFan: string) {
    if (state.opponentType !== "friend" || state.phase === "finished") return;
    const target =
      state.phase === "axisSelection"
        ? state.attackerId
        : [state.challengerId, state.opponentId!].find((id) => id !== actingFan && !state.submissions[id]);
    if (target) await notifyDuelTurn(this.repository, state.id, target);
  }
}
