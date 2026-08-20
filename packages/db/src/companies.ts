import { pool, type Company } from './base.ts';
import { getMembership } from './access.ts';

export type BankDirectoryRow = {
  slug: string;
  name: string;
  brand_color: string;
};

export async function listCompanies(): Promise<Company[]> {
  const { rows } = await pool.query<Company>(
    `SELECT id, code, legal_name, display_name, base_currency
     FROM companies
     WHERE is_active = true
     ORDER BY code`
  );
  return rows;
}

export async function listCompaniesForUser(userId: string): Promise<Company[]> {
  const { rows } = await pool.query<Company>(
    `SELECT c.id, c.code, c.legal_name, c.display_name, c.base_currency
     FROM companies c
     JOIN company_memberships m ON m.company_id=c.id
     WHERE m.user_id=$1
       AND m.can_read=true
       AND c.is_active=true
       AND (m.expires_at IS NULL OR m.expires_at > now())
     ORDER BY c.code`,
    [userId]
  );
  return rows;
}

export async function createCompany(
  actorId: string,
  input: {
    code: string;
    legalName: string;
    displayName: string;
    taxId?: string;
  }
) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const code = input.code.trim().toUpperCase().replace(/[^A-Z0-9_-]/g, '');
    if (!code || code.length > 30) throw new Error('invalid company code');

    const company = await client.query(
      `INSERT INTO companies(code, legal_name, display_name, tax_id)
       VALUES($1,$2,$3,$4)
       RETURNING id, code, legal_name, display_name, base_currency`,
      [code, input.legalName.trim(), input.displayName.trim(), input.taxId?.trim() || null]
    );
    const companyId = company.rows[0].id as string;

    await client.query(
      `INSERT INTO branches(company_id, code, name, is_head_office)
       VALUES($1,'HQ','สำนักงานใหญ่',true)`,
      [companyId]
    );

    await client.query(
      `INSERT INTO company_memberships(
         user_id, company_id, role, can_read, can_create_draft, can_approve, can_post
       ) VALUES($1,$2,'OWNER',true,true,true,true)`,
      [actorId, companyId]
    );

    const coa = [
      ['1000','เงินสด','ASSET','CASH'],
      ['1100','เงินฝากธนาคาร/อีวอลเล็ต','ASSET','BANK'],
      ['1200','ลูกหนี้การค้า','ASSET','AR'],
      ['1300','ภาษีซื้อ','ASSET','VAT_INPUT'],
      ['1310','ภาษีหัก ณ ที่จ่ายถูกหัก','ASSET','WHT_RECEIVABLE'],
      ['2000','เจ้าหนี้การค้า','LIABILITY','AP'],
      ['2100','เจ้าหนี้บัตรเครดิต','LIABILITY','CREDIT_CARD_PAYABLE'],
      ['2200','ภาษีขายค้างจ่าย','LIABILITY','VAT_OUTPUT'],
      ['2210','ภาษีหัก ณ ที่จ่ายค้างจ่าย','LIABILITY','WHT_PAYABLE'],
      ['3000','ทุน','EQUITY','EQUITY'],
      ['4000','รายได้จากการขาย/บริการ','REVENUE','REVENUE_MAIN'],
      ['5000','ค่าใช้จ่ายทั่วไป','EXPENSE','EXPENSE_GENERAL'],
      ['5100','ค่าสาธารณูปโภค','EXPENSE','EXPENSE_UTILITIES'],
      ['5200','ค่าโฆษณาและการตลาด','EXPENSE','EXPENSE_ADS'],
    ];

    for (const [codeValue, name, type, key] of coa) {
      await client.query(
        `INSERT INTO chart_of_accounts(company_id, code, name_th, account_type, system_key)
         VALUES($1,$2,$3,$4,$5)`,
        [companyId, codeValue, name, type, key]
      );
    }

    await client.query(
      `INSERT INTO company_tax_profiles(company_id)
       VALUES($1)
       ON CONFLICT (company_id) DO NOTHING`,
      [companyId]
    );

    const { rows: yearRows } = await client.query<{ year: number }>(
      `SELECT extract(year FROM now() AT TIME ZONE accounting_timezone)::int AS year
       FROM companies WHERE id=$1`,
      [companyId]
    );
    const year = yearRows[0].year;
    await client.query(
      `INSERT INTO fiscal_periods(company_id, period_key, start_date, end_date, status)
       VALUES($1,$2,$3,$4,'OPEN')`,
      [companyId, `FY${year}`, `${year}-01-01`, `${year}-12-31`]
    );

    await client.query(
      `INSERT INTO audit_events(company_id, actor_user_id, event_type, resource_type, resource_id, payload)
       VALUES($1,$2,'COMPANY_CREATED','company',$1,$3::jsonb)`,
      [companyId, actorId, JSON.stringify({ code, displayName: input.displayName.trim() })]
    );

    await client.query('COMMIT');
    return company.rows[0] as Company;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

