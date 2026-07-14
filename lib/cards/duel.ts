/**
 * Trump Duel + Moment Arena (ADR-0003, ADR-0008).
 */
import { inventoryOf, getCard, getMoment, registerCard } from "./economy";
import type { Axis, DuelRound, PlayerCard, SkillCard, TrumpDuel } from "./types";
import { AXES } from "./types";

const duelGlobal = globalThis as unknown as { __fwr_duels?: Map<string, TrumpDuel> };
const duels =
  duelGlobal.__fwr_duels ??
  (duelGlobal.__fwr_duels = new Map<string, TrumpDuel>());

function uid(prefix: string): string {
  return `${prefix}_${Math.random().toString(36).slice(2, 10)}${Date.now().toString(36).slice(-4)}`;
}

function code6(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let s = "";
  for (let i = 0; i < 6; i++) s += alphabet[Math.floor(Math.random() * alphabet.length)];
  return s;
}

function effectiveValue(
  player: PlayerCard,
  axis: Axis,
  skill?: SkillCard,
): { value: number; stealAttack?: boolean } {
  let v = player.axes[axis];
  let stealAttack = false;
  if (skill) {
    const e = skill.effect;
    if (e.kind === "axisBoost" && e.axis === axis) v += e.amount;
    if (e.kind === "doubleAura" && axis === "aura") v *= 2;
    if (e.kind === "swapAttacker") stealAttack = true;
  }
  return { value: Math.min(99, Math.round(v)), stealAttack };
}

/** Create a Trump Duel vs bot or open for a friend code. */
export function createTrumpDuel(opts: {
  challengerId: string;
  hand: string[];
  vsBot?: boolean;
}): TrumpDuel | { error: string } {
  if (opts.hand.length !== 3) return { error: "Hand must be exactly 3 Player Cards" };
  const inv = inventoryOf(opts.challengerId);
  for (const id of opts.hand) {
    if (!inv.players.some((p) => p.id === id)) return { error: `Card ${id} not owned` };
  }

  const duel: TrumpDuel = {
    id: uid("duel"),
    code: code6(),
    mode: "trump",
    status: opts.vsBot ? "playing" : "open",
    challengerId: opts.challengerId,
    opponentId: opts.vsBot ? "bot" : null,
    challengerHand: [...opts.hand],
    opponentHand: opts.vsBot ? botHand(opts.challengerId) : [],
    attackerId: opts.challengerId,
    rounds: [],
    createdAt: Date.now(),
  };
  duels.set(duel.id, duel);
  return duel;
}

function botHand(_excludeOwner: string): string[] {
  const names = ["Bot Striker", "Bot Mid", "Bot Anchor"];
  const ids: string[] = [];
  for (let i = 0; i < 3; i++) {
    const id = uid("botplr");
    const card: PlayerCard = {
      id,
      type: "player",
      ownerId: "bot",
      playerId: `bot-${i}`,
      name: names[i],
      teamCode: "BOT",
      teamName: "House XI",
      position: i === 0 ? "FW" : i === 1 ? "MF" : "DF",
      axes: {
        finishing: 70 + Math.floor(Math.random() * 20),
        chaos: 65 + Math.floor(Math.random() * 25),
        clutch: 68 + Math.floor(Math.random() * 22),
        marketShock: 60 + Math.floor(Math.random() * 25),
        aura: 72 + Math.floor(Math.random() * 18),
      },
      leafData: `bot:${id}`,
      createdAt: Date.now(),
    };
    inventoryOf("bot").players.push(card);
    registerCard(card);
    ids.push(id);
  }
  return ids;
}

export function resolveCard(id: string): PlayerCard | SkillCard | undefined {
  const c = getCard(id);
  if (c && (c.type === "player" || c.type === "skill")) return c;
  return undefined;
}

