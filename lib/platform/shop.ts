/**
 * The Pack Shop (Revenue Layer 2). Packs are bought with EARNED Fan Credits —
 * never cash — which keeps the economy points-only; the ledger records the
 * concept USD price point each tier maps to ($2/$5/$20) so the revenue model
 * reads like the real store. Purchased packs add variety, never raw power
 * (openPack odds are identical to earned packs of the same weight).
 */
import { inventoryOf } from "@/lib/cards/economy";
import type { PackGrant } from "@/lib/cards/types";
import { recordRevenue, spend } from "./ledger";

export interface ShopTier {
  id: "starter" | "premium" | "legend";
  label: string;
  priceFC: number;
  conceptUsd: number;
  grants: number; // pack charges granted
  weight: number; // pack weight (>=2 rolls skill-card chance)
  blurb: string;
}

export const SHOP: ShopTier[] = [
  { id: "starter", label: "Starter Pack", priceFC: 100, conceptUsd: 2, grants: 1, weight: 1, blurb: "One player card. Somewhere to start." },
  { id: "premium", label: "Premium Pack", priceFC: 250, conceptUsd: 5, grants: 1, weight: 2.5, blurb: "One player card with a skill-card chance." },
  { id: "legend", label: "Legend Pack", priceFC: 800, conceptUsd: 20, grants: 3, weight: 3, blurb: "Three charges, each with a skill-card chance." },
];

function uid(prefix: string): string {
  return `${prefix}_${Math.random().toString(36).slice(2, 10)}${Date.now().toString(36).slice(-4)}`;
}

export function buyPack(fanId: string, tierId: string): { packs: PackGrant[]; creditsLeft: number } | { error: string } {
  const tier = SHOP.find((t) => t.id === tierId);
  if (!tier) return { error: "Unknown pack tier" };
  const left = spend(fanId, tier.priceFC, `shop ${tier.id}`);
  if (left == null) return { error: `Not enough FC (need ${tier.priceFC})` };
  recordRevenue("packs", tier.conceptUsd, "USD", `${tier.label} — ${tier.priceFC} FC`, fanId);
  const inv = inventoryOf(fanId);
  const packs: PackGrant[] = [];
  for (let i = 0; i < tier.grants; i++) {
    const pack: PackGrant = {
      id: uid("pack"),
      ownerId: fanId,
      weight: tier.weight,
      momentIds: [],
      opened: false,
      cards: [],
      createdAt: Date.now(),
    };
    inv.packs.push(pack);
    packs.push(pack);
  }
  return { packs, creditsLeft: left };
}