export async function createFinancialAccount(
  actorId: string,
  companyId: string,
  input: {
    kind: 'BANK' | 'CASH' | 'E_WALLET' | 'CREDIT_CARD';
    name: string;
    bankSlug?: string;
    institution?: string;
    maskedNumber?: string;
    currency?: string;
  }
) {
  const membership = await getMembership(actorId, companyId);
  if (!membership || !['OWNER','CFO','ACCOUNTING_MANAGER','ACCOUNTANT'].includes(membership.role)) {
    throw new Error('ACCESS_DENIED: cannot create financial account');
  }

  if (!['BANK','CASH','E_WALLET','CREDIT_CARD'].includes(input.kind)) {
    throw new Error('invalid financial account kind');
  }
  const name = input.name.trim();
  if (!name || name.length > 160) throw new Error('financial account name must be 1-160 characters');

  const bankSlug = input.bankSlug?.trim() || null;
  if (bankSlug && !/^[a-z0-9]+$/.test(bankSlug)) throw new Error('invalid bank logo identifier');
  if (input.kind === 'BANK' && !bankSlug) throw new Error('bank is required for bank accounts');
  if (input.kind === 'CASH' && bankSlug) throw new Error('cash accounts cannot have a bank');
  const customInstitution = input.institution?.trim() || null;
  if (customInstitution && customInstitution.length > 120) throw new Error('institution is too long');
  const maskedNumber = input.maskedNumber?.trim() || null;
  if (maskedNumber && (
    maskedNumber.length < 4
    || maskedNumber.length > 80
    || !/^[0-9Xx* .-]+$/.test(maskedNumber)
    || !/[Xx*]/.test(maskedNumber)
  )) {
    throw new Error('account number must be masked with X or *');
  }
  const currency = (input.currency ?? 'THB').toUpperCase();
  if (!/^[A-Z]{3}$/.test(currency)) throw new Error('currency must be a 3-letter code');

  const systemKey =
    input.kind === 'CASH'
      ? 'CASH'
      : input.kind === 'CREDIT_CARD'
        ? 'CREDIT_CARD_PAYABLE'
        : 'BANK';

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { rows: gl } = await client.query(
      `SELECT id FROM chart_of_accounts
       WHERE company_id=$1 AND system_key=$2 AND is_active=true`,
      [companyId, systemKey]
    );
    if (!gl[0]) throw new Error(`required GL control account ${systemKey} not found`);

    const { rows: branch } = await client.query(
      `SELECT id FROM branches WHERE company_id=$1 AND is_head_office=true LIMIT 1`,
      [companyId]
    );
    let institution = customInstitution;
    if (bankSlug) {
      const { rows: banks } = await client.query<{ name: string }>(
        `SELECT name FROM bank_directory WHERE slug=$1 AND is_active=true`,
        [bankSlug]
      );
      if (!banks[0]) throw new Error('unknown or inactive bank');
      institution = banks[0].name;
    }

    const { rows } = await client.query(
      `INSERT INTO financial_accounts(
         company_id, branch_id, gl_account_id, kind, name, bank_slug, institution, masked_number, currency
       ) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)
       RETURNING id`,
      [
        companyId, branch[0]?.id ?? null, gl[0].id, input.kind, name, bankSlug,
        institution, maskedNumber, currency
      ]
    );

    await client.query(
      `INSERT INTO audit_events(company_id, actor_user_id, event_type, resource_type, resource_id, payload)
       VALUES($1,$2,'FINANCIAL_ACCOUNT_CREATED','financial_account',$3,$4::jsonb)`,
      [
        companyId, actorId, rows[0].id,
        JSON.stringify({ kind: input.kind, name, bankSlug, institution })
      ]
    );
    await client.query('COMMIT');
    return rows[0].id as string;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function listBanks() {
  const { rows } = await pool.query<BankDirectoryRow>(
    `SELECT slug, name, brand_color
     FROM bank_directory
     WHERE is_active=true
     ORDER BY name`
  );
  return rows;
}

export async function financialAccountBalances(companyId: string) {
  const { rows } = await pool.query(
    `SELECT fa.id, fa.kind, fa.name, fa.institution, fa.masked_number, fa.currency,
            fa.bank_slug, b.name AS bank_name,
            b.brand_color AS bank_brand_color,
            COALESCE(sum(
              CASE
                WHEN je.status NOT IN ('POSTED','REVERSED') THEN 0
                WHEN a.account_type IN ('LIABILITY','EQUITY','REVENUE') THEN jl.credit-jl.debit
                ELSE jl.debit-jl.credit
              END
            ),0)::text AS balance
     FROM financial_accounts fa
     JOIN chart_of_accounts a ON a.id=fa.gl_account_id
     LEFT JOIN bank_directory b ON b.slug=fa.bank_slug
     LEFT JOIN journal_lines jl ON jl.financial_account_id=fa.id
     LEFT JOIN journal_entries je ON je.id=jl.journal_entry_id
     WHERE fa.company_id=$1 AND fa.is_active=true
     GROUP BY fa.id, fa.kind, fa.name, fa.institution, fa.masked_number, fa.currency,
              fa.bank_slug, b.name, b.brand_color, a.account_type
     ORDER BY fa.kind, fa.name`,
    [companyId]
  );
  return rows;
}

export async function listFinancialAccounts(companyId: string) {
  const { rows } = await pool.query(
    `SELECT fa.id, fa.kind, fa.name, fa.institution, fa.masked_number, fa.currency,
            fa.bank_slug, b.name AS bank_name,
            b.brand_color AS bank_brand_color,
            a.code AS gl_code, a.name_th AS gl_name
     FROM financial_accounts fa
     JOIN chart_of_accounts a ON a.id = fa.gl_account_id
     LEFT JOIN bank_directory b ON b.slug=fa.bank_slug
     WHERE fa.company_id = $1 AND fa.is_active = true
     ORDER BY fa.kind, fa.name`,
    [companyId]
  );
  return rows;
}

export async function listExpenseAccounts(companyId: string) {
  const { rows } = await pool.query(
    `SELECT id, code, name_th
     FROM chart_of_accounts
     WHERE company_id=$1 AND account_type='EXPENSE' AND is_active=true
     ORDER BY code`,
    [companyId]
  );
  return rows;
}

export async function listRevenueAccounts(companyId: string) {
  const { rows } = await pool.query(
    `SELECT id, code, name_th
     FROM chart_of_accounts
     WHERE company_id=$1 AND account_type='REVENUE' AND is_active=true
     ORDER BY code`,
    [companyId]
  );
  return rows;
}
