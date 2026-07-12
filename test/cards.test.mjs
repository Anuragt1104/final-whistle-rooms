/**
 * Card Economy seam tests — mint, Called It, pack, craft, duel, arena.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  __resetCardEconomyForTests,
  craft,
  inventoryOf,
  mintFromEvent,
  momentProof,
  openPack,
  partyDropMultiplier,
  stampCalledIt,
} from "../lib/cards/economy.ts";
import {
  __resetDuelsForTests,
  createMomentArena,
  createTrumpDuel,
  playTrumpRound,
} from "../lib/cards/duel.ts";
import { marketRarity } from "../lib/cards/rarity.ts";
import { applyLineageImprint, imprintAxis } from "../lib/cards/lineage.ts";

const sandwich = {
  before: { home: 0.55, draw: 0.25, away: 0.2 },
  after: { home: 0.72, draw: 0.18, away: 0.1 },
};

function mintGoal(fanId = "fan1", seq = 1) {
  return mintFromEvent({
    fanId,
    fixtureId: "fx1",
    matchLabel: "FRA vs ARG",
    roomId: "room1",
    partyMultiplier: partyDropMultiplier(2),
    event: { kind: "goal", side: "home", minute: 23, seq, label: "Goal — France" },
    oddsSandwich: sandwich,
    priorHomeProb: 0.55,
  });
}

test("empty inventory", () => {
  __resetCardEconomyForTests();
  const inv = inventoryOf("nobody");
  assert.equal(inv.moments.length, 0);
  assert.equal(inv.players.length, 0);
});

test("mintFromEvent creates Moment with rarity + Odds Sandwich + pack", () => {
  __resetCardEconomyForTests();
  const m = mintGoal();
  assert.ok(m);
  assert.equal(m.type, "moment");
  assert.ok(m.rarity >= 1 && m.rarity <= 5);
  assert.equal(m.oddsSandwich.after.home, 0.72);
  assert.equal(m.calledIt, false);
  const inv = inventoryOf("fan1");
  assert.equal(inv.moments.length, 1);
  assert.equal(inv.packs.length, 1);
  assert.equal(inv.packs[0].opened, false);
});

test("Market Rarity rises for upsets and swings", () => {
  const low = marketRarity("goal", 0.8, {
    before: { home: 0.8, draw: 0.15, away: 0.05 },
    after: { home: 0.82, draw: 0.13, away: 0.05 },
  });
  const high = marketRarity("goal", 0.15, {
    before: { home: 0.15, draw: 0.25, away: 0.6 },
    after: { home: 0.45, draw: 0.25, away: 0.3 },
  });
  assert.ok(high >= low);
});

test("Moment proof verifies against Merkle root", () => {
  __resetCardEconomyForTests();
  const m = mintGoal("fan1", 7);
  assert.ok(m);
  const proof = momentProof(m.id);
  assert.ok(proof);
  assert.equal(proof.verified, true);
  assert.ok(proof.root.length > 16);
});

test("Called It stamps Moment and boosts pack weight", () => {
  __resetCardEconomyForTests();
  const m = mintGoal();
  assert.ok(m);
  const before = inventoryOf("fan1").packs[0].weight;
  const stamped = stampCalledIt("fan1", { fixtureId: "fx1" });
  assert.equal(stamped.length, 1);
  assert.equal(stamped[0].calledIt, true);
  assert.ok(inventoryOf("fan1").packs[0].weight > before);
});

test("openPack yields Player Card with Lineage Imprint", () => {
  __resetCardEconomyForTests();
  const m = mintGoal();
  assert.ok(m);
  const packId = inventoryOf("fan1").packs[0].id;
  const rand = (() => {
    let i = 0;
    const seq = [0.1, 0.2, 0.3, 0.4, 0.5];
    return () => seq[i++ % seq.length];
  })();
  const pack = openPack("fan1", packId, rand);
  assert.ok(!("error" in pack));
  assert.equal(pack.opened, true);
  assert.ok(pack.cards.some((c) => c.type === "player"));
  const player = pack.cards.find((c) => c.type === "player");
  assert.ok(player && player.type === "player");
  assert.equal(player.lineageMomentId, m.id);
  // goal → finishing imprint (+8)
  const baseFinishing = applyLineageImprint(
    { finishing: 80, chaos: 70, clutch: 70, marketShock: 70, aura: 70 },
    "goal",
  ).finishing;
  assert.equal(baseFinishing, 88);
  assert.equal(imprintAxis("goal"), "finishing");
});

test("craft burns Moments into a Player Card", () => {
  __resetCardEconomyForTests();
  // three 5★-ish moments via low prior
  for (let i = 0; i < 3; i++) {
    mintFromEvent({
      fanId: "fan1",
      fixtureId: "fx1",
      matchLabel: "FRA vs ARG",
      event: { kind: "goal", side: "away", minute: 10 + i, seq: 100 + i, label: "Upset" },
      oddsSandwich: {
        before: { home: 0.1, draw: 0.2, away: 0.7 },
        after: { home: 0.05, draw: 0.15, away: 0.8 },
      },
      priorHomeProb: 0.1,
    });
  }
  const ids = inventoryOf("fan1").moments.map((m) => m.id);
  assert.ok(ids.length >= 3);
  const player = craft("fan1", ids.slice(0, 3), () => 0.2);
  assert.ok(!("error" in player));
  assert.equal(player.type, "player");
  assert.equal(inventoryOf("fan1").moments.length, ids.length - 3);
});

test("Trump Duel vs bot completes best of 3", () => {
  __resetCardEconomyForTests();
  __resetDuelsForTests();
  // seed 3 players via packs
  for (let i = 0; i < 3; i++) {
    mintFromEvent({
      fanId: "fan1",
      fixtureId: "fx1",
      matchLabel: "A vs B",
      event: { kind: "goal", side: "home", minute: i + 1, seq: i + 1, label: "G" },
      oddsSandwich: sandwich,
      priorHomeProb: 0.5,
    });
  }
  const packs = inventoryOf("fan1").packs;
  for (const p of packs) openPack("fan1", p.id, () => 0.15);
  const hand = inventoryOf("fan1").players.slice(0, 3).map((p) => p.id);
  assert.equal(hand.length, 3);

  const duel = createTrumpDuel({ challengerId: "fan1", hand, vsBot: true });
  assert.ok(!("error" in duel));
  assert.equal(duel.status, "playing");

  let d = duel;
  for (let i = 0; i < 3; i++) {
    const result = playTrumpRound({
      duelId: d.id,
      fanId: "fan1",
      axis: "finishing",
      cardId: hand[i],
    });
    assert.ok(!("error" in result));
    d = result;
  }
  assert.equal(d.status, "finished");
  assert.equal(d.rounds.length, 3);
});

test("Moment Arena auto-resolves from seed Moment", () => {
  __resetCardEconomyForTests();
  __resetDuelsForTests();
  const m = mintGoal("fan1", 42);
  assert.ok(m);
  openPack("fan1", inventoryOf("fan1").packs[0].id, () => 0.1);
  // need 3 cards — mint more
  for (let i = 0; i < 2; i++) {
    mintGoal("fan1", 50 + i);
    openPack("fan1", inventoryOf("fan1").packs.find((p) => !p.opened).id, () => 0.1);
  }
  const hand = inventoryOf("fan1").players.slice(0, 3).map((p) => p.id);
  const arena = createMomentArena({
    challengerId: "fan1",
    seedMomentId: m.id,
    hand,
  });
  assert.ok(!("error" in arena));
  assert.equal(arena.mode, "arena");
  assert.ok(arena.rounds.length >= 1);
});

test("partyDropMultiplier scales with fans", () => {
  assert.equal(partyDropMultiplier(1), 1);
  assert.equal(partyDropMultiplier(2), 1.25);
  assert.equal(partyDropMultiplier(4), 1.5);
});
