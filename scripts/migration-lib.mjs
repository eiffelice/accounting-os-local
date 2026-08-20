import { createHash } from 'node:crypto';

export function migrationChecksum(sql) {
  return createHash('sha256').update(sql).digest('hex');
}

function hasOwnTransaction(sql) {
  return /^\s*BEGIN\s*;/i.test(sql) && /COMMIT\s*;\s*$/i.test(sql);
}

export function stripOuterTransaction(sql) {
  if (!hasOwnTransaction(sql)) return sql;
  return sql
    .replace(/^\s*BEGIN\s*;/i, '')
    .replace(/COMMIT\s*;\s*$/i, '');
}

export async function applyMigration(client, version, sql, hash = migrationChecksum(sql)) {
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
