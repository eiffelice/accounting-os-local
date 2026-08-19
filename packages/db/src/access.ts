import { pool } from './base.js';
import { makePasswordHash } from './auth.js';

export async function assertCompanyAccess(
  actorId: string,
  companyId: string,
  capability: 'read' | 'create_draft' | 'approve' | 'post'
) {
  const column = {
    read: 'can_read',
    create_draft: 'can_create_draft',
    approve: 'can_approve',
    post: 'can_post',
  }[capability];

  const { rows } = await pool.query(
    `SELECT role, approval_limit, ${column} AS allowed
     FROM company_memberships
     WHERE user_id = $1
       AND company_id = $2
       AND (expires_at IS NULL OR expires_at > now())`,
    [actorId, companyId]
  );

  if (!rows[0]?.allowed) {
    throw new Error(`ACCESS_DENIED: ${capability} on company`);
  }
  return rows[0];
}

export async function getMembership(actorId: string, companyId: string) {
  const { rows } = await pool.query(
    `SELECT role, can_read, can_create_draft, can_approve, can_post,
            approval_limit, expires_at
     FROM company_memberships
     WHERE user_id=$1 AND company_id=$2`,
    [actorId, companyId]
  );
  return rows[0] ?? null;
}

export async function createEmployeeMembership(
  actorId: string,
  companyId: string,
  input: {
    email: string;
    displayName: string;
    temporaryPassword: string;
    role: 'CFO' | 'ACCOUNTING_MANAGER' | 'ACCOUNTANT' | 'STAFF' | 'AUDITOR';
  }
) {
  const mine = await getMembership(actorId, companyId);
  if (!mine || mine.role !== 'OWNER') {
    throw new Error('ACCESS_DENIED: only OWNER can add employees in v0.2');
  }

  const email = input.email.trim().toLowerCase();
  if (!email.includes('@') || email.length > 254) throw new Error('invalid email');
  if (input.displayName.trim().length < 2) throw new Error('display name is too short');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const existing = await client.query(
      `SELECT id FROM app_users WHERE lower(email)=lower($1)`,
      [email]
    );

    let userId: string;
    if (existing.rows[0]) {
      userId = existing.rows[0].id;
    } else {
      const hash = makePasswordHash(input.temporaryPassword);
      const created = await client.query(
        `INSERT INTO app_users(email, display_name, password_hash, must_change_password)
         VALUES($1,$2,$3,true)
         RETURNING id`,
        [email, input.displayName.trim(), hash]
      );
      userId = created.rows[0].id;
    }

    const presets = {
      CFO: [true, true, true, true, null],
      ACCOUNTING_MANAGER: [true, true, true, true, 5000000],
      ACCOUNTANT: [true, true, false, false, 50000],
      STAFF: [true, true, false, false, 0],
      AUDITOR: [true, false, false, false, 0],
    } as const;
    const [canRead, canDraft, canApprove, canPost, limit] = presets[input.role];

    await client.query(
      `INSERT INTO company_memberships(
         user_id, company_id, role, can_read, can_create_draft, can_approve, can_post, approval_limit
       ) VALUES($1,$2,$3,$4,$5,$6,$7,$8)
       ON CONFLICT (user_id, company_id) DO NOTHING`,
      [userId, companyId, input.role, canRead, canDraft, canApprove, canPost, limit]
    );

    const membership = await client.query(
      `SELECT 1 FROM company_memberships WHERE user_id=$1 AND company_id=$2`,
      [userId, companyId]
    );
    if (!membership.rows[0]) throw new Error('failed to create employee membership');

    await client.query(
      `INSERT INTO audit_events(company_id, actor_user_id, event_type, resource_type, resource_id, payload)
       VALUES($1,$2,'EMPLOYEE_MEMBERSHIP_CREATED','company_membership',$3,$4::jsonb)`,
      [
        companyId,
        actorId,
        userId,
        JSON.stringify({ email, displayName: input.displayName.trim(), role: input.role }),
      ]
    );

    await client.query('COMMIT');
    return userId;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

export async function listMemberships(companyId: string) {
  const { rows } = await pool.query(
    `SELECT u.id AS user_id, u.email, u.display_name, u.is_active,
            m.role, m.can_read, m.can_create_draft, m.can_approve, m.can_post,
            m.approval_limit, m.expires_at
     FROM company_memberships m
     JOIN app_users u ON u.id=m.user_id
     WHERE m.company_id=$1
     ORDER BY u.display_name`,
    [companyId]
  );
  return rows;
}

export async function updateMembership(
  actorId: string,
  companyId: string,
  userId: string,
  input: {
    role: string;
    canRead: boolean;
    canCreateDraft: boolean;
    canApprove: boolean;
    canPost: boolean;
    approvalLimit: number | null;
  }
) {
  const actorMembership = await getMembership(actorId, companyId);
  if (!actorMembership || actorMembership.role !== 'OWNER') {
    throw new Error('ACCESS_DENIED: only OWNER can change employee permissions in v0.2');
  }

  const targetMembership = await getMembership(userId, companyId);
  if (!targetMembership) throw new Error('target membership not found');

  if (targetMembership.role === 'OWNER' && input.role !== 'OWNER') {
    const { rows } = await pool.query(
      `SELECT count(*)::int AS count
       FROM company_memberships
       WHERE company_id=$1 AND role='OWNER' AND user_id<>$2`,
      [companyId, userId]
    );
    if (rows[0].count < 1) {
      throw new Error('cannot remove the final OWNER from a company');
    }
  }

  await pool.query(
    `UPDATE company_memberships
     SET role=$3,
         can_read=$4,
         can_create_draft=$5,
         can_approve=$6,
         can_post=$7,
         approval_limit=$8
     WHERE company_id=$1 AND user_id=$2`,
    [
      companyId,
      userId,
      input.role,
      input.canRead,
      input.canCreateDraft,
      input.canApprove,
      input.canPost,
      input.approvalLimit,
    ]
  );

  await pool.query(
    `INSERT INTO audit_events(company_id, actor_user_id, event_type, resource_type, resource_id, payload)
     VALUES ($1,$2,'MEMBERSHIP_UPDATED','company_membership',$3,$4::jsonb)`,
    [
      companyId,
      actorId,
      userId,
      JSON.stringify({
        role: input.role,
        canRead: input.canRead,
        canCreateDraft: input.canCreateDraft,
        canApprove: input.canApprove,
        canPost: input.canPost,
        approvalLimit: input.approvalLimit,
      }),
    ]
  );
}
