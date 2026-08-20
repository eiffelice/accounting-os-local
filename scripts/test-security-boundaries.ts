import { randomBytes, randomUUID } from 'node:crypto';
import {
  assertCompanyAccess,
  assertMcpScope,
  getMembership,
  getMcpIdentity,
  hashSessionToken,
  makePasswordHash,
  pool,
  verifyPassword,
} from '../packages/db/src/index.ts';

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error('DATABASE_URL is required');

async function main() {
const password = randomBytes(18).toString('base64url');
const encoded = makePasswordHash(password);
if (!verifyPassword(password, encoded) || verifyPassword('wrong-password', encoded)) {
  throw new Error('password verification invariant failed');
}
if (verifyPassword('x', 'pbkdf2_sha256$bad$not-base64$not-base64')) {
  throw new Error('malformed password hash was accepted');
}
for (const scopes of [['read', 'tax_submit'], ['payment_execute']]) {
  let rejected = false;
  try { assertMcpScope(scopes, scopes[0]); } catch { rejected = true; }
  if (!rejected) throw new Error('forbidden MCP scope was accepted');
}

const userId = randomUUID();
const companyId = randomUUID();
const identityId = randomUUID();
const token = randomBytes(32).toString('base64url');
try {
  await pool.query(
    `INSERT INTO app_users(id,email,display_name,password_hash,must_change_password)
     VALUES($1,$2,'Security QA',$3,true)`,
    [userId, `security-${userId}@local.invalid`, encoded]
  );

  await pool.query(
    `INSERT INTO companies(id,code,legal_name,display_name)
     VALUES($1,$2,'Security QA','Security QA')`,
    [companyId, `SEC-${companyId.slice(0, 8)}`]
  );
  await pool.query(
    `INSERT INTO company_memberships(
       user_id,company_id,role,can_read,can_create_draft,can_approve,can_post
     ) VALUES($1,$2,'STAFF',true,false,false,false)`,
    [userId, companyId]
  );
  await pool.query(
    `UPDATE company_memberships SET expires_at=now()-interval '1 minute'
     WHERE user_id=$1 AND company_id=$2`,
    [userId, companyId]
  );
  if (await getMembership(userId, companyId)) {
    throw new Error('expired company membership was accepted');
  }
  await pool.query(
    `UPDATE company_memberships SET expires_at=NULL
     WHERE user_id=$1 AND company_id=$2`,
    [userId, companyId]
  );
  await pool.query(
    `INSERT INTO mcp_identities(id,user_id,name,token_hash,scopes)
     VALUES($1,$2,'Security QA',$3,ARRAY['read','draft:create'])`,
    [identityId, userId, hashSessionToken(token)]
  );

  if (await getMcpIdentity(identityId, token)) {
    throw new Error('MCP identity was active before temporary password change');
  }
  await pool.query(`UPDATE app_users SET must_change_password=false WHERE id=$1`, [userId]);
  const identity = await getMcpIdentity(identityId, token);
  if (!identity) throw new Error('valid MCP identity was rejected after password change');
  assertMcpScope(identity.scopes, 'draft:create');

  let employeeDenied = false;
  try { await assertCompanyAccess(identity.id, companyId, 'create_draft'); } catch { employeeDenied = true; }
  if (!employeeDenied) throw new Error('MCP scope exceeded employee company permission');
} finally {
  await pool.query(`DELETE FROM mcp_identities WHERE id=$1`, [identityId]).catch(() => {});
  await pool.query(`DELETE FROM company_memberships WHERE user_id=$1 AND company_id=$2`, [userId, companyId]).catch(() => {});
  await pool.query(`DELETE FROM companies WHERE id=$1`, [companyId]).catch(() => {});
  await pool.query(`DELETE FROM app_users WHERE id=$1`, [userId]).catch(() => {});
  await pool.end();
}

console.log('PASS: password, MCP identity, scope, and employee permission boundaries');
}

void main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
