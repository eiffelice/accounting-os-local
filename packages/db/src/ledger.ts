import { createHash } from 'node:crypto';
import { pool } from './base.ts';
import { assertCompanyAccess } from './access.ts';

export async function trialBalance(companyId: string) {
  const { rows } = await pool.query(
    `SELECT a.code, a.name_th, a.account_type,
            COALESCE(sum(CASE WHEN je.status IN ('POSTED','REVERSED') THEN jl.debit ELSE 0 END),0)::text AS debit,
            COALESCE(sum(CASE WHEN je.status IN ('POSTED','REVERSED') THEN jl.credit ELSE 0 END),0)::text AS credit,
            (
              COALESCE(sum(CASE WHEN je.status IN ('POSTED','REVERSED') THEN jl.debit ELSE 0 END),0)
              -
              COALESCE(sum(CASE WHEN je.status IN ('POSTED','REVERSED') THEN jl.credit ELSE 0 END),0)
            )::text AS balance
     FROM chart_of_accounts a
     LEFT JOIN journal_lines jl ON jl.account_id=a.id
     LEFT JOIN journal_entries je ON je.id=jl.journal_entry_id
     WHERE a.company_id=$1
     GROUP BY a.id, a.code, a.name_th, a.account_type
     ORDER BY a.code`,
    [companyId]
  );
  return rows;
}

export async function dashboardSummary(companyId: string) {
  const { rows } = await pool.query(
    `SELECT
       COALESCE(sum(CASE WHEN a.account_type='REVENUE' THEN jl.credit-jl.debit ELSE 0 END),0)::text AS revenue,
       COALESCE(sum(CASE WHEN a.account_type='EXPENSE' THEN jl.debit-jl.credit ELSE 0 END),0)::text AS expense,
       COALESCE(sum(CASE WHEN a.account_type='ASSET' AND a.system_key IN ('BANK','CASH') THEN jl.debit-jl.credit ELSE 0 END),0)::text AS cash_balance,
       (
         COALESCE(sum(CASE WHEN a.account_type='REVENUE' THEN jl.credit-jl.debit ELSE 0 END),0)
         -
         COALESCE(sum(CASE WHEN a.account_type='EXPENSE' THEN jl.debit-jl.credit ELSE 0 END),0)
       )::text AS profit
     FROM journal_entries je
     JOIN journal_lines jl ON jl.journal_entry_id=je.id
     JOIN chart_of_accounts a ON a.id=jl.account_id
     WHERE je.company_id=$1 AND je.status IN ('POSTED','REVERSED')`,
    [companyId]
  );
  const r = rows[0] ?? { revenue: '0', expense: '0', cash_balance: '0' };
  return r;
}

export async function recentJournals(companyId: string, limit = 10) {
  const { rows } = await pool.query(
    `SELECT id, entry_no, txn_date, status, source_type, memo, posted_at, created_by
     FROM journal_entries
     WHERE company_id=$1
     ORDER BY txn_date DESC, created_at DESC
     LIMIT $2`,
    [companyId, limit]
  );
  return rows;
}

