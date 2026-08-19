import { pool } from './base.js';
import { assertCompanyAccess } from './access.js';

export type TaxType = 'VAT' | 'WHT';
export type VatMode = 'EXCLUSIVE' | 'INCLUSIVE';
export type WhtTransactionType = 'SERVICE' | 'RENT' | 'ADVERTISING';
export type PayeeType = 'INDIVIDUAL' | 'LEGAL_ENTITY';

export type TaxRule = {
  id: string;
  country_code: string;
  tax_type: TaxType;
  rule_code: string;
  version: number;
  name_th: string;
  description_th: string;
  rate_bps: number;
  effective_from: string;
  effective_to: string | null;
  transaction_type: string | null;
  payer_type: string | null;
  payee_type: string | null;
  threshold_amount: string;
  form_code_individual: string | null;
  form_code_legal_entity: string | null;
  legal_reference: string;
  source_url: string;
  source_checked_at: string;
  verification_status: string;
  metadata: Record<string, unknown>;
};

function assertIsoDate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new Error('date must be YYYY-MM-DD');
  }
}

function assertMoneyString(value: string) {
  if (!/^\d{1,15}(?:\.\d{1,2})?$/.test(value)) {
    throw new Error('amount must be a non-negative decimal string with max 2 decimals');
  }
}

export async function listTaxRules(input?: {
  taxType?: TaxType;
  asOf?: string;
}) {
  const taxType = input?.taxType ?? null;
  const asOf = input?.asOf ?? null;
  if (asOf) assertIsoDate(asOf);

  const { rows } = await pool.query<TaxRule>(
    `SELECT id, country_code, tax_type, rule_code, version, name_th,
            description_th, rate_bps, effective_from::text, effective_to::text,
            transaction_type, payer_type, payee_type, threshold_amount::text,
            form_code_individual, form_code_legal_entity, legal_reference,
            source_url, source_checked_at::text, verification_status, metadata
     FROM tax_rule_versions
     WHERE verification_status='VERIFIED'
       AND ($1::text IS NULL OR tax_type=$1)
       AND (
         $2::date IS NULL OR
         (effective_from <= $2::date AND (effective_to IS NULL OR effective_to >= $2::date))
       )
     ORDER BY tax_type, rule_code, effective_from DESC, version DESC`,
    [taxType, asOf]
  );
  return rows;
}

export async function resolveTaxRule(
  taxType: TaxType,
  ruleCode: string,
  transactionDate: string
): Promise<TaxRule> {
  assertIsoDate(transactionDate);
  const { rows } = await pool.query<TaxRule>(
    `SELECT id, country_code, tax_type, rule_code, version, name_th,
            description_th, rate_bps, effective_from::text, effective_to::text,
            transaction_type, payer_type, payee_type, threshold_amount::text,
            form_code_individual, form_code_legal_entity, legal_reference,
            source_url, source_checked_at::text, verification_status, metadata
     FROM tax_rule_resolve($1,$2,$3::date)`,
    [taxType, ruleCode, transactionDate]
  );
  if (!rows[0]) {
    throw new Error(`NO_TAX_RULE: ${taxType}/${ruleCode} on ${transactionDate}`);
  }
  return rows[0];
}

export async function calculateVat(input: {
  amount: string;
  mode: VatMode;
  transactionDate: string;
}) {
  assertMoneyString(input.amount);
  assertIsoDate(input.transactionDate);
  const rule = await resolveTaxRule('VAT', 'VAT_STANDARD', input.transactionDate);

  const { rows } = await pool.query<{
    base_amount: string;
    tax_amount: string;
    gross_amount: string;
  }>(
    `SELECT base_amount::text, tax_amount::text, gross_amount::text
     FROM tax_vat_breakdown($1::numeric,$2,$3)`,
    [input.amount, rule.rate_bps, input.mode]
  );

  return {
    taxType: 'VAT' as const,
    rule: {
      id: rule.id,
      code: rule.rule_code,
      version: rule.version,
      rateBps: rule.rate_bps,
      legalReference: rule.legal_reference,
      sourceUrl: rule.source_url,
      effectiveFrom: rule.effective_from,
      effectiveTo: rule.effective_to,
    },
    transactionDate: input.transactionDate,
    mode: input.mode,
    baseAmount: rows[0].base_amount,
    vatAmount: rows[0].tax_amount,
    grossAmount: rows[0].gross_amount,
    currency: 'THB',
    deterministic: true,
  };
}

const WHT_RULE_BY_TRANSACTION: Record<WhtTransactionType, string> = {
  SERVICE: 'WHT_SERVICE',
  RENT: 'WHT_RENT',
  ADVERTISING: 'WHT_ADVERTISING',
};

