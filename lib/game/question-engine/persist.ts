/**
 * Optional Postgres persistence for question instances / answers / rewards.
 */
import type { QuestionSpec } from "./types";
import { ENGINE_VERSION } from "./types";

async function poolOrNull() {
  if (!process.env.DATABASE_URL) return null;
  try {
    const { getPool } = await import("@/lib/db/pool");
    return await getPool();
  } catch {
    return null;
  }
}

export async function persistQuestionInstance(q: QuestionSpec): Promise<void> {
  const pool = await poolOrNull();
  if (!pool) return;
  try {
    await pool.query(
      `INSERT INTO question_instances
        (id, fixture_id, rule_id, rule_version, lane, status, spec, winner_key, engine_version, opened_at, settled_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
       ON CONFLICT (id) DO UPDATE SET
         status = EXCLUDED.status,
         winner_key = EXCLUDED.winner_key,
         spec = EXCLUDED.spec,
         settled_at = EXCLUDED.settled_at`,
      [
        q.id,
        q.fixtureId,
        q.ruleId,
        q.ruleVersion,
        q.lane,
        q.status,
        JSON.stringify(q),
        q.winningKey ?? null,
        ENGINE_VERSION,
        q.openedAtMinute != null ? new Date(q.createdAt) : null,
        q.status === "settled" || q.status === "void" || q.status === "corrected"
          ? new Date()
          : null,
      ],
    );
  } catch {
    /* non-fatal */
  }
}

export async function persistQuestionAnswer(opts: {
  questionId: string;
  fanId: string;
  optionKey: string;
  actionId?: string;
  roomId?: string;
}): Promise<void> {
  const pool = await poolOrNull();
  if (!pool) return;
  try {
    await pool.query(
      `INSERT INTO question_answers (question_id, fan_id, option_key, action_id, room_id)
       VALUES ($1,$2,$3,$4,$5)
       ON CONFLICT (question_id, fan_id) DO NOTHING`,
      [opts.questionId, opts.fanId, opts.optionKey, opts.actionId ?? null, opts.roomId ?? null],
    );
  } catch {
    /* non-fatal */
  }
}

export async function persistRewardGrant(opts: {
  questionId: string;
  fanId: string;
  result: string;
  momentId?: string;
}): Promise<boolean> {
  const pool = await poolOrNull();
  if (!pool) return true; // memory path — caller uses rewardedCalls set
  try {
    const res = await pool.query(
      `INSERT INTO question_reward_grants (question_id, fan_id, result, moment_id)
       VALUES ($1,$2,$3,$4)
       ON CONFLICT (question_id, fan_id) DO NOTHING
       RETURNING question_id`,
      [opts.questionId, opts.fanId, opts.result, opts.momentId ?? null],
    );
    return (res.rowCount ?? 0) > 0;
  } catch {
    return true;
  }
}