async function createDraft(
  input: {
    actorId: string;
    companyId: string;
    financialAccountId: string;
    accountCode: string;
    amount: string;
    txnDate: string;
    description: string;
    idempotencyKey: string;
    sourceType: string;
    kind: 'EXPENSE' | 'INCOME';
  }
) {
  if (!/^\d{1,15}(?:\.\d{1,2})?$/.test(input.amount) || Number(input.amount) <= 0) {
    throw new Error('amount must be a positive decimal string with max 2 decimals');
  }
  await assertCompanyAccess(input.actorId, input.companyId, 'create_draft');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const payloadHash = createHash('sha256')
      .update(JSON.stringify({
        companyId: input.companyId,
        financialAccountId: input.financialAccountId,
        accountCode: input.accountCode,
        amount: input.amount,
        txnDate: input.txnDate,
        description: input.description,
        kind: input.kind,
      }))
      .digest('hex');

    const operation = input.kind === 'EXPENSE' ? 'expense.create_draft' : 'income.create_draft';
    const existing = await client.query(
      `SELECT payload_hash, resource_id
       FROM idempotency_registry
       WHERE company_id=$1 AND operation=$2 AND idempotency_key=$3`,
      [input.companyId, operation, input.idempotencyKey]
    );

    if (existing.rows[0]) {
      if (existing.rows[0].payload_hash !== payloadHash) {
        throw new Error('IDEMPOTENCY_CONFLICT: same key with different payload');
      }
      await client.query('COMMIT');
      return { id: existing.rows[0].resource_id, replayed: true };
    }

    const fa = await client.query(
      `SELECT id, gl_account_id
       FROM financial_accounts
       WHERE id=$1 AND company_id=$2 AND is_active=true`,
      [input.financialAccountId, input.companyId]
    );
    if (!fa.rows[0]) throw new Error('financial account not found in company');

    const target = await client.query(
      `SELECT id
       FROM chart_of_accounts
       WHERE company_id=$1 AND code=$2 AND account_type=$3 AND is_active=true`,
      [input.companyId, input.accountCode, input.kind === 'EXPENSE' ? 'EXPENSE' : 'REVENUE']
    );
    if (!target.rows[0]) throw new Error(`${input.kind.toLowerCase()} account not found in company`);

    const je = await client.query(
      `INSERT INTO journal_entries(
         company_id, txn_date, status, source_type, memo, created_by, idempotency_key
       )
       VALUES ($1,$2,'DRAFT',$3,$4,$5,$6)
       RETURNING id`,
      [
        input.companyId,
        input.txnDate,
        input.sourceType,
        input.description,
        input.actorId,
        input.idempotencyKey,
      ]
    );
    const id = je.rows[0].id;
    const amount = input.amount;

    if (input.kind === 'EXPENSE') {
      await client.query(
        `INSERT INTO journal_lines(
           journal_entry_id, company_id, line_no, account_id, financial_account_id,
           description, debit, credit
         ) VALUES
           ($1,$2,1,$3,NULL,$5,$6,0),
           ($1,$2,2,$4,$7,$5,0,$6)`,
        [
          id,
          input.companyId,
          target.rows[0].id,
          fa.rows[0].gl_account_id,
          input.description,
          amount,
          input.financialAccountId,
        ]
      );
    } else {
      await client.query(
        `INSERT INTO journal_lines(
           journal_entry_id, company_id, line_no, account_id, financial_account_id,
           description, debit, credit
         ) VALUES
           ($1,$2,1,$3,$7,$5,$6,0),
           ($1,$2,2,$4,NULL,$5,0,$6)`,
        [
          id,
          input.companyId,
          fa.rows[0].gl_account_id,
          target.rows[0].id,
          input.description,
          amount,
          input.financialAccountId,
        ]
      );
    }

    await client.query(
      `INSERT INTO idempotency_registry(
         company_id, operation, idempotency_key, payload_hash, resource_id
       ) VALUES ($1,$2,$3,$4,$5)`,
      [input.companyId, operation, input.idempotencyKey, payloadHash, id]
    );

    await client.query(
      `INSERT INTO approval_requests(
         company_id, resource_type, resource_id, action, amount, requested_by
       ) VALUES ($1,'journal_entry',$2,'POST_JOURNAL',$3,$4)
       ON CONFLICT (company_id, resource_type, resource_id, action) DO NOTHING`,
      [input.companyId, id, amount, input.actorId]
    );

    await client.query(
      `INSERT INTO audit_events(
         company_id, actor_user_id, event_type, resource_type, resource_id, payload
       ) VALUES ($1,$2,$3,'journal_entry',$4,$5::jsonb)`,
      [
        input.companyId,
        input.actorId,
        `${input.kind}_DRAFT_CREATED`,
        id,
        JSON.stringify({ amount, accountCode: input.accountCode, source: input.sourceType }),
      ]
    );

    await client.query('COMMIT');
    return { id, replayed: false };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function createExpenseDraft(input: {
  actorId: string;
  companyId: string;
  financialAccountId: string;
  expenseAccountCode: string;
  amount: string;
  txnDate: string;
  description: string;
  idempotencyKey: string;
  sourceType?: string;
}) {
  return createDraft({
    ...input,
    accountCode: input.expenseAccountCode,
    kind: 'EXPENSE',
    sourceType: input.sourceType ?? 'AI_MCP_DRAFT',
  });
}

export async function createIncomeDraft(input: {
  actorId: string;
  companyId: string;
  financialAccountId: string;
  revenueAccountCode: string;
  amount: string;
  txnDate: string;
  description: string;
  idempotencyKey: string;
  sourceType?: string;
}) {
  return createDraft({
    ...input,
    accountCode: input.revenueAccountCode,
    kind: 'INCOME',
    sourceType: input.sourceType ?? 'HUMAN_UI_DRAFT',
  });
}
