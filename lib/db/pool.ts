import type { Pool } from "pg";

let pool: Pool | undefined;

export async function getPool(): Promise<Pool> {
  if (!process.env.DATABASE_URL) throw new Error("DATABASE_URL is required");
  if (!pool) {
    const pg = await import("pg");
    pool = new pg.Pool({
      connectionString: process.env.DATABASE_URL,
      ssl: process.env.PGSSL === "disable" ? false : { rejectUnauthorized: false },
      max: Number(process.env.PG_POOL_MAX ?? 10),
    });
  }
  return pool;
}

export async function closePoolForTests() {
  await pool?.end();
  pool = undefined;
}
