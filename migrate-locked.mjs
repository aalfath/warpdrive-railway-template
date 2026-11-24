// Runs upstream's migrations (dist/migrate.mjs) under a Postgres advisory lock, so two
// overlapping Railway deploys never migrate at the same time. Polls pg_try_advisory_lock
// instead of blocking, and waits for the database on a cold first deploy.
import { spawnSync } from "node:child_process";
import pg from "pg";

const LOCK = 7_305_800_158;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let client;
for (let i = 1; ; i++) {
  client = new pg.Client({ connectionString: process.env.DATABASE_URL });
  try {
    await client.connect();
    break;
  } catch (e) {
    await client.end().catch(() => {});
    if (i >= 60) {
      console.error(`database not reachable after ${i} tries: ${e.message}`);
      process.exit(1);
    }
    console.warn(`waiting for the database (${i}/60): ${e.message}`);
    await sleep(3000);
  }
}

for (let i = 1; ; i++) {
  const { rows } = await client.query("SELECT pg_try_advisory_lock($1) AS ok", [LOCK]);
  if (rows[0].ok) break;
  if (i >= 200) {
    console.error("another deploy held the migration lock for 10 minutes");
    process.exit(1);
  }
  if (i === 1) console.warn("another deploy is migrating; waiting for its lock");
  await sleep(3000);
}

const r = spawnSync(process.execPath, ["dist/migrate.mjs"], { stdio: "inherit" });
await client.query("SELECT pg_advisory_unlock($1)", [LOCK]).catch(() => {});
await client.end().catch(() => {});
process.exit(r.status ?? 1);
