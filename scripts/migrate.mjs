import { readFile } from 'node:fs/promises';
import { readdirSync } from 'node:fs';
import path from 'node:path';
import pg from 'pg';
import { applyMigration, migrationChecksum } from './migration-lib.mjs';

const root = process.cwd();
const migrationsDir = path.join(root, 'db', 'migrations');
const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl) {
  throw new Error('DATABASE_URL is required');
}

const client = new pg.Client({ connectionString: databaseUrl });

await client.connect();
try {
  await client.query(`SELECT pg_advisory_lock(hashtext('accounting-os-schema-migrations'))`);
  await client.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version text PRIMARY KEY,
      checksum text NOT NULL,
      applied_at timestamptz NOT NULL DEFAULT now()
    )
  `);

  const files = readdirSync(migrationsDir)
    .filter((file) => /^\d+_.+\.sql$/.test(file))
    .sort();

  for (const file of files) {
    const version = file.replace(/\.sql$/, '');
    const fullPath = path.join(migrationsDir, file);
    const sql = await readFile(fullPath, 'utf8');
    const hash = migrationChecksum(sql);

    const existing = await client.query(
      `SELECT checksum FROM schema_migrations WHERE version=$1`,
      [version]
    );
    if (existing.rows[0]) {
      if (existing.rows[0].checksum !== hash) {
        throw new Error(`migration checksum mismatch: ${version}`);
      }
      console.log(`skip ${version}`);
      continue;
    }

    console.log(`apply ${version}`);
    await applyMigration(client, version, sql, hash);
  }
} finally {
  await client.query(`SELECT pg_advisory_unlock(hashtext('accounting-os-schema-migrations'))`).catch(() => {});
  await client.end();
}
