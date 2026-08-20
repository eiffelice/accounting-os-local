import { readFile } from 'node:fs/promises';
import { readdirSync } from 'node:fs';
import path from 'node:path';
import pg from 'pg';

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error('DATABASE_URL is required');

const client = new pg.Client({ connectionString: databaseUrl });
await client.connect();
try {
  const files = [
    ...readdirSync(path.join(process.cwd(), 'db', 'tests'))
      .filter((file) => file.endsWith('.sql'))
      .map((file) => path.join('db', 'tests', file)),
    path.join('db', 'qa_v0_3_tax.sql'),
  ].sort();

  for (const file of files) {
    console.log(`test ${file}`);
    await client.query(await readFile(path.join(process.cwd(), file), 'utf8'));
  }
} finally {
  await client.end();
}
