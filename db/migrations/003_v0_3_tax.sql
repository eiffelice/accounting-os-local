-- Accounting OS Local v0.3 — Thai Tax Core
-- Deterministic, versioned tax rules. Safe to re-run.

BEGIN;

CREATE TABLE IF NOT EXISTS tax_rule_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  country_code text NOT NULL DEFAULT 'TH' CHECK (country_code ~ '^[A-Z]{2}$'),
  tax_type text NOT NULL CHECK (tax_type IN ('VAT','WHT')),
  rule_code text NOT NULL,
  version integer NOT NULL CHECK (version > 0),
  name_th text NOT NULL,
  description_th text NOT NULL DEFAULT '',
  rate_bps integer NOT NULL CHECK (rate_bps BETWEEN 0 AND 10000),
  effective_from date NOT NULL,
  effective_to date,
  transaction_type text,
  payer_type text,
  payee_type text,
  threshold_amount numeric(18,2) NOT NULL DEFAULT 0 CHECK (threshold_amount >= 0),
  form_code_individual text,
  form_code_legal_entity text,
  legal_reference text NOT NULL,
  source_url text NOT NULL,
  source_checked_at date NOT NULL,
  verification_status text NOT NULL DEFAULT 'VERIFIED'
    CHECK (verification_status IN ('VERIFIED','REVIEW_REQUIRED','RETIRED')),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (effective_to IS NULL OR effective_to >= effective_from),
  UNIQUE(country_code, tax_type, rule_code, version)
);

CREATE INDEX IF NOT EXISTS idx_tax_rule_lookup
  ON tax_rule_versions(tax_type, rule_code, effective_from, effective_to, version);

