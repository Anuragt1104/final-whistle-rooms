/**
 * The Marketplace (Revenue Layer 3) — player-owned economy, platform takes 2%.
 *
 * Listings are priced in Fan Credits (the points-only rail); every settlement
 * records the 2% fee in the revenue ledger. On-chain settlement in SOL with
 * the same fee split is the documented mainnet upgrade — the market mechanics,
 * provenance and fee model are identical, only the settlement rail changes.
 */
import { getCard, inventoryOf, registerCard, transferCard } from "@/lib/cards/economy";
import type { Card, PlayerCard } from "@/lib/cards/types";
import { earn, recordRevenue, spend } from "./ledger";
import { addXp, XP } from "./pass";

export const MARKET_FEE = 0.02;

export interface Listing {
  id: string;
  cardId: string;
  card: Card;
  sellerId: string;
  sellerName: string;
  priceFC: number;
  listedAt: number;
  sold?: { buyerId: string; at: number };
}

const listings = (() => {
  const g = globalThis as unknown as {
    __fwr_market?: { listings: Map<string, Listing>; botSeeded: boolean };
  };
  if (!g.__fwr_market) g.__fwr_market = { listings: new Map(), botSeeded: false };
  return g.__fwr_market.listings;
})();
let botSeeded = (() => {
  const g = globalThis as unknown as {
    __fwr_market?: { listings: Map<string, Listing>; botSeeded: boolean };
  };
  if (!g.__fwr_market) g.__fwr_market = { listings: new Map(), botSeeded: false };
  return g.__fwr_market.botSeeded;
})();

function setBotSeeded(v: boolean) {
  const g = globalThis as unknown as {
    __fwr_market?: { listings: Map<string, Listing>; botSeeded: boolean };
  };
  if (!g.__fwr_market) g.__fwr_market = { listings: new Map(), botSeeded: false };
  g.__fwr_market.botSeeded = v;
  botSeeded = v;
}

function uid(prefix: string): string {
  return `${prefix}_${Math.random().toString(36).slice(2, 10)}${Date.now().toString(36).slice(-4)}`;
}

export function listCard(fanId: string, sellerName: string, cardId: string, priceFC: number): Listing | { error: string } {
  if (priceFC < 10 || priceFC > 100_000) return { error: "Price must be 10–100,000 FC" };
  const inv = inventoryOf(fanId);
  const owned = [...inv.moments, ...inv.players, ...inv.skills].find((c) => c.id === cardId);
  if (!owned) return { error: "You don't own that card" };
  if ([...listings.values()].some((l) => l.cardId === cardId && !l.sold)) return { error: "Already listed" };
  const listing: Listing = { id: uid("lst"), cardId, card: owned, sellerId: fanId, sellerName, priceFC, listedAt: Date.now() };
  listings.set(listing.id, listing);
  return listing;
}

export function cancelListing(fanId: string, listingId: string): boolean {
  const l = listings.get(listingId);
  if (!l || l.sellerId !== fanId || l.sold) return false;
  listings.delete(listingId);
  return true;
}

export function buyListing(buyerId: string, buyerName: string, listingId: string): { listing: Listing; feeFC: number } | { error: string } {
  const l = listings.get(listingId);
  if (!l || l.sold) return { error: "Listing gone" };
  if (l.sellerId === buyerId) return { error: "That's your own listing" };
  const after = spend(buyerId, l.priceFC, `buy ${l.card.id}`);
  if (after == null) return { error: "Not enough FC" };
  const fee = Math.max(1, Math.round(l.priceFC * MARKET_FEE));
  // settle: seller gets price - fee, platform records the fee
  earn(l.sellerId, l.priceFC - fee, `sold ${l.card.id}`);
  recordRevenue("market-fee", fee, "FC", `2% of ${l.priceFC} FC — ${cardLabel(l.card)}`, buyerId);
  const moved = transferCard(l.cardId, l.sellerId, buyerId);
  if (!moved) {
    // seller no longer holds it (shouldn't happen) — refund
    earn(buyerId, l.priceFC, "refund");
    spend(l.sellerId, l.priceFC - fee, "reversal");
    listings.delete(listingId);
    return { error: "Card no longer available" };
  }
  l.sold = { buyerId, at: Date.now() };
  l.card = moved;
  addXp(buyerId, XP.marketTrade, "market");
  addXp(l.sellerId, XP.marketTrade, "market");
  void buyerName;
  return { listing: l, feeFC: fee };
}

export function browse(): Listing[] {
  seedBotListings();
  return [...listings.values()].filter((l) => !l.sold).sort((a, b) => b.listedAt - a.listedAt);
}

export function myListings(fanId: string): Listing[] {
  return [...listings.values()].filter((l) => l.sellerId === fanId);
}

function cardLabel(c: Card): string {
  return c.type === "player" ? c.name : c.type === "moment" ? c.label : c.name;
}

/**
 * Seed the market with bot listings so it's alive on first open — named sim
 * fans list player cards at prices scaled by their axis totals.
 */
const BOT_SELLERS = ["marcus_k", "priya_d", "noor", "diego", "sam", "mia"];
const BOT_PLAYERS: Array<[string, string, string, string, number]> = [
  // name, teamCode, teamName, position, axisTotal-ish price base
  ["Kylian Mbappé", "FRA", "France", "FW", 900],
  ["Jude Bellingham", "ENG", "England", "MF", 780],
  ["Vinícius Júnior", "BRA", "Brazil", "FW", 860],
  ["Rodri", "SPA", "Spain", "MF", 700],
  ["Alisson", "BRA", "Brazil", "GK", 560],
  ["Achraf Hakimi", "MAR", "Morocco", "DF", 520],
  ["Lautaro Martínez", "ARG", "Argentina", "FW", 740],
  ["Virgil van Dijk", "NED", "Netherlands", "DF", 640],
];

function seedBotListings() {
  if (botSeeded) return;
  setBotSeeded(true);
  BOT_PLAYERS.forEach(([name, teamCode, teamName, position, base], i) => {
    const seller = BOT_SELLERS[i % BOT_SELLERS.length];
    const botId = `bot:${seller}`;
    const axes = {
      finishing: 40 + ((base + i * 7) % 55),
      chaos: 30 + ((base * 3 + i * 11) % 60),
      clutch: 35 + ((base * 5 + i * 13) % 60),
      marketShock: 25 + ((base * 7 + i * 17) % 65),
      aura: 45 + ((base * 11 + i * 19) % 50),
    };
    const card: PlayerCard = {
      id: uid("pc"),
      type: "player",
      ownerId: botId,
      playerId: `${teamCode}-${name.split(" ").pop()}`,
      name,
      teamCode,
      teamName,
      position,
      axes,
      leafData: `market-seed|${teamCode}|${name}`,
      createdAt: Date.now() - i * 3_600_000,
    };
    registerCard(card);
    const inv = inventoryOf(botId);
    inv.players.push(card);
    const listing: Listing = {
      id: uid("lst"),
      cardId: card.id,
      card,
      sellerId: botId,
      sellerName: seller,
      priceFC: base + (i % 3) * 45,
      listedAt: Date.now() - i * 1_800_000,
    };
    listings.set(listing.id, listing);
  });
}

export function __resetMarketForTests() {
  listings.clear();
  setBotSeeded(false);
}
