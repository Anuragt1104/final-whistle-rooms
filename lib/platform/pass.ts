/**
 * The World Cup Pass — the platform's battle pass (Revenue Layer 1).
 *
 * One pass per football season: World Cup today, Champions League / Premier
 * League next (the pass is parameterized by name so seasons rotate). Two
 * lanes: FREE (everyone progresses) and PREMIUM ($15 concept purchase —
 * cosmetics, capacity and access, never pay-to-win). XP flows from every core
 * loop action, so the pass is the connective tissue between watching,
 * predicting, collecting and battling.
 */
import { earn, recordRevenue } from "./ledger";

export const XP = {
  correctCall: 10,
  momentMinted: 5,
  packOpened: 15,
  craft: 20,
  duelWin: 25,
  duelLoss: 8,
  marketTrade: 10,
  cardMintedOnChain: 15,
} as const;

export const XP_PER_TIER = 100;
export const TIER_COUNT = 20;
export const PASS_PRICE_USD = 15;

export type PassRewardKind =
  | "credits" // FC grant
  | "pack" // bonus pack weight token (redeemed by the economy)
  | "cardback" // cosmetic card back
  | "deckSlot" // extra saved deck slot
  | "proTicket" // Pro Queue entry ticket
  | "title"; // profile title cosmetic

export interface PassReward {
  tier: number;
  lane: "free" | "premium";
  kind: PassRewardKind;
  amount?: number;
  label: string;
}

/** The full 20-tier reward track (free lane + premium lane). */
export const TRACK: PassReward[] = (() => {
  const t: PassReward[] = [];
  const freeCycle: Array<[PassRewardKind, number | undefined, string]> = [
    ["credits", 50, "50 FC"],
    ["pack", 1, "Bonus pack"],
    ["credits", 75, "75 FC"],
    ["title", undefined, "Title: Ultra"],
  ];
  const premiumCycle: Array<[PassRewardKind, number | undefined, string]> = [
    ["credits", 150, "150 FC"],
    ["cardback", undefined, "Card back: Foil Terrace"],
    ["pack", 2, "2 Bonus packs"],
    ["proTicket", 1, "Pro Queue ticket"],
    ["deckSlot", 1, "Extra deck slot"],
  ];
  for (let tier = 1; tier <= TIER_COUNT; tier++) {
    const f = freeCycle[(tier - 1) % freeCycle.length];
    t.push({ tier, lane: "free", kind: f[0], amount: f[1], label: f[2] });
    const p = premiumCycle[(tier - 1) % premiumCycle.length];
    t.push({ tier, lane: "premium", kind: p[0], amount: p[1], label: p[2] });
  }
  // milestone overrides — the aspirational pulls
  const override = (tier: number, lane: "free" | "premium", kind: PassRewardKind, amount: number | undefined, label: string) => {
    const i = t.findIndex((r) => r.tier === tier && r.lane === lane);
    t[i] = { tier, lane, kind, amount, label };
  };
  override(5, "premium", "cardback", undefined, "Card back: Golden Ticket");
  override(10, "premium", "proTicket", 3, "3 Pro Queue tickets");
  override(15, "premium", "cardback", undefined, "Card back: Holo Pitch");
  override(20, "free", "title", undefined, "Title: Season Veteran");
  override(20, "premium", "cardback", undefined, "Card back: TROPHY GOLD — pass exclusive, never reissued");
  return t;
})();

export interface PassState {
  fanId: string;
  season: string;
  xp: number;
  tier: number; // derived, stored for convenience
  premium: boolean;
  claimed: string[]; // `${tier}:${lane}`
  cosmetics: string[]; // card backs + titles unlocked
  proTickets: number;
  deckSlots: number; // base 1
}

const passes = new Map<string, PassState>();

function state(fanId: string): PassState {
  let p = passes.get(fanId);
  if (!p) {
    p = { fanId, season: "World Cup 2026", xp: 0, tier: 0, premium: false, claimed: [], cosmetics: [], proTickets: 0, deckSlots: 1 };
    passes.set(fanId, p);
  }
  return p;
}

export function passOf(fanId: string): PassState {
  return state(fanId);
}

/** Add XP from any loop action; returns tiers crossed (for celebration UI). */
export function addXp(fanId: string, amount: number, _source: string): { xp: number; tier: number; tiersCrossed: number } {
  const p = state(fanId);
  const before = p.tier;
  p.xp += Math.max(0, amount);
  p.tier = Math.min(TIER_COUNT, Math.floor(p.xp / XP_PER_TIER));
  return { xp: p.xp, tier: p.tier, tiersCrossed: p.tier - before };
}

export function unlockPremium(fanId: string): PassState {
  const p = state(fanId);
  if (!p.premium) {
    p.premium = true;
    recordRevenue("pass", PASS_PRICE_USD, "USD", `World Cup Pass premium — ${fanId.slice(0, 8)}`, fanId);
  }
  return p;
}

export function claimReward(fanId: string, tier: number, lane: "free" | "premium"): { state: PassState; reward: PassReward } | { error: string } {
  const p = state(fanId);
  const reward = TRACK.find((r) => r.tier === tier && r.lane === lane);
  if (!reward) return { error: "No such reward" };
  if (p.tier < tier) return { error: `Reach tier ${tier} first` };
  if (lane === "premium" && !p.premium) return { error: "Premium pass required" };
  const key = `${tier}:${lane}`;
  if (p.claimed.includes(key)) return { error: "Already claimed" };
  p.claimed.push(key);
  switch (reward.kind) {
    case "credits":
      earn(fanId, reward.amount ?? 0, `pass tier ${tier}`);
      break;
    case "proTicket":
      p.proTickets += reward.amount ?? 1;
      break;
    case "deckSlot":
      p.deckSlots += reward.amount ?? 1;
      break;
    case "cardback":
    case "title":
      p.cosmetics.push(reward.label);
      break;
    case "pack":
      // pack tokens are granted as FC-equivalent weight via the economy's
      // pack-weight bonus; the route layer wires this to grantPackWeight
      break;
  }
  return { state: p, reward };
}

export function spendProTicket(fanId: string): boolean {
  const p = state(fanId);
  if (p.proTickets <= 0) return false;
  p.proTickets -= 1;
  return true;
}

export function __resetPassForTests() {
  passes.clear();
}
