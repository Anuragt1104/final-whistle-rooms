/**
 * Fixture event tape archive — TxLINE historical windows expire; we persist
 * compressed JSON on game_finalised for replay parity + history priors.
 */
import { gzipSync, gunzipSync } from "zlib";
import type { MatchEvent, ScoreSnapshot } from "@/lib/txline/types";

export interface FixtureTapePayload {
  fixtureId: string;
  kickoff?: string;
  scores: ScoreSnapshot[];
  events: MatchEvent[];
  archivedAt: number;
}

export function compressTape(payload: FixtureTapePayload): Buffer {
  return gzipSync(Buffer.from(JSON.stringify(payload), "utf8"));
}

export function decompressTape(buf: Buffer | Uint8Array): FixtureTapePayload {
  const json = gunzipSync(buf).toString("utf8");
  return JSON.parse(json) as FixtureTapePayload;
}

/** Best-effort persist when DATABASE_URL is set. */
export async function archiveFixtureTape(payload: FixtureTapePayload): Promise<boolean> {
  if (!process.env.DATABASE_URL) return false;
  try {
    const { getPool } = await import("@/lib/db/pool");
    const pool = await getPool();
    const tape = compressTape(payload);
    await pool.query(
      `INSERT INTO fixture_event_tapes (fixture_id, kickoff, tape, meta, archived_at)
       VALUES ($1, $2, $3, $4, now())
       ON CONFLICT (fixture_id) DO UPDATE SET
         tape = EXCLUDED.tape,
         meta = EXCLUDED.meta,
         kickoff = EXCLUDED.kickoff,
         archived_at = now()`,
      [
        payload.fixtureId,
        payload.kickoff ?? null,
        tape,
        JSON.stringify({
          scoreCount: payload.scores.length,
          eventCount: payload.events.length,
          archivedAt: payload.archivedAt,
        }),
      ],
    );
    return true;
  } catch {
    return false;
  }
}

export async function loadFixtureTape(fixtureId: string): Promise<FixtureTapePayload | null> {
  if (!process.env.DATABASE_URL) return null;
  try {
    const { getPool } = await import("@/lib/db/pool");
    const pool = await getPool();
    const res = await pool.query<{ tape: Buffer }>(
      `SELECT tape FROM fixture_event_tapes WHERE fixture_id = $1`,
      [fixtureId],
    );
    if (!res.rows[0]) return null;
    return decompressTape(res.rows[0].tape);
  } catch {
    return null;
  }
}