CREATE TABLE IF NOT EXISTS company_tax_profiles (
  company_id uuid PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
  vat_registered boolean NOT NULL DEFAULT false,
  vat_registration_date date,
  wht_enabled boolean NOT NULL DEFAULT true,
  filing_channel text NOT NULL DEFAULT 'INTERNET'
    CHECK (filing_channel IN ('PAPER','INTERNET')),
  branch_code text NOT NULL DEFAULT '00000',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO company_tax_profiles(company_id)
SELECT id FROM companies
ON CONFLICT (company_id) DO NOTHING;

CREATE TABLE IF NOT EXISTS tax_deadline_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  country_code text NOT NULL DEFAULT 'TH',
  rule_code text NOT NULL UNIQUE,
  tax_type text NOT NULL CHECK (tax_type IN ('VAT','WHT')),
  form_codes text[] NOT NULL,
  due_month_offset integer NOT NULL DEFAULT 1 CHECK (due_month_offset BETWEEN 0 AND 12),
  paper_due_day integer CHECK (paper_due_day BETWEEN 1 AND 31),
  internet_due_day integer CHECK (internet_due_day BETWEEN 1 AND 31),
  requires_official_calendar_check boolean NOT NULL DEFAULT true,
  legal_reference text NOT NULL,
  source_url text NOT NULL,
  source_checked_at date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tax_calculation_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  journal_entry_id uuid REFERENCES journal_entries(id) ON DELETE RESTRICT,
  tax_type text NOT NULL CHECK (tax_type IN ('VAT','WHT')),
  tax_rule_version_id uuid NOT NULL REFERENCES tax_rule_versions(id) ON DELETE RESTRICT,
  transaction_date date NOT NULL,
  transaction_type text,
  payee_type text,
  amount_mode text CHECK (amount_mode IN ('EXCLUSIVE','INCLUSIVE','BASE_ONLY')),
  base_amount numeric(18,2) NOT NULL CHECK (base_amount >= 0),
  rate_bps integer NOT NULL CHECK (rate_bps BETWEEN 0 AND 10000),
  tax_amount numeric(18,2) NOT NULL CHECK (tax_amount >= 0),
  gross_amount numeric(18,2) NOT NULL CHECK (gross_amount >= 0),
  currency text NOT NULL DEFAULT 'THB' CHECK (char_length(currency) = 3),
  form_code text,
  reference_type text,
  reference_id text,
  calculation_inputs jsonb NOT NULL DEFAULT '{}'::jsonb,
  calculation_hash text NOT NULL,
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','FINAL','VOID')),
  created_by uuid REFERENCES app_users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  finalized_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_tax_calc_company_date
  ON tax_calculation_records(company_id, transaction_date, tax_type, status);

-- Tax control accounts for existing companies.
INSERT INTO chart_of_accounts(company_id, code, name_th, account_type, system_key)
SELECT c.id, x.code, x.name_th, x.account_type, x.system_key
FROM companies c
CROSS JOIN (VALUES
  ('1300','ภาษีซื้อ','ASSET','VAT_INPUT'),
  ('1310','ภาษีหัก ณ ที่จ่ายถูกหัก','ASSET','WHT_RECEIVABLE'),
  ('2200','ภาษีขายค้างจ่าย','LIABILITY','VAT_OUTPUT'),
  ('2210','ภาษีหัก ณ ที่จ่ายค้างจ่าย','LIABILITY','WHT_PAYABLE')
) AS x(code, name_th, account_type, system_key)
WHERE NOT EXISTS (
  SELECT 1 FROM chart_of_accounts a
  WHERE a.company_id=c.id AND a.system_key=x.system_key
);

-- VAT 7%: current period and announced extension are separate immutable versions
-- so historical calculations keep the legal/source snapshot that applied on the tax point date.
INSERT INTO tax_rule_versions(
  tax_type, rule_code, version, name_th, description_th, rate_bps,
  effective_from, effective_to, transaction_type, payer_type, payee_type,
  threshold_amount, legal_reference, source_url, source_checked_at, verification_status, metadata
) VALUES
(
  'VAT','VAT_STANDARD',1,'ภาษีมูลค่าเพิ่ม อัตราทั่วไป 7%',
  'อัตรา VAT ที่ใช้กับการขายสินค้า/ให้บริการ/นำเข้าที่เข้าเกณฑ์อัตราทั่วไปในประเทศไทย',
  700,'2025-10-01','2026-09-30','STANDARD',NULL,NULL,0,
  'กรมสรรพากร ปชส.34/2568 — ขยายเวลาลด VAT เหลือ 7% ถึง 30 กันยายน 2569',
  'https://www.rd.go.th/59.html','2026-08-20','VERIFIED',
  '{"note":"rule snapshot for tax points through 2026-09-30"}'::jsonb
),
(
  'VAT','VAT_STANDARD',2,'ภาษีมูลค่าเพิ่ม อัตราทั่วไป 7%',
  'อัตรา VAT 7% ตามการขยายเวลาที่กรมสรรพากรประกาศถึง 30 กันยายน 2570',
  700,'2026-10-01','2027-09-30','STANDARD',NULL,NULL,0,
  'กรมสรรพากร ปชส.18/2569 — ขยายเวลาลด VAT เหลือ 7% ถึง 30 กันยายน 2570',
  'https://rd.go.th/59.html','2026-08-20','VERIFIED',
  '{"note":"keep legal instrument reference updated if a later official page supersedes the press release"}'::jsonb
),
(
  'WHT','WHT_SERVICE',1,'หัก ณ ที่จ่าย — ค่าบริการ 3%',
  'กฎเริ่มต้นสำหรับค่าบริการที่เข้าเกณฑ์ตามคำสั่ง ท.ป.4/2528; ต้องตรวจข้อยกเว้น/สถานะคู่สัญญาก่อนใช้จริง',
  300,'1985-09-26',NULL,'SERVICE','LEGAL_ENTITY','BOTH',500,
  'คำสั่งกรมสรรพากร ที่ ท.ป.4/2528 (กรณีค่าบริการตามข้อ 8 และข้อที่เกี่ยวข้อง)',
  'https://www.rd.go.th/3479.html','2026-08-20','VERIFIED',
  '{"risk":"transaction classification matters"}'::jsonb
),
(
  'WHT','WHT_RENT',1,'หัก ณ ที่จ่าย — ค่าเช่า 5%',
  'กฎเริ่มต้นสำหรับค่าเช่าที่เข้าเกณฑ์ตามคำสั่ง ท.ป.4/2528',
  500,'1985-09-26',NULL,'RENT','LEGAL_ENTITY','BOTH',500,
  'คำสั่งกรมสรรพากร ที่ ท.ป.4/2528 และแนววินิจฉัยกรมสรรพากรเกี่ยวกับค่าเช่า',
  'https://www.rd.go.th/3479.html','2026-08-20','VERIFIED',
  '{}'::jsonb
),
(
  'WHT','WHT_ADVERTISING',1,'หัก ณ ที่จ่าย — ค่าโฆษณา 2%',
  'กฎเริ่มต้นสำหรับค่าโฆษณาที่เข้าเกณฑ์ตามคำสั่ง ท.ป.4/2528',
  200,'1985-09-26',NULL,'ADVERTISING','LEGAL_ENTITY','BOTH',500,
  'คำสั่งกรมสรรพากร ที่ ท.ป.4/2528 ข้อ 10 และคำสั่ง ป.6/2528',
  'https://www.rd.go.th/3479.html','2026-08-20','VERIFIED',
  '{}'::jsonb
)
ON CONFLICT (country_code, tax_type, rule_code, version) DO NOTHING;

UPDATE tax_rule_versions
SET form_code_individual='PND3', form_code_legal_entity='PND53'
WHERE tax_type='WHT'
  AND form_code_individual IS NULL
  AND form_code_legal_entity IS NULL;

INSERT INTO tax_deadline_rules(
  rule_code, tax_type, form_codes, due_month_offset,
  paper_due_day, internet_due_day, requires_official_calendar_check,
  legal_reference, source_url, source_checked_at
) VALUES
(
  'TH_WHT_MONTHLY','WHT',ARRAY['PND3','PND53'],1,7,15,true,
  'ปฏิทิน/ระบบงานภาษีเงินได้หัก ณ ที่จ่ายของกรมสรรพากร',
  'https://rd.go.th/62977.html','2026-08-20'
),
(
  'TH_VAT_PP30','VAT',ARRAY['PP30'],1,15,23,true,
  'ปฏิทินภาษีอากรกรมสรรพากร; วันจริงอาจเลื่อนตามวันหยุดหรือประกาศขยายเวลา',
  'https://rd.go.th/62348.html','2026-08-20'
)
ON CONFLICT (rule_code) DO NOTHING;

CREATE OR REPLACE FUNCTION tax_percent_amount(
  p_base numeric,
  p_rate_bps integer
) RETURNS numeric(18,2)
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT round((p_base * p_rate_bps::numeric) / 10000::numeric, 2)::numeric(18,2)
$$;

CREATE OR REPLACE FUNCTION tax_vat_breakdown(
  p_amount numeric,
  p_rate_bps integer,
  p_mode text
) RETURNS TABLE(base_amount numeric(18,2), tax_amount numeric(18,2), gross_amount numeric(18,2))
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_base numeric(18,2);
  v_tax numeric(18,2);
  v_gross numeric(18,2);
BEGIN
  IF p_amount < 0 THEN
    RAISE EXCEPTION 'amount must be >= 0';
  END IF;
  IF p_rate_bps < 0 OR p_rate_bps > 10000 THEN
    RAISE EXCEPTION 'invalid rate_bps';
  END IF;

  IF p_mode = 'EXCLUSIVE' THEN
    v_base := round(p_amount, 2);
    v_tax := tax_percent_amount(v_base, p_rate_bps);
    v_gross := (v_base + v_tax)::numeric(18,2);
  ELSIF p_mode = 'INCLUSIVE' THEN
    v_gross := round(p_amount, 2);
    v_base := round(v_gross / (1 + p_rate_bps::numeric / 10000::numeric), 2)::numeric(18,2);
    v_tax := (v_gross - v_base)::numeric(18,2);
  ELSE
    RAISE EXCEPTION 'mode must be EXCLUSIVE or INCLUSIVE';
  END IF;

  RETURN QUERY SELECT v_base, v_tax, v_gross;
END;
$$;

CREATE OR REPLACE FUNCTION tax_rule_resolve(
  p_tax_type text,
  p_rule_code text,
  p_on_date date
) RETURNS SETOF tax_rule_versions
LANGUAGE sql
STABLE
AS $$
  SELECT r.*
  FROM tax_rule_versions r
  WHERE r.country_code='TH'
    AND r.tax_type=p_tax_type
    AND r.rule_code=p_rule_code
    AND r.verification_status='VERIFIED'
    AND r.effective_from <= p_on_date
    AND (r.effective_to IS NULL OR r.effective_to >= p_on_date)
  ORDER BY r.effective_from DESC, r.version DESC
  LIMIT 1
$$;

CREATE OR REPLACE FUNCTION prevent_tax_rule_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'tax_rule_versions are immutable; insert a new version instead';
END;
$$;

DROP TRIGGER IF EXISTS trg_tax_rule_immutable ON tax_rule_versions;
CREATE TRIGGER trg_tax_rule_immutable
BEFORE UPDATE OR DELETE ON tax_rule_versions
FOR EACH ROW EXECUTE FUNCTION prevent_tax_rule_mutation();

CREATE OR REPLACE FUNCTION protect_final_tax_calculation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status='FINAL' THEN
    RAISE EXCEPTION 'FINAL tax calculation is immutable; create a correcting record';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tax_calc_final_immutable ON tax_calculation_records;
CREATE TRIGGER trg_tax_calc_final_immutable
BEFORE UPDATE OR DELETE ON tax_calculation_records
FOR EACH ROW EXECUTE FUNCTION protect_final_tax_calculation();

COMMIT;