export function joinTrumpDuel(
  code: string,
  opponentId: string,
  hand: string[],
): TrumpDuel | { error: string } {
  const duel = [...duels.values()].find((d) => d.code === code.toUpperCase() && d.status === "open");
  if (!duel) return { error: "Duel not found" };
  if (duel.challengerId === opponentId) return { error: "Cannot join your own duel" };
  if (hand.length !== 3) return { error: "Hand must be exactly 3 Player Cards" };
  const inv = inventoryOf(opponentId);
  for (const id of hand) {
    if (!inv.players.some((p) => p.id === id)) return { error: `Card ${id} not owned` };
  }
  duel.opponentId = opponentId;
  duel.opponentHand = [...hand];
  duel.status = "playing";
  return duel;
}

export function getDuel(id: string): TrumpDuel | undefined {
  return duels.get(id);
}

export function getDuelByCode(code: string): TrumpDuel | undefined {
  return [...duels.values()].find((d) => d.code === code.toUpperCase());
}

export function listDuelsForFan(fanId: string): TrumpDuel[] {
  return [...duels.values()].filter(
    (d) => d.challengerId === fanId || d.opponentId === fanId,
  );
}

/**
 * Play one Trump round. Attacker picks axis; each side plays one unused Hand card
 * (+ optional Skill). Best of 3.
 */
export function playTrumpRound(opts: {
  duelId: string;
  fanId: string;
  axis: Axis;
  cardId: string;
  skillId?: string;
  /** Bot auto-picks when opponent is bot and fan is challenger completing both sides */
  botCardId?: string;
  botSkillId?: string;
}): TrumpDuel | { error: string } {
  const duel = duels.get(opts.duelId);
  if (!duel) return { error: "Duel not found" };
  if (duel.status !== "playing") return { error: "Duel not in play" };
  if (duel.rounds.length >= 3) return { error: "Duel already complete" };
  if (!AXES.includes(opts.axis)) return { error: "Invalid axis" };
  if (opts.fanId !== duel.attackerId && opts.fanId !== duel.challengerId && opts.fanId !== duel.opponentId) {
    return { error: "Not a participant" };
  }
  // Only attacker chooses axis this round
  if (opts.fanId !== duel.attackerId && duel.opponentId !== "bot") {
    return { error: "Only the Attacker picks the Axis" };
  }

  const usedA = new Set(duel.rounds.map((r) => r.aCardId));
  const usedB = new Set(duel.rounds.map((r) => r.bCardId));

  const aIsChallenger = duel.attackerId === duel.challengerId || opts.fanId === duel.challengerId;
  // Simplify: challenger always plays as A, opponent/bot as B
  const aCardId = duel.challengerHand.includes(opts.cardId)
    ? opts.cardId
    : duel.challengerHand.find((id) => !usedA.has(id));
  if (!aCardId || usedA.has(aCardId)) {
    // if fan is challenger playing their card
  }

  let challengerCardId: string;
  let opponentCardId: string;
  let challengerSkill: string | undefined;
  let opponentSkill: string | undefined;

  if (opts.fanId === duel.challengerId || duel.opponentId === "bot") {
    if (!duel.challengerHand.includes(opts.cardId) || usedA.has(opts.cardId)) {
      return { error: "Invalid challenger card" };
    }
    challengerCardId = opts.cardId;
    challengerSkill = opts.skillId;
    if (duel.opponentId === "bot") {
      opponentCardId =
        opts.botCardId ??
        duel.opponentHand.find((id) => !usedB.has(id)) ??
        duel.opponentHand[0];
      opponentSkill = opts.botSkillId;
    } else {
      // PvP: opponent must have submitted — for MVP, attacker also supplies opp card via botCardId field as "response"
      if (!opts.botCardId || !duel.opponentHand.includes(opts.botCardId)) {
        return { error: "Opponent card required" };
      }
      opponentCardId = opts.botCardId;
      opponentSkill = opts.botSkillId;
    }
  } else {
    // opponent is attacker
    if (!duel.opponentHand.includes(opts.cardId) || usedB.has(opts.cardId)) {
      return { error: "Invalid opponent card" };
    }
    opponentCardId = opts.cardId;
    opponentSkill = opts.skillId;
    if (!opts.botCardId || !duel.challengerHand.includes(opts.botCardId)) {
      return { error: "Challenger card required" };
    }
    challengerCardId = opts.botCardId;
    challengerSkill = opts.botSkillId;
  }

  const aCard = resolveCard(challengerCardId) as PlayerCard | undefined;
  const bCard = resolveCard(opponentCardId) as PlayerCard | undefined;
  if (!aCard || aCard.type !== "player" || !bCard || bCard.type !== "player") {
    return { error: "Cards not found" };
  }

  const aSkill = challengerSkill ? (resolveCard(challengerSkill) as SkillCard | undefined) : undefined;
  const bSkill = opponentSkill ? (resolveCard(opponentSkill) as SkillCard | undefined) : undefined;

  const aEff = effectiveValue(aCard, opts.axis, aSkill?.type === "skill" ? aSkill : undefined);
  const bEff = effectiveValue(bCard, opts.axis, bSkill?.type === "skill" ? bSkill : undefined);

  let winnerId: string | null = null;
  if (aEff.value > bEff.value) winnerId = duel.challengerId;
  else if (bEff.value > aEff.value) winnerId = duel.opponentId === "bot" ? "bot" : duel.opponentId!;
  else winnerId = null;

  const round: DuelRound = {
    round: duel.rounds.length + 1,
    attackerId: duel.attackerId,
    axis: opts.axis,
    aCardId: challengerCardId,
    bCardId: opponentCardId,
    aSkillId: challengerSkill,
    bSkillId: opponentSkill,
    aValue: aEff.value,
    bValue: bEff.value,
    winnerId,
  };
  duel.rounds.push(round);

  // next attacker = round winner (draws keep current)
  if (winnerId && winnerId !== "bot") duel.attackerId = winnerId;
  else if (winnerId === "bot") duel.attackerId = duel.challengerId; // bot won → human still attacks for pace
  if (aEff.stealAttack) duel.attackerId = duel.challengerId;
  if (bEff.stealAttack && duel.opponentId && duel.opponentId !== "bot") {
    duel.attackerId = duel.opponentId;
  }

  if (duel.rounds.length >= 3) {
    duel.status = "finished";
    const aWins = duel.rounds.filter((r) => r.winnerId === duel.challengerId).length;
    const bWins = duel.rounds.filter(
      (r) => r.winnerId && r.winnerId !== duel.challengerId,
    ).length;
    duel.winnerId = aWins > bWins ? duel.challengerId : bWins > aWins ? (duel.opponentId ?? "bot") : undefined;
    // reward winner a small pack weight bonus
    if (duel.winnerId && duel.winnerId !== "bot") {
      inventoryOf(duel.winnerId).packWeightBonus += 0.5;
    }
  }

  return duel;
}

