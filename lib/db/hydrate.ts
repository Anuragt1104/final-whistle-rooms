import {
  applyDurableInventory,
  applyDurableLeaves,
} from "@/lib/cards/economy";
import {
  applyDurableRevenue,
  applyDurableWallet,
} from "@/lib/platform/ledger";
import { applyDurablePass } from "@/lib/platform/pass";
import { economyStoreEnabled, hydrateDurableStores } from "./durable";

let ready: Promise<void> | null = null;

/**
 * Load durable economy/wallet/pass rows into process memory once per replica.
 * Safe to call from every authenticated duel/inventory route.
 */
export async function ensureStoreHydrated(): Promise<void> {
  if (!economyStoreEnabled()) return;
  if (!ready) {
    ready = hydrateDurableStores({
      loadInventory: applyDurableInventory,
      loadLeaves: applyDurableLeaves,
      loadWallet: applyDurableWallet,
      loadPass: applyDurablePass,
      loadRevenue: applyDurableRevenue,
    }).catch((error) => {
      ready = null;
      throw error;
    });
  }
  await ready;
}
