import { test } from "node:test";
import assert from "node:assert/strict";
import nacl from "tweetnacl";
import { base58Encode } from "../lib/util/base58.ts";
import {
  __resetAuthForTests,
  issueNonce,
  verifySessionToken,
  verifyWalletSignature,
} from "../lib/auth/session.ts";
import {
  __resetCardEconomyForTests,
  craft,
  inventoryOf,
  seedDemoInventory,
} from "../lib/cards/economy.ts";
import { AuthoritativeDuelEngine, cardCommitment } from "../lib/duel/engine.ts";
import { MemoryDuelRepository } from "../lib/duel/repository.ts";
import { arenaScript, DuelCommandService } from "../lib/duel/service.ts";

const axes = (finishing, chaos = 50, clutch = 50, marketShock = 50, aura = 50) => ({
  finishing, chaos, clutch, marketShock, aura,
});

function state() {
  const cards = (owner, values) =>
    values.map((value, index) => ({
      id: `${owner}-${index}`,
      playerId: `${owner}-real-${index}`,
      ownerId: owner,
      name: `${owner} player ${index}`,
      teamCode: owner === "a" ? "FRA" : "ARG",
      axes: axes(value),
    }));
  return {
    id: "duel-test",
    code: "ABC234",
    mode: "stadium",
    opponentType: "friend",
    phase: "axisSelection",
    version: 1,
    challengerId: "a",
    opponentId: "b",
    participants: {
      a: { fanId: "a", cards: cards("a", [90, 91, 92]), skills: [], usedCardIds: [], usedSkillIds: [] },
      b: { fanId: "b", cards: cards("b", [10, 11, 12]), skills: [], usedCardIds: [], usedSkillIds: [] },
    },
    attackerId: "a",
    submissions: {},
    rounds: [],
    wins: { a: 0, b: 0 },
    commitments: [],
    turnStartedAt: 0,
    turnDeadlineAt: 60_000,
    createdAt: 0,
    updatedAt: 0,
  };
}

test("wallet nonce is Ed25519 verified, single-use, and yields an expiring session", () => {
  __resetAuthForTests();
  const pair = nacl.sign.keyPair();
  const wallet = base58Encode(pair.publicKey);
  const challenge = issueNonce(wallet, 1_000);
  const signature = base58Encode(nacl.sign.detached(new TextEncoder().encode(challenge.message), pair.secretKey));
  const session = verifyWalletSignature({ wallet, message: challenge.message, signature, now: 2_000 });
  assert.equal(verifySessionToken(session.token, 2_001), wallet);
  assert.throws(() => verifyWalletSignature({ wallet, message: challenge.message, signature, now: 2_000 }), /used/);
  assert.throws(() => verifySessionToken(session.token, session.expiresAt + 1), /expired/);
});

test("House cards are fixed-roster snapshots with valid ordered commitments and private plans", async () => {
  __resetCardEconomyForTests();
  const repository = new MemoryDuelRepository({
    states: new Map(), actions: new Map(), events: [], rewards: new Set(), devices: new Map(),
  });
  const service = new DuelCommandService(repository);
  const seeded = seedDemoInventory("fan-house").inventory;
  const view = await service.create({
    fanId: "fan-house",
    mode: "stadium",
    opponentType: "house",
    hand: seeded.players.slice(0, 3).map((card) => card.id),
    actionId: "create-house",
    now: 10,
  });
  assert.equal(view.commitments.length, 3);
  assert.ok(view.commitments.every((commitment) => !commitment.cardId && !commitment.salt));
  const stored = await repository.get(view.id);
  assert.ok(stored.house.cards.every((card) => !card.name.startsWith("Bot ")));
  stored.commitments.forEach((commitment, index) => {
    assert.equal(
      commitment.hash,
      cardCommitment(stored.id, index, commitment.cardId, commitment.salt),
    );
  });
});

test("Friend submissions stay hidden and an idempotent action resolves only once", async () => {
  __resetCardEconomyForTests();
  const repository = new MemoryDuelRepository({
    states: new Map(), actions: new Map(), events: [], rewards: new Set(), devices: new Map(),
  });
  const service = new DuelCommandService(repository);
  const a = seedDemoInventory("friend-a").inventory.players.map((card) => card.id);
  const b = seedDemoInventory("friend-b").inventory.players.map((card) => card.id);
  const created = await service.create({
    fanId: "friend-a", mode: "stadium", opponentType: "friend", hand: a, actionId: "create",
  });
  await service.join({ fanId: "friend-b", code: created.code, hand: b, actionId: "join" });
  await service.action(created.id, "friend-a", { type: "choose_axis", axis: "finishing", actionId: "axis" });
  const submitted = await service.action(created.id, "friend-a", { type: "submit_card", cardId: a[0], actionId: "a-card" });
  assert.equal(submitted.rounds.length, 0);
  const defender = await service.get(created.id, "friend-b");
  assert.equal(defender.opponent.submitted, true);
  assert.equal(JSON.stringify(defender).includes(a[0]), false);
  const resolved = await service.action(created.id, "friend-b", { type: "submit_card", cardId: b[0], actionId: "b-card" });
  const duplicate = await service.action(created.id, "friend-b", { type: "submit_card", cardId: b[0], actionId: "b-card" });
  assert.equal(resolved.rounds.length, 1);
  assert.deepEqual(duplicate, resolved);
});