/** Moment Arena — seeded by a Moment; loadouts score by claim fit. */
export function createMomentArena(opts: {
  challengerId: string;
  seedMomentId: string;
  hand: string[];
}): TrumpDuel | { error: string } {
  const moment = getMoment(opts.seedMomentId);
  if (!moment) return { error: "Seed Moment not found" };
  if (opts.hand.length !== 3) return { error: "Hand must be exactly 3" };

  const duel: TrumpDuel = {
    id: uid("arena"),
    code: code6(),
    mode: "arena",
    status: "playing",
    challengerId: opts.challengerId,
    opponentId: "bot",
    challengerHand: [...opts.hand],
    opponentHand: botHand(opts.challengerId),
    attackerId: opts.challengerId,
    rounds: [],
    seedMomentId: opts.seedMomentId,
    createdAt: Date.now(),
  };
  duels.set(duel.id, duel);

  // Auto-resolve 3 rounds using imprint axis as preferred claim
  const preferred: Axis =
    moment.kind === "goal"
      ? "finishing"
      : moment.kind === "market-swing"
        ? "marketShock"
        : moment.kind === "red" || moment.kind === "yellow"
          ? "chaos"
          : "clutch";

  for (let i = 0; i < 3; i++) {
    const result = playTrumpRound({
      duelId: duel.id,
      fanId: opts.challengerId,
      axis: i === 0 ? preferred : AXES[i % AXES.length],
      cardId: opts.hand[i],
    });
    if ("error" in result) break;
  }
  return duels.get(duel.id)!;
}

export function __resetDuelsForTests() {
  duels.clear();
}
