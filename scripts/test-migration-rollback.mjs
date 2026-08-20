import pg from 'pg';
import { applyMigration } from './migration-lib.mjs';

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error('DATABASE_URL is required');

const client = new pg.Client({ connectionString: databaseUrl });
await client.connect();
try {
  let failed = false;
  try {
    await applyMigration(
      client,
      '__qa_forced_rollback__',
      'CREATE TABLE migration_rollback_probe(id integer); SELECT * FROM migration_forced_failure;'
    );
  } catch {
    failed = true;
  }
  if (!failed) throw new Error('forced migration failure did not fail');

  const { rows } = await client.query(
    `SELECT to_regclass('public.migration_rollback_probe') IS NULL AS table_rolled_back,
            NOT EXISTS(
              SELECT 1 FROM schema_migrations WHERE version='__qa_forced_rollback__'
            ) AS version_rolled_back`
  );
  if (!rows[0]?.table_rolled_back || !rows[0]?.version_rolled_back) {
    throw new Error('migration transaction did not fully roll back');
  }
  console.log('PASS: migration failure rolled back schema and version record');
} finally {
  await client.end();
}