test("Engine ends immediately at two wins and deterministically auto-plays timeouts", () => {
  const engine = new AuthoritativeDuelEngine();
  let duel = state();
  duel = engine.apply(duel, "a", { type: "choose_axis", axis: "finishing", actionId: "1" }, 1);
  duel = engine.apply(duel, "a", { type: "submit_card", cardId: "a-0", actionId: "2" }, 2);
  duel = engine.apply(duel, "b", { type: "submit_card", cardId: "b-0", actionId: "3" }, 3);
  duel = engine.apply(duel, "a", { type: "acknowledge_round", actionId: "4" }, 4);
  duel = engine.applyTimeout(duel, 75_005);
  assert.equal(duel.phase, "finished");
  assert.equal(duel.rounds.length, 2);
  assert.equal(duel.winnerId, "a");
  assert.equal(duel.rounds[1].aAutoPlayed, true);
  assert.equal(duel.rounds[1].bAutoPlayed, true);
  assert.equal(duel.rounds[1].aCard.id, "a-1");
});

test("three tied rounds produce an honest draw", () => {
  const engine = new AuthoritativeDuelEngine();
  let duel = state();
  duel.participants.b.cards.forEach((card, index) => {
    card.axes.finishing = duel.participants.a.cards[index].axes.finishing;
  });
  for (let round = 0; round < 3; round++) {
    duel = engine.apply(duel, duel.attackerId, { type: "choose_axis", axis: "finishing", actionId: `axis-${round}` });
    duel = engine.apply(duel, "a", { type: "submit_card", cardId: `a-${round}`, actionId: `a-${round}` });
    duel = engine.apply(duel, "b", { type: "submit_card", cardId: `b-${round}`, actionId: `b-${round}` });
    if (round < 2) duel = engine.apply(duel, "a", { type: "acknowledge_round", actionId: `ack-${round}` });
  }
  assert.equal(duel.phase, "finished");
  assert.equal(duel.winnerId, null);
});

test("Arena scripts match literal event families and craft preserves lineage after burns", () => {
  assert.deepEqual(arenaScript({ kind: "goal", minute: 12 }), ["finishing", "aura", "marketShock"]);
  assert.deepEqual(arenaScript({ kind: "red", minute: 75 }), ["chaos", "clutch", "marketShock"]);
  assert.deepEqual(arenaScript({ kind: "market-swing", minute: 80 }), ["marketShock", "clutch", "aura"]);
  __resetCardEconomyForTests();
  const inventory = seedDemoInventory("crafter").inventory;
  const sources = inventory.moments.slice(0, 3);
  const parent = [...sources].sort((a, b) => b.rarity - a.rarity)[0];
  const result = craft("crafter", sources.map((moment) => moment.id), () => 0);
  assert.ok(!("error" in result));
  assert.equal(result.lineage.parentMomentId, parent.id);
  assert.equal(result.lineage.sourceEventId, parent.sourceEventId);
  assert.ok(result.lineage.oddsSandwich);
  assert.equal(result.lineage.proofRef, parent.leafData);
  assert.equal(inventoryOf("crafter").moments.some((moment) => moment.id === result.lineage.parentMomentId), false);
});

test("repository grants and device ownership are exactly-once", async () => {
  const repository = new MemoryDuelRepository({
    states: new Map(), actions: new Map(), events: [], rewards: new Set(), devices: new Map(),
  });
  assert.equal(await repository.grantRewardOnce("d", "fan", "win"), true);
  assert.equal(await repository.grantRewardOnce("d", "fan", "win"), false);
  await repository.registerDevice("fan", "token-12345678901234567890", "android", []);
  assert.deepEqual(await repository.devicesForFan("fan"), ["token-12345678901234567890"]);
});

test("Postgres adapter survives create → reload for inventory and active Duels", {
  skip: !process.env.DATABASE_URL,
}, async () => {
  const { PostgresDuelRepository } = await import("../lib/duel/repository.ts");
  const { ensureStoreHydrated } = await import("../lib/db/hydrate.ts");
  const { persistInventory } = await import("../lib/db/durable.ts");
  const { __resetCardEconomyForTests, inventoryOf, seedDemoInventory } = await import("../lib/cards/economy.ts");
  const { __resetDurableHydrationForTests } = await import("../lib/db/durable.ts");

  __resetCardEconomyForTests();
  __resetDurableHydrationForTests();
  const repository = new PostgresDuelRepository();
  const service = new DuelCommandService(repository);
  const seeded = seedDemoInventory(`pg-fan-${Date.now()}`);
  await persistInventory(seeded.inventory.fanId, seeded.inventory);
  __resetCardEconomyForTests();
  __resetDurableHydrationForTests();
  await ensureStoreHydrated();
  const reloaded = inventoryOf(seeded.inventory.fanId);
  assert.equal(reloaded.players.length, seeded.inventory.players.length);

  const hand = reloaded.players.slice(0, 3).map((card) => card.id);
  const created = await service.create({
    fanId: seeded.inventory.fanId,
    mode: "stadium",
    opponentType: "house",
    hand,
    actionId: `pg-create-${Date.now()}`,
  });
  const again = await repository.get(created.id);
  assert.ok(again);
  assert.equal(again.phase, created.phase);
  assert.equal(again.participants[seeded.inventory.fanId].cards.length, 3);
});
