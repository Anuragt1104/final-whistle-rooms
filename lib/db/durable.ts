/**
 * Write-through durability for card economy, FC wallets, and Pass state.
 * Process memory remains the hot path; Postgres survives Railway restarts
 * when DATABASE_URL is set (or ECONOMY_STORE=postgres).
 */
import { getPool } from "./pool";
import { runMigrations } from "./migrate";

let hydrated = false;
let hydratePromise: Promise<void> | null = null;

export function economyStoreEnabled(): boolean {
  if (process.env.ECONOMY_STORE === "postgres") return true;
  if (process.env.ECONOMY_STORE === "memory") return false;
  return Boolean(process.env.DATABASE_URL);
}

export type DurableLoaders = {
  loadInventory: (fanId: string, inventory: unknown) => void;
  loadLeaves: (leafKey: string, leaves: string[]) => void;
  loadWallet: (fanId: string, wallet: { credits: number; earned: number; spent: number }) => void;
  loadPass: (fanId: string, state: unknown) => void;
  loadRevenue: (events: unknown[]) => void;
};

export async function hydrateDurableStores(loaders: DurableLoaders): Promise<void> {
  if (!economyStoreEnabled() || hydrated) return;
  if (!hydratePromise) {
    hydratePromise = (async () => {
      await runMigrations();
      const pool = await getPool();
      const [inv, leaves, wallets, passes, revenue] = await Promise.all([
        pool.query("SELECT fan_id, inventory FROM fan_inventories"),
        pool.query("SELECT leaf_key, leaves FROM moment_leaves"),
        pool.query("SELECT fan_id, credits, earned, spent FROM fan_wallets"),
        pool.query("SELECT fan_id, state FROM fan_passes"),
        pool.query("SELECT event FROM platform_revenue ORDER BY created_at ASC LIMIT 500"),
      ]);
      for (const row of inv.rows) loaders.loadInventory(row.fan_id, row.inventory);
      for (const row of leaves.rows) {
        loaders.loadLeaves(row.leaf_key, Array.isArray(row.leaves) ? row.leaves : []);
      }
      for (const row of wallets.rows) {
        loaders.loadWallet(row.fan_id, {
          credits: Number(row.credits),
          earned: Number(row.earned),
          spent: Number(row.spent),
        });
      }
      for (const row of passes.rows) loaders.loadPass(row.fan_id, row.state);
      loaders.loadRevenue(revenue.rows.map((row) => row.event));
      hydrated = true;
    })().catch((error) => {
      hydratePromise = null;
      throw error;
    });
  }
  await hydratePromise;
}

export async function persistInventory(fanId: string, inventory: unknown) {
  if (!economyStoreEnabled()) return;
  await runMigrations();
  const pool = await getPool();
  await pool.query(
    `INSERT INTO fan_inventories(fan_id, inventory, updated_at)
     VALUES ($1, $2::jsonb, now())
     ON CONFLICT (fan_id) DO UPDATE SET inventory = EXCLUDED.inventory, updated_at = now()`,
    [fanId, JSON.stringify(inventory)],
  );
}

export async function persistLeaves(leafKey: string, leaves: string[]) {
  if (!economyStoreEnabled()) return;
  await runMigrations();
  const pool = await getPool();
  await pool.query(
    `INSERT INTO moment_leaves(leaf_key, leaves, updated_at)
     VALUES ($1, $2::jsonb, now())
     ON CONFLICT (leaf_key) DO UPDATE SET leaves = EXCLUDED.leaves, updated_at = now()`,
    [leafKey, JSON.stringify(leaves)],
  );
}

export async function persistWallet(
  fanId: string,
  wallet: { credits: number; earned: number; spent: number },
) {
  if (!economyStoreEnabled()) return;
  await runMigrations();
  const pool = await getPool();
  await pool.query(
    `INSERT INTO fan_wallets(fan_id, credits, earned, spent, updated_at)
     VALUES ($1, $2, $3, $4, now())
     ON CONFLICT (fan_id) DO UPDATE SET
       credits = EXCLUDED.credits,
       earned = EXCLUDED.earned,
       spent = EXCLUDED.spent,
       updated_at = now()`,
    [fanId, wallet.credits, wallet.earned, wallet.spent],
  );
}

export async function persistPass(fanId: string, state: unknown) {
  if (!economyStoreEnabled()) return;
  await runMigrations();
  const pool = await getPool();
  await pool.query(
    `INSERT INTO fan_passes(fan_id, state, updated_at)
     VALUES ($1, $2::jsonb, now())
     ON CONFLICT (fan_id) DO UPDATE SET state = EXCLUDED.state, updated_at = now()`,
    [fanId, JSON.stringify(state)],
  );
}

export async function persistRevenue(event: { id: string }) {
  if (!economyStoreEnabled()) return;
  await runMigrations();
  const pool = await getPool();
  await pool.query(
    `INSERT INTO platform_revenue(id, event) VALUES ($1, $2::jsonb)
     ON CONFLICT (id) DO NOTHING`,
    [event.id, JSON.stringify(event)],
  );
}

export function __resetDurableHydrationForTests() {
  hydrated = false;
  hydratePromise = null;
}
