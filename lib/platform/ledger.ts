/**
 * Platform economy core — Fan Credits + the revenue ledger.
 *
 * Positioning (see SUBMISSION.md): this is a GAMING PLATFORM where football is
 * the content, not a betting product. Fan Credits (FC) are a points-only soft
 * currency — earned by skill and participation, never cashed out. Every
 * monetized surface (pass, packs, marketplace fee, mint fee, ranked rake)
 * records a revenue event here, so the business model is a running system the
 * judges can watch, not a slide.
 */

export type RevenueLayer =
  | "pass" // World Cup Pass premium unlocks
  | "packs" // direct pack purchases
  | "market-fee" // 2% marketplace take
  | "mint-fee" // Solana mint fee share
  | "queue-rake"; // Pro Queue entry rake

export interface RevenueEvent {
  id: string;
  layer: RevenueLayer;
  /** FC for soft-currency layers; lamports for the mint rail. */
  amount: number;
  unit: "FC" | "lamports" | "USD";
  detail: string;
  fanId?: string;
  ts: number;
}

export interface WalletView {
  fanId: string;
  credits: number;
  lifetimeEarned: number;
  lifetimeSpent: number;
}

const balances = new Map<string, { credits: number; earned: number; spent: number }>();
const revenue: RevenueEvent[] = [];

function uid(prefix: string): string {
  return `${prefix}_${Math.random().toString(36).slice(2, 10)}${Date.now().toString(36).slice(-4)}`;
}

function bal(fanId: string) {
  let b = balances.get(fanId);
  if (!b) {
    // starter grant so every new fan can act immediately (shop tour, first list)
    b = { credits: 250, earned: 250, spent: 0 };
    balances.set(fanId, b);
  }
  return b;
}

export function walletOf(fanId: string): WalletView {
  const b = bal(fanId);
  return { fanId, credits: b.credits, lifetimeEarned: b.earned, lifetimeSpent: b.spent };
}

/** Earn FC (skill/participation). Returns the new balance. */
export function earn(fanId: string, amount: number, _reason: string): number {
  if (amount <= 0) return bal(fanId).credits;
  const b = bal(fanId);
  b.credits += amount;
  b.earned += amount;
  return b.credits;
}

/** Spend FC. Returns new balance or null when insufficient. */
export function spend(fanId: string, amount: number, _reason: string): number | null {
  const b = bal(fanId);
  if (amount < 0 || b.credits < amount) return null;
  b.credits -= amount;
  b.spent += amount;
  return b.credits;
}

/** Record platform revenue (the investor-facing ledger). */
export function recordRevenue(layer: RevenueLayer, amount: number, unit: "FC" | "lamports" | "USD", detail: string, fanId?: string): RevenueEvent {
  const ev: RevenueEvent = { id: uid("rev"), layer, amount, unit, detail, fanId, ts: Date.now() };
  revenue.push(ev);
  if (revenue.length > 500) revenue.shift();
  return ev;
}

export interface HqView {
  totals: Record<RevenueLayer, { amount: number; unit: "FC" | "lamports" | "USD"; events: number }>;
  recent: RevenueEvent[];
  fans: number;
  circulating: number; // FC in wallets
}

export function hqView(): HqView {
  const totals = {} as HqView["totals"];
  for (const layer of ["pass", "packs", "market-fee", "mint-fee", "queue-rake"] as RevenueLayer[]) {
    totals[layer] = { amount: 0, unit: layer === "mint-fee" ? "lamports" : layer === "pass" || layer === "packs" ? "USD" : "FC", events: 0 };
  }
  for (const ev of revenue) {
    totals[ev.layer].amount += ev.amount;
    totals[ev.layer].events += 1;
  }
  let circulating = 0;
  for (const b of balances.values()) circulating += b.credits;
  return { totals, recent: revenue.slice(-25).reverse(), fans: balances.size, circulating };
}

/** FC earn table — one place, referenced by hooks + docs. */
export const EARN = {
  correctCall: 15, // Higher/Lower or Next Swing correct
  streakBonus: 10, // per correct call while streak >= 3
  packOpened: 5,
  craft: 20,
  duelWin: 40,
  duelLoss: 10, // participation
  momentMinted: 8, // a live moment landed in your inventory
} as const;

export function __resetLedgerForTests() {
  balances.clear();
  revenue.length = 0;
}
