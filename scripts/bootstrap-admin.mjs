import { pbkdf2Sync, randomBytes, createHash } from 'node:crypto';
import pg from 'pg';

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error('DATABASE_URL is required');

const email = process.env.INITIAL_ADMIN_EMAIL ?? 'owner@local.accounting';
const displayName = process.env.INITIAL_ADMIN_DISPLAY_NAME ?? 'Local Owner';
const password = randomBytes(18).toString('base64url');
const mcpToken = randomBytes(32).toString('base64url');

function passwordHash(value) {
  const salt = randomBytes(16);
  const digest = pbkdf2Sync(value, salt, 310000, 32, 'sha256');
  return `pbkdf2_sha256$310000$${salt.toString('base64')}$${digest.toString('base64')}`;
}

function tokenHash(value) {
  return createHash('sha256').update(value).digest('hex');
}

const client = new pg.Client({ connectionString: databaseUrl });
await client.connect();
try {
  await client.query('BEGIN');
  const count = await client.query(
    `SELECT count(*)::int AS n
     FROM app_users
     WHERE is_active=true AND password_hash IS NOT NULL`
  );
  if (count.rows[0].n > 0) {
    await client.query('COMMIT');
    console.log('Admin bootstrap skipped: at least one user already exists.');
    process.exit(0);
  }

  const existing = await client.query(
    `SELECT id FROM app_users WHERE lower(email)=lower($1) FOR UPDATE`,
    [email]
  );
  const user = existing.rows[0]
    ? await client.query(
        `UPDATE app_users
         SET display_name=$2, password_hash=$3, must_change_password=true,
             is_active=true, failed_login_count=0, locked_until=NULL
         WHERE id=$1
         RETURNING id`,
        [existing.rows[0].id, displayName, passwordHash(password)]
      )
    : await client.query(
        `INSERT INTO app_users(email, display_name, password_hash, must_change_password)
         VALUES($1,$2,$3,true)
         RETURNING id`,
        [email, displayName, passwordHash(password)]
      );

  const mcp = await client.query(
    `INSERT INTO mcp_identities(user_id, name, token_hash, scopes)
     VALUES($1,'Local read/tax/draft MCP', $2, ARRAY['read','tax:calculate','draft:create'])
     RETURNING id`,
    [user.rows[0].id, tokenHash(mcpToken)]
  );

  await client.query(
    `INSERT INTO audit_events(actor_user_id, event_type, resource_type, resource_id, payload)
     VALUES($1::uuid,'INITIAL_ADMIN_BOOTSTRAPPED','app_user',$1::text,'{}'::jsonb)`,
    [user.rows[0].id]
  );
  await client.query('COMMIT');

  console.log('');
  console.log('Initial admin created. Store this once, then change it after login.');
  console.log(`Email: ${email}`);
  console.log(`Initial password: ${password}`);
  console.log('');
  console.log('MCP identity created. Add these to your MCP env only if needed:');
  console.log(`ACCOUNTING_MCP_IDENTITY_ID=${mcp.rows[0].id}`);
  console.log(`ACCOUNTING_MCP_TOKEN=${mcpToken}`);
} catch (error) {
  await client.query('ROLLBACK');
  throw error;
} finally {
  await client.end();
}
