import { runMigrations } from "@/lib/db/migrate";
import { getPool } from "@/lib/db/pool";
import type { DuelState, DuelView } from "./types";

export interface StoredDuelEvent {
  duelId: string;
  version: number;
  event: { type: string; view?: DuelView };
}

export interface ActionResult {
  state: DuelState;
  duplicate: boolean;
}

export interface DuelRepository {
  create(state: DuelState, event: StoredDuelEvent["event"]): Promise<void>;
  get(id: string): Promise<DuelState | null>;
  findByCode(code: string): Promise<DuelState | null>;
  applyAction(
    id: string,
    actorId: string,
    actionId: string,
    mutate: (state: DuelState) => DuelState,
    event: (state: DuelState) => StoredDuelEvent["event"],
  ): Promise<ActionResult>;
  events(id: string, afterVersion: number): Promise<StoredDuelEvent[]>;
  grantRewardOnce(id: string, fanId: string, result: "win" | "loss" | "draw"): Promise<boolean>;
  registerDevice(fanId: string, token: string, platform: string, fixtureIds: string[]): Promise<void>;
  devicesForFan(fanId: string): Promise<string[]>;
}

type MemoryData = {
  states: Map<string, DuelState>;
  actions: Map<string, DuelState>;
  events: StoredDuelEvent[];
  rewards: Set<string>;
  devices: Map<string, { fanId: string; platform: string; fixtureIds: string[] }>;
};

const memoryGlobal = globalThis as unknown as { __fwr_duel_repository?: MemoryData };
const memoryData = (memoryGlobal.__fwr_duel_repository ??= {
  states: new Map(),
  actions: new Map(),
  events: [] as StoredDuelEvent[],
  rewards: new Set(),
  devices: new Map(),
} as MemoryData);

const copy = <T>(value: T): T => structuredClone(value);

export class MemoryDuelRepository implements DuelRepository {
  constructor(private readonly data = memoryData) {}

  async create(state: DuelState, event: StoredDuelEvent["event"]) {
    if (this.data.states.has(state.id)) throw new Error("duel already exists");
    this.data.states.set(state.id, copy(state));
    this.data.events.push({ duelId: state.id, version: state.version, event: copy(event) });
  }

  async get(id: string) {
    const state = this.data.states.get(id);
    return state ? copy(state) : null;
  }

  async findByCode(code: string) {
    const state = [...this.data.states.values()].find((candidate) => candidate.code === code.toUpperCase());
    return state ? copy(state) : null;
  }

  async applyAction(
    id: string,
    actorId: string,
    actionId: string,
    mutate: (state: DuelState) => DuelState,
    event: (state: DuelState) => StoredDuelEvent["event"],
  ) {
    const key = `${id}:${actorId}:${actionId}`;
    const previous = this.data.actions.get(key);
    if (previous) return { state: copy(previous), duplicate: true };
    const current = this.data.states.get(id);
    if (!current) throw new Error("duel not found");
    const next = mutate(copy(current));
    this.data.states.set(id, copy(next));
    this.data.actions.set(key, copy(next));
    this.data.events.push({ duelId: id, version: next.version, event: copy(event(next)) });
    return { state: copy(next), duplicate: false };
  }

  async events(id: string, afterVersion: number) {
    return this.data.events
      .filter((event) => event.duelId === id && event.version > afterVersion)
      .map(copy);
  }

  async grantRewardOnce(id: string, fanId: string) {
    const key = `${id}:${fanId}`;
    if (this.data.rewards.has(key)) return false;
    this.data.rewards.add(key);
    return true;
  }

  async registerDevice(fanId: string, token: string, platform: string, fixtureIds: string[]) {
    this.data.devices.set(token, { fanId, platform, fixtureIds: [...fixtureIds] });
  }

  async devicesForFan(fanId: string) {
    return [...this.data.devices]
      .filter(([, device]) => device.fanId === fanId)
      .map(([token]) => token);
  }

  reset() {
    this.data.states.clear();
    this.data.actions.clear();
    this.data.events.length = 0;
    this.data.rewards.clear();
    this.data.devices.clear();
  }
}

let migrated: Promise<void> | undefined;
async function ready() {
  migrated ??= runMigrations();
  await migrated;
  return getPool();
}

