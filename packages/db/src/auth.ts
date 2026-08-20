import { createHash, randomBytes, timingSafeEqual, pbkdf2Sync } from 'node:crypto';
import { pool, type LocalUser } from './base.ts';

export function hashSessionToken(token: string) {
  return createHash('sha256').update(token).digest('hex');
}

export function verifyPassword(password: string, encoded: string | null) {
  if (!encoded || password.length > 1024) return false;
  try {
    const parts = encoded.split('$');
    if (parts.length !== 4) return false;
    const [algo, iterationsText, saltB64, hashB64] = parts;
    if (algo !== 'pbkdf2_sha256') return false;
    const iterations = Number(iterationsText);
    if (!Number.isSafeInteger(iterations) || iterations < 100000 || iterations > 2_000_000) return false;
    const salt = Buffer.from(saltB64, 'base64');
    const expected = Buffer.from(hashB64, 'base64');
    if (salt.length !== 16 || expected.length !== 32) return false;
    const actual = pbkdf2Sync(password, salt, iterations, expected.length, 'sha256');
    return timingSafeEqual(expected, actual);
  } catch {
    return false;
  }
}

export function makePasswordHash(password: string) {
  if (password.length < 12 || password.length > 1024) {
    throw new Error('password must be 12 to 1024 characters');
  }
  const iterations = 310000;
  const salt = randomBytes(16);
  const digest = pbkdf2Sync(password, salt, iterations, 32, 'sha256');
  return `pbkdf2_sha256$${iterations}$${salt.toString('base64')}$${digest.toString('base64')}`;
}

export async function changePassword(userId: string, currentPassword: string, newPassword: string) {
  const { rows } = await pool.query(
    `SELECT password_hash FROM app_users WHERE id=$1 AND is_active=true`,
    [userId]
  );
  if (!rows[0] || !verifyPassword(currentPassword, rows[0].password_hash)) {
    throw new Error('current password is incorrect');
  }
  const newHash = makePasswordHash(newPassword);
  await pool.query(
    `UPDATE app_users SET password_hash=$2, must_change_password=false WHERE id=$1`,
    [userId, newHash]
  );
  await pool.query(`UPDATE user_sessions SET revoked_at=now() WHERE user_id=$1 AND revoked_at IS NULL`, [userId]);
  await pool.query(
    `INSERT INTO audit_events(actor_user_id, event_type, resource_type, resource_id, payload)
     VALUES($1::uuid,'PASSWORD_CHANGED','app_user',$1::text,'{}'::jsonb)`,
    [userId]
  );
}

export async function recordLoginFailure(email: string) {
  await pool.query(
    `UPDATE app_users
     SET failed_login_count = failed_login_count + 1,
         locked_until = CASE
           WHEN failed_login_count + 1 >= 5 THEN now() + interval '15 minutes'
           ELSE locked_until
         END
     WHERE lower(email)=lower($1)`,
    [email]
  );
}

export async function recordLoginSuccess(userId: string) {
  await pool.query(
    `UPDATE app_users
     SET failed_login_count=0, locked_until=NULL
     WHERE id=$1`,
    [userId]
  );
}

export async function getActorByEmail(email: string) {
  const { rows } = await pool.query<LocalUser>(
    `SELECT id, email, display_name, is_active, must_change_password
     FROM app_users
     WHERE email = $1 AND is_active = true`,
    [email]
  );
  return rows[0] ?? null;
}

export async function getUserForLogin(email: string) {
  const { rows } = await pool.query(
    `SELECT id, email, display_name, is_active, password_hash, must_change_password,
            locked_until, locked_until IS NOT NULL AND locked_until > now() AS is_locked
     FROM app_users WHERE lower(email)=lower($1) AND is_active=true`,
    [email]
  );
  return rows[0] ?? null;
}

export async function createSession(userId: string, ttlHours = 12) {
  const token = randomBytes(32).toString('base64url');
  const tokenHash = hashSessionToken(token);
  const { rows } = await pool.query(
    `INSERT INTO user_sessions(user_id, token_hash, expires_at)
     VALUES ($1,$2,now() + ($3::text || ' hours')::interval)
     RETURNING expires_at`,
    [userId, tokenHash, ttlHours]
  );
  return { token, expiresAt: rows[0].expires_at as Date };
}

export async function getSessionUser(token: string | undefined) {
  if (!token) return null;
  const { rows } = await pool.query<LocalUser>(
    `SELECT u.id, u.email, u.display_name, u.is_active, u.must_change_password
     FROM user_sessions s
     JOIN app_users u ON u.id=s.user_id
     WHERE s.token_hash=$1
       AND s.revoked_at IS NULL
       AND s.expires_at > now()
       AND u.is_active=true`,
    [hashSessionToken(token)]
  );
  if (rows[0]) {
    await pool.query(
      `UPDATE user_sessions SET last_seen_at=now()
       WHERE token_hash=$1`,
      [hashSessionToken(token)]
    );
  }
  return rows[0] ?? null;
}

export async function revokeSession(token: string) {
  await pool.query(
    `UPDATE user_sessions SET revoked_at=now()
     WHERE token_hash=$1 AND revoked_at IS NULL`,
    [hashSessionToken(token)]
  );
}

export async function getMcpIdentity(identityId: string, token: string) {
  const { rows } = await pool.query<{
    id: string;
    mcp_identity_id: string;
    user_id: string;
    email: string;
    display_name: string;
    scopes: string[];
  }>(
    `SELECT u.id, m.id AS mcp_identity_id, m.user_id, u.email, u.display_name, m.scopes
     FROM mcp_identities m
     JOIN app_users u ON u.id=m.user_id
     WHERE m.id=$1
       AND m.token_hash=$2
       AND m.is_active=true
       AND u.is_active=true
       AND u.must_change_password=false`,
    [identityId, hashSessionToken(token)]
  );
  if (rows[0]) {
    await pool.query(`UPDATE mcp_identities SET last_used_at=now() WHERE id=$1`, [identityId]);
  }
  return rows[0] ?? null;
}

export function assertMcpScope(scopes: string[], required: string) {
  if (scopes.includes('tax_submit') || scopes.includes('payment_execute')) {
    throw new Error('forbidden MCP scope configured');
  }
  if (!scopes.includes(required)) {
    throw new Error(`MCP scope required: ${required}`);
  }
}
