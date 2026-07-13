import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { earn, spend, walletOf, recordRevenue, hqView, EARN, __resetLedgerForTests } from "../lib/platform/ledger.ts";
import { addXp, claimReward, passOf, unlockPremium, TRACK, TIER_COUNT, __resetPassForTests } from "../lib/platform/pass.ts";
import { browse, buyListing, listCard, MARKET_FEE, __resetMarketForTests } from "../lib/platform/market.ts";
import { buyPack, SHOP } from "../lib/platform/shop.ts";
import { inventoryOf, openPack, __resetCardEconomyForTests } from "../lib/cards/economy.ts";

beforeEach(() => {
  __resetLedgerForTests();
  __resetPassForTests();
  __resetMarketForTests();
  __resetCardEconomyForTests();
});

test("wallet: starter grant, earn and spend", () => {
  const w0 = walletOf("fan1");
  assert.equal(w0.credits, 250);
  earn("fan1", EARN.correctCall, "call");
  assert.equal(walletOf("fan1").credits, 265);
  assert.equal(spend("fan1", 1000, "too much"), null);
  assert.equal(spend("fan1", 65, "ok"), 200);
});

test("pass: XP tiers, premium gate, claims", () => {
  assert.equal(TRACK.length, TIER_COUNT * 2);
  const r1 = addXp("fan1", 250, "test");
  assert.equal(r1.tier, 2);
  assert.equal(r1.tiersCrossed, 2);
  // premium reward locked before purchase
  const locked = claimReward("fan1", 1, "premium");
  assert.ok("error" in locked);
  unlockPremium("fan1");
  const claimed = claimReward("fan1", 1, "premium");
  assert.ok(!("error" in claimed));
  // no double-claim
  assert.ok("error" in claimReward("fan1", 1, "premium"));
  // free credits reward pays FC
  const before = walletOf("fan1").credits;
  const free = claimReward("fan1", 1, "free");
  assert.ok(!("error" in free));
  assert.equal(walletOf("fan1").credits, before + 50);
  // pass revenue recorded once
  unlockPremium("fan1");
  const hq = hqView();
  assert.equal(hq.totals.pass.events, 1);
  assert.equal(hq.totals.pass.amount, 15);
});

test("market: listing, buy settles with 2% fee to the ledger", () => {
  const all = browse(); // seeds bots
  assert.ok(all.length >= 8, "bot listings seeded");
  const l = all[0];
  earn("buyer", 5000, "seed");
  const res = buyListing("buyer", "Buyer", l.id);
  assert.ok(!("error" in res));
  const fee = Math.max(1, Math.round(l.priceFC * MARKET_FEE));
  assert.equal(res.feeFC, fee);
  // buyer now owns the card
  const inv = inventoryOf("buyer");
  assert.ok(inv.players.some((c) => c.id === l.cardId));
  // seller got price - fee
  assert.equal(walletOf(l.sellerId).credits, 250 + l.priceFC - fee);
  // ledger recorded the fee
  assert.equal(hqView().totals["market-fee"].amount, fee);
  // can't buy twice
  assert.ok("error" in buyListing("buyer", "Buyer", l.id));
});

test("market: list own card then another fan buys it", () => {
  // give fan1 a card via a shop pack
  earn("fan1", 1000, "seed");
  const bought = buyPack("fan1", "starter");
  assert.ok(!("error" in bought));
  const opened = openPack("fan1", bought.packs[0].id, () => 0.4);
  assert.ok(!("error" in opened));
  const card = opened.cards[0];
  const listing = listCard("fan1", "Fan One", card.id, 300);
  assert.ok(!("error" in listing));
  earn("fan2", 1000, "seed");
  const sale = buyListing("fan2", "Fan Two", listing.id);
  assert.ok(!("error" in sale));
  assert.ok(inventoryOf("fan2").players.some((c) => c.id === card.id));
  assert.ok(!inventoryOf("fan1").players.some((c) => c.id === card.id));
});

test("shop: tiers priced, packs granted, USD concept revenue recorded", () => {
  assert.equal(SHOP.length, 3);
  earn("fan1", 2000, "seed");
  const legend = buyPack("fan1", "legend");
  assert.ok(!("error" in legend));
  assert.equal(legend.packs.length, 3);
  assert.equal(hqView().totals.packs.amount, 20);
  const broke = buyPack("fan-broke", "legend"); // only starter 250 FC
  assert.ok("error" in broke);
});

test("hq: revenue aggregates across layers and units", () => {
  walletOf("fan1"); // materialize a wallet so fan count reflects it
  recordRevenue("mint-fee", 5_000_000, "lamports", "mint x", "fan1");
  recordRevenue("queue-rake", 20, "FC", "pro queue", "fan1");
  const hq = hqView();
  assert.equal(hq.totals["mint-fee"].amount, 5_000_000);
  assert.equal(hq.totals["mint-fee"].unit, "lamports");
  assert.equal(hq.totals["queue-rake"].amount, 20);
  assert.ok(hq.fans >= 1);
});