export async function calculateWht(input: {
  withholdingBaseAmount: string;
  contractTotalAmount: string;
  transactionType: WhtTransactionType;
  payeeType: PayeeType;
  transactionDate: string;
}) {
  assertMoneyString(input.withholdingBaseAmount);
  assertMoneyString(input.contractTotalAmount);
  assertIsoDate(input.transactionDate);

  const rule = await resolveTaxRule(
    'WHT',
    WHT_RULE_BY_TRANSACTION[input.transactionType],
    input.transactionDate
  );

  const { rows } = await pool.query<{
    contract_qualifies: boolean;
    tax_amount: string;
  }>(
    `SELECT contract_qualifies, tax_amount::text
     FROM tax_wht_breakdown($1::numeric,$2::numeric,$3,$4::numeric)`,
    [
      input.withholdingBaseAmount,
      input.contractTotalAmount,
      rule.rate_bps,
      rule.threshold_amount,
    ]
  );

  const formCode =
    input.payeeType === 'INDIVIDUAL'
      ? rule.form_code_individual
      : rule.form_code_legal_entity;

  return {
    taxType: 'WHT' as const,
    rule: {
      id: rule.id,
      code: rule.rule_code,
      version: rule.version,
      rateBps: rule.rate_bps,
      contractThresholdAmount: rule.threshold_amount,
      legalReference: rule.legal_reference,
      sourceUrl: rule.source_url,
      effectiveFrom: rule.effective_from,
      effectiveTo: rule.effective_to,
    },
    transactionDate: input.transactionDate,
    transactionType: input.transactionType,
    payeeType: input.payeeType,
    withholdingBaseAmount: input.withholdingBaseAmount,
    contractTotalAmount: input.contractTotalAmount,
    whtAmount: rows[0].tax_amount,
    formCode,
    contractQualifies: rows[0].contract_qualifies,
    currency: 'THB',
    deterministic: true,
    warning:
      'WHT depends on transaction classification, payer/payee status, contract total and exceptions. Verify the real transaction before filing.',
  };
}

function lastDayOfMonth(year: number, monthOneBased: number) {
  return new Date(Date.UTC(year, monthOneBased, 0)).getUTCDate();
}

function isoDate(year: number, monthOneBased: number, day: number) {
  const d = Math.min(day, lastDayOfMonth(year, monthOneBased));
  return `${year}-${String(monthOneBased).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}

export async function taxCalendarForPeriod(period: string) {
  const match = /^(\d{4})-(\d{2})$/.exec(period);
  if (!match) throw new Error('period must be YYYY-MM');
  const periodYear = Number(match[1]);
  const periodMonth = Number(match[2]);
  if (periodMonth < 1 || periodMonth > 12) throw new Error('invalid month');

  const { rows } = await pool.query<{
    rule_code: string;
    tax_type: TaxType;
    form_codes: string[];
    due_month_offset: number;
    paper_due_day: number | null;
    internet_due_day: number | null;
    requires_official_calendar_check: boolean;
    legal_reference: string;
    source_url: string;
    source_checked_at: string;
  }>(
    `SELECT rule_code, tax_type, form_codes, due_month_offset,
            paper_due_day, internet_due_day, requires_official_calendar_check,
            legal_reference, source_url, source_checked_at::text
     FROM tax_deadline_rules
     WHERE country_code='TH'
     ORDER BY tax_type, rule_code`
  );

  return rows.map((r) => {
    const zeroBased = periodMonth - 1 + r.due_month_offset;
    const dueYear = periodYear + Math.floor(zeroBased / 12);
    const dueMonth = (zeroBased % 12) + 1;
    return {
      ...r,
      taxPeriod: period,
      paperBaseDueDate: r.paper_due_day ? isoDate(dueYear, dueMonth, r.paper_due_day) : null,
      internetBaseDueDate: r.internet_due_day ? isoDate(dueYear, dueMonth, r.internet_due_day) : null,
      warning: r.requires_official_calendar_check
        ? 'Base schedule only. Check the Revenue Department tax calendar for holidays or special filing extensions before filing.'
        : null,
    };
  });
}

export async function getCompanyTaxProfile(actorId: string, companyId: string) {
  await assertCompanyAccess(actorId, companyId, 'read');
  const { rows } = await pool.query(
    `SELECT company_id, vat_registered, vat_registration_date::text,
            wht_enabled, filing_channel, branch_code
     FROM company_tax_profiles
     WHERE company_id=$1`,
    [companyId]
  );
  return rows[0] ?? null;
}

export async function taxDashboard(actorId: string, companyId: string, period: string) {
  await assertCompanyAccess(actorId, companyId, 'read');
  if (!/^\d{4}-\d{2}$/.test(period)) throw new Error('period must be YYYY-MM');

  const { rows } = await pool.query(
    `SELECT tax_type, COALESCE(form_code,'UNASSIGNED') AS form_code,
            count(*)::int AS calculations,
            COALESCE(sum(base_amount),0)::text AS base_amount,
            COALESCE(sum(tax_amount),0)::text AS tax_amount
     FROM tax_calculation_records
     WHERE company_id=$1
       AND status='FINAL'
       AND to_char(transaction_date,'YYYY-MM')=$2
     GROUP BY tax_type, COALESCE(form_code,'UNASSIGNED')
     ORDER BY tax_type, form_code`,
    [companyId, period]
  );
  return rows;
}
