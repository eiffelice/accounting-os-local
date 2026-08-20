import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { readdirSync } from 'node:fs';
import path from 'node:path';
import pg from 'pg';

const root = process.cwd();
const migrationsDir = path.join(root, 'db', 'migrations');
const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl) {
  throw new Error('DATABASE_URL is required');
}

const client = new pg.Client({ connectionString: databaseUrl });

function checksum(sql) {
  return createHash('sha256').update(sql).digest('hex');
}

function hasOwnTransaction(sql) {
  return /^\s*BEGIN\s*;/i.test(sql) && /COMMIT\s*;\s*$/i.test(sql);
}

function stripOuterTransaction(sql) {
  if (!hasOwnTransaction(sql)) return sql;
  return sql
    .replace(/^\s*BEGIN\s*;/i, '')
    .replace(/COMMIT\s*;\s*$/i, '');
}

await client.connect();
try {
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
    const hash = checksum(sql);

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
    await client.query('BEGIN');
    try {
      await client.query(stripOuterTransaction(sql));
      await client.query(
        `INSERT INTO schema_migrations(version, checksum) VALUES($1,$2)`,
        [version, hash]
      );
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    }
  }
} finally {
  await client.end();
}
