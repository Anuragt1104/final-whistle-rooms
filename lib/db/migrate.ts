import fs from "fs/promises";
import path from "path";
import { getPool } from "./pool";

export async function runMigrations() {
  const pool = await getPool();
  await pool.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name text PRIMARY KEY,
      applied_at timestamptz NOT NULL DEFAULT now()
    )
  `);
  const directory = path.join(process.cwd(), "migrations");
  const files = (await fs.readdir(directory)).filter((name) => name.endsWith(".sql")).sort();
  for (const name of files) {
    const exists = await pool.query("SELECT 1 FROM schema_migrations WHERE name = $1", [name]);
    if (exists.rowCount) continue;
    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      await client.query(await fs.readFile(path.join(directory, name), "utf8"));
      await client.query("INSERT INTO schema_migrations(name) VALUES($1)", [name]);
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }
}

if (process.argv[1]?.endsWith("migrate.ts")) {
  runMigrations().then(() => process.exit(0), (error) => {
    console.error(error);
    process.exit(1);
  });
}
