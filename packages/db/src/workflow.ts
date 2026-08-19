import { pool } from './base.js';
import { assertCompanyAccess, getMembership } from './access.js';

export async function listApprovals(companyId: string, status?: 'PENDING' | 'APPROVED') {
  const params: unknown[] = [companyId];
  let filter = `AND ar.status IN ('PENDING','APPROVED')`;
  if (status) {
    params.push(status);
    filter = `AND ar.status=$2`;
  }
  const { rows } = await pool.query(
    `SELECT ar.id, ar.action, ar.amount, ar.status, ar.requested_at,
            ar.resource_id, je.memo, je.txn_date, je.source_type, je.status AS journal_status,
            u.display_name AS requested_by_name
     FROM approval_requests ar
     LEFT JOIN journal_entries je
       ON ar.resource_type='journal_entry' AND je.id=ar.resource_id
     JOIN app_users u ON u.id=ar.requested_by
     WHERE ar.company_id=$1 ${filter}
     ORDER BY CASE WHEN ar.status='PENDING' THEN 0 ELSE 1 END, ar.requested_at DESC`,
    params
  );
  return rows;
}

export async function approveRequest(actorId: string, requestId: string, reason: string) {
  await pool.query(`SELECT approve_post_request($1,$2,$3)`, [requestId, actorId, reason]);
}

export async function rejectRequest(actorId: string, requestId: string, reason: string) {
  await pool.query(`SELECT reject_post_request($1,$2,$3)`, [requestId, actorId, reason]);
}

export async function postApprovedJournal(actorId: string, entryId: string) {
  const { rows } = await pool.query(
    `SELECT post_approved_journal($1,$2) AS entry_no`,
    [entryId, actorId]
  );
  return rows[0]?.entry_no as string;
}

export async function listContacts(companyId: string) {
  const { rows } = await pool.query(
    `SELECT id, contact_type, code, display_name, legal_name, tax_id, email, phone, is_active
     FROM contacts
     WHERE company_id=$1
     ORDER BY display_name`,
    [companyId]
  );
  return rows;
}

export async function createContact(
  actorId: string,
  companyId: string,
  input: {
    contactType: 'CUSTOMER' | 'VENDOR' | 'BOTH';
    displayName: string;
    legalName?: string;
    taxId?: string;
    email?: string;
    phone?: string;
  }
) {
  await assertCompanyAccess(actorId, companyId, 'create_draft');
  const { rows } = await pool.query(
    `INSERT INTO contacts(company_id, contact_type, display_name, legal_name, tax_id, email, phone, created_by)
     VALUES($1,$2,$3,$4,$5,$6,$7,$8)
     RETURNING id`,
    [
      companyId, input.contactType, input.displayName, input.legalName || null,
      input.taxId || null, input.email || null, input.phone || null, actorId
    ]
  );

  await pool.query(
    `INSERT INTO audit_events(company_id, actor_user_id, event_type, resource_type, resource_id, payload)
     VALUES($1,$2,'CONTACT_CREATED','contact',$3,$4::jsonb)`,
    [companyId, actorId, rows[0].id, JSON.stringify({ contactType: input.contactType, displayName: input.displayName })]
  );
  return rows[0].id as string;
}

export async function listFiscalPeriods(companyId: string) {
  const { rows } = await pool.query(
    `SELECT id, period_key, start_date, end_date, status, closed_at, close_reason,
            reopened_at, reopen_reason
     FROM fiscal_periods
     WHERE company_id=$1
     ORDER BY start_date DESC`,
    [companyId]
  );
  return rows;
}

export async function closeFiscalPeriod(actorId: string, companyId: string, periodId: string, reason: string) {
  const membership = await assertCompanyAccess(actorId, companyId, 'approve');
  if (!['OWNER','CFO','ACCOUNTING_MANAGER'].includes(membership.role)) {
    throw new Error('ACCESS_DENIED: role cannot close period');
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const period = await client.query(
      `SELECT * FROM fiscal_periods WHERE id=$1 AND company_id=$2 FOR UPDATE`,
      [periodId, companyId]
    );
    if (!period.rows[0] || period.rows[0].status !== 'OPEN') {
      throw new Error('period is not OPEN');
    }

    const pending = await client.query(
      `SELECT count(*)::int AS count
       FROM journal_entries
       WHERE company_id=$1
         AND status='DRAFT'
         AND txn_date BETWEEN $2 AND $3`,
      [companyId, period.rows[0].start_date, period.rows[0].end_date]
    );
    if (pending.rows[0].count > 0) {
      throw new Error(`cannot close period: ${pending.rows[0].count} draft journal(s) remain`);
    }

    await client.query(
      `UPDATE fiscal_periods
       SET status='CLOSED', closed_at=now(), closed_by=$3, close_reason=$4
       WHERE id=$1 AND company_id=$2`,
      [periodId, companyId, actorId, reason]
    );

    await client.query(
      `INSERT INTO audit_events(company_id, actor_user_id, event_type, resource_type, resource_id, payload)
       VALUES($1,$2,'FISCAL_PERIOD_CLOSED','fiscal_period',$3,$4::jsonb)`,
      [companyId, actorId, periodId, JSON.stringify({ reason })]
    );

    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

export async function reopenFiscalPeriod(actorId: string, companyId: string, periodId: string, reason: string) {
  const membership = await getMembership(actorId, companyId);
  if (!membership || !['OWNER','CFO'].includes(membership.role)) {
    throw new Error('ACCESS_DENIED: only OWNER/CFO can reopen period in v0.2');
  }

  await pool.query(
    `UPDATE fiscal_periods
     SET status='OPEN', reopened_at=now(), reopened_by=$3, reopen_reason=$4
     WHERE id=$1 AND company_id=$2 AND status='CLOSED'`,
    [periodId, companyId, actorId, reason]
  );
  await pool.query(
    `INSERT INTO audit_events(company_id, actor_user_id, event_type, resource_type, resource_id, payload)
     VALUES($1,$2,'FISCAL_PERIOD_REOPENED','fiscal_period',$3,$4::jsonb)`,
    [companyId, actorId, periodId, JSON.stringify({ reason })]
  );
}