export class PostgresDuelRepository implements DuelRepository {
  async create(state: DuelState, event: StoredDuelEvent["event"]) {
    const pool = await ready();
    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      await client.query(
        "INSERT INTO duel_states(id, invite_code, version, state) VALUES($1,$2,$3,$4)",
        [state.id, state.code, state.version, state],
      );
      await client.query(
        "INSERT INTO duel_events(duel_id, version, event) VALUES($1,$2,$3)",
        [state.id, state.version, event],
      );
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async get(id: string) {
    const pool = await ready();
    const result = await pool.query<{ state: DuelState }>("SELECT state FROM duel_states WHERE id=$1", [id]);
    return result.rows[0]?.state ?? null;
  }

  async findByCode(code: string) {
    const pool = await ready();
    const result = await pool.query<{ state: DuelState }>(
      "SELECT state FROM duel_states WHERE invite_code=$1",
      [code.toUpperCase()],
    );
    return result.rows[0]?.state ?? null;
  }

  async applyAction(
    id: string,
    actorId: string,
    actionId: string,
    mutate: (state: DuelState) => DuelState,
    event: (state: DuelState) => StoredDuelEvent["event"],
  ) {
    const pool = await ready();
    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      const duplicate = await client.query<{ result: DuelState }>(
        "SELECT result FROM duel_actions WHERE duel_id=$1 AND actor_id=$2 AND action_id=$3",
        [id, actorId, actionId],
      );
      if (duplicate.rows[0]) {
        await client.query("COMMIT");
        return { state: duplicate.rows[0].result, duplicate: true };
      }
      const locked = await client.query<{ state: DuelState; version: number }>(
        "SELECT state, version FROM duel_states WHERE id=$1 FOR UPDATE",
        [id],
      );
      if (!locked.rows[0]) throw new Error("duel not found");
      const next = mutate(locked.rows[0].state);
      const updated = await client.query(
        "UPDATE duel_states SET state=$1, version=$2, updated_at=now() WHERE id=$3 AND version=$4",
        [next, next.version, id, locked.rows[0].version],
      );
      if (updated.rowCount !== 1) throw new Error("duel version conflict");
      await client.query(
        "INSERT INTO duel_actions(duel_id, actor_id, action_id, result) VALUES($1,$2,$3,$4)",
        [id, actorId, actionId, next],
      );
      await client.query(
        "INSERT INTO duel_events(duel_id, version, event) VALUES($1,$2,$3)",
        [id, next.version, event(next)],
      );
      await client.query("COMMIT");
      return { state: next, duplicate: false };
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async events(id: string, afterVersion: number) {
    const pool = await ready();
    const result = await pool.query<{ version: number; event: StoredDuelEvent["event"] }>(
      "SELECT version,event FROM duel_events WHERE duel_id=$1 AND version>$2 ORDER BY version",
      [id, afterVersion],
    );
    return result.rows.map((row) => ({ duelId: id, ...row }));
  }

  async grantRewardOnce(id: string, fanId: string, result: "win" | "loss" | "draw") {
    const pool = await ready();
    const inserted = await pool.query(
      "INSERT INTO duel_reward_grants(duel_id,fan_id,result) VALUES($1,$2,$3) ON CONFLICT DO NOTHING",
      [id, fanId, result],
    );
    return inserted.rowCount === 1;
  }

  async registerDevice(fanId: string, token: string, platform: string, fixtureIds: string[]) {
    const pool = await ready();
    await pool.query(
      `INSERT INTO fan_devices(token,fan_id,platform,fixture_ids)
       VALUES($1,$2,$3,$4)
       ON CONFLICT(token) DO UPDATE SET fan_id=$2,platform=$3,fixture_ids=$4,registered_at=now()`,
      [token, fanId, platform, fixtureIds],
    );
  }

  async devicesForFan(fanId: string) {
    const pool = await ready();
    const result = await pool.query<{ token: string }>("SELECT token FROM fan_devices WHERE fan_id=$1", [fanId]);
    return result.rows.map((row) => row.token);
  }
}

let selected: DuelRepository | undefined;
export function duelRepository(): DuelRepository {
  return (selected ??= process.env.DUEL_STORE === "postgres"
    ? new PostgresDuelRepository()
    : new MemoryDuelRepository());
}

export function setDuelRepositoryForTests(repository?: DuelRepository) {
  selected = repository;
}
