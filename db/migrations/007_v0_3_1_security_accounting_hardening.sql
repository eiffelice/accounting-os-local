-- Accounting OS Local v0.3.1 — security/accounting hardening.
-- Adds canonical tax point/ledger lifecycle, MCP identities, secure auth state,
-- Bangkok accounting timezone defaults, and backup metadata.

BEGIN;

ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS accounting_timezone text NOT NULL DEFAULT 'Asia/Bangkok';

ALTER TABLE app_users
  ADD COLUMN IF NOT EXISTS failed_login_count integer NOT NULL DEFAULT 0 CHECK (failed_login_count >= 0),
  ADD COLUMN IF NOT EXISTS locked_until timestamptz;

CREATE TABLE IF NOT EXISTS mcp_identities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  name text NOT NULL,
  token_hash text NOT NULL UNIQUE,
  scopes text[] NOT NULL DEFAULT ARRAY[]::text[],
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz,
  CHECK (array_position(scopes, 'tax_submit') IS NULL),
  CHECK (array_position(scopes, 'payment_execute') IS NULL)
);

ALTER TABLE tax_calculation_records
  ADD COLUMN IF NOT EXISTS tax_point_date date,
  ADD COLUMN IF NOT EXISTS tax_period text,
  ADD COLUMN IF NOT EXISTS tax_point_type text,
  ADD COLUMN IF NOT EXISTS source_journal_entry_id uuid REFERENCES journal_entries(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS finalized_by uuid REFERENCES app_users(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS voided_by uuid REFERENCES app_users(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS voided_at timestamptz,
  ADD COLUMN IF NOT EXISTS idempotency_key text;

UPDATE tax_calculation_records
SET tax_point_date = transaction_date
WHERE tax_point_date IS NULL;

UPDATE tax_calculation_records
SET tax_period = to_char(tax_point_date, 'YYYY-MM')
WHERE tax_period IS NULL;

ALTER TABLE tax_calculation_records
  ALTER COLUMN tax_point_date SET NOT NULL,
  ALTER COLUMN tax_period SET NOT NULL;

ALTER TABLE tax_calculation_records
  DROP CONSTRAINT IF EXISTS chk_tax_calc_period_matches_point;
ALTER TABLE tax_calculation_records
  ADD CONSTRAINT chk_tax_calc_period_matches_point
  CHECK (tax_period = to_char(tax_point_date, 'YYYY-MM'));

ALTER TABLE tax_calculation_records
  DROP CONSTRAINT IF EXISTS chk_tax_calc_journal_link;
ALTER TABLE tax_calculation_records
  ADD CONSTRAINT chk_tax_calc_journal_link
  CHECK (journal_entry_id IS NULL OR source_journal_entry_id IS NULL OR journal_entry_id = source_journal_entry_id);

CREATE UNIQUE INDEX IF NOT EXISTS ux_tax_calc_idempotency
  ON tax_calculation_records(company_id, tax_type, idempotency_key)
  WHERE idempotency_key IS NOT NULL AND status <> 'VOID';

CREATE INDEX IF NOT EXISTS idx_tax_calc_company_period
  ON tax_calculation_records(company_id, tax_period, tax_type, status);

CREATE TABLE IF NOT EXISTS tax_ledger_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  tax_calculation_record_id uuid NOT NULL REFERENCES tax_calculation_records(id) ON DELETE RESTRICT,
  journal_entry_id uuid NOT NULL REFERENCES journal_entries(id) ON DELETE RESTRICT,
  tax_type text NOT NULL CHECK (tax_type IN ('VAT','WHT')),
  tax_period text NOT NULL,
  account_system_key text NOT NULL CHECK (account_system_key IN ('VAT_INPUT','VAT_OUTPUT','WHT_RECEIVABLE','WHT_PAYABLE')),
  amount numeric(18,2) NOT NULL CHECK (amount >= 0),
  direction text NOT NULL CHECK (direction IN ('DEBIT','CREDIT')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id, tax_calculation_record_id, account_system_key)
);

CREATE TABLE IF NOT EXISTS backup_manifests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  backup_file text NOT NULL UNIQUE,
  cipher text NOT NULL,
  sha256 text NOT NULL,
  hmac_sha256 text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  verified_at timestamptz
);

CREATE OR REPLACE FUNCTION tax_resolve_vat_tax_point(
  p_transaction_type text,
  p_transaction_date date,
  p_delivery_date date DEFAULT NULL,
  p_payment_date date DEFAULT NULL,
  p_invoice_date date DEFAULT NULL,
  p_import_date date DEFAULT NULL
) RETURNS date
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_tax_point date;
BEGIN
  IF p_transaction_date IS NULL THEN
    RAISE EXCEPTION 'transaction_date is required';
  END IF;

  CASE p_transaction_type
    WHEN 'SALE_GOODS' THEN
      SELECT min(d) INTO v_tax_point
      FROM unnest(ARRAY[p_delivery_date, p_payment_date, p_invoice_date]) AS x(d)
      WHERE d IS NOT NULL;
      v_tax_point := COALESCE(v_tax_point, p_transaction_date);
    WHEN 'SERVICE' THEN
      SELECT min(d) INTO v_tax_point
      FROM unnest(ARRAY[p_payment_date, p_invoice_date]) AS x(d)
      WHERE d IS NOT NULL;
      v_tax_point := COALESCE(v_tax_point, p_transaction_date);
    WHEN 'IMPORT' THEN
      v_tax_point := COALESCE(p_import_date, p_transaction_date);
    WHEN 'ADVANCE', 'DEPOSIT' THEN
      v_tax_point := COALESCE(p_payment_date, p_invoice_date, p_transaction_date);
    ELSE
      RAISE EXCEPTION 'unsupported VAT transaction type: %', p_transaction_type;
  END CASE;

  RETURN v_tax_point;
END;
$$;

CREATE OR REPLACE FUNCTION validate_tax_record_company()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_journal_company uuid;
  v_rule_type text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  SELECT tax_type INTO v_rule_type
  FROM tax_rule_versions
  WHERE id=NEW.tax_rule_version_id;
  IF v_rule_type IS NULL OR v_rule_type <> NEW.tax_type THEN
    RAISE EXCEPTION 'tax rule/type mismatch';
  END IF;

  IF NEW.journal_entry_id IS NOT NULL THEN
    SELECT company_id INTO v_journal_company
    FROM journal_entries
    WHERE id=NEW.journal_entry_id;
    IF v_journal_company IS NULL OR v_journal_company <> NEW.company_id THEN
      RAISE EXCEPTION 'cross-company tax record journal link rejected';
    END IF;
  END IF;

  IF NEW.source_journal_entry_id IS NOT NULL THEN
    SELECT company_id INTO v_journal_company
    FROM journal_entries
    WHERE id=NEW.source_journal_entry_id;
    IF v_journal_company IS NULL OR v_journal_company <> NEW.company_id THEN
      RAISE EXCEPTION 'cross-company tax record source journal link rejected';
    END IF;
  END IF;

  NEW.source_journal_entry_id := COALESCE(NEW.source_journal_entry_id, NEW.journal_entry_id);
  NEW.tax_point_date := COALESCE(NEW.tax_point_date, NEW.transaction_date);
  NEW.tax_period := to_char(NEW.tax_point_date, 'YYYY-MM');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tax_calc_company_integrity ON tax_calculation_records;
CREATE TRIGGER trg_tax_calc_company_integrity
BEFORE INSERT OR UPDATE ON tax_calculation_records
FOR EACH ROW EXECUTE FUNCTION validate_tax_record_company();

CREATE OR REPLACE FUNCTION protect_final_tax_calculation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' AND OLD.status='FINAL' THEN
    RAISE EXCEPTION 'FINAL tax calculation is immutable; void with a correcting record';
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status='FINAL' THEN
    IF NEW.status='VOID'
       AND OLD.company_id=NEW.company_id
       AND OLD.id=NEW.id
       AND OLD.tax_amount=NEW.tax_amount
       AND OLD.base_amount=NEW.base_amount THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'FINAL tax calculation is immutable; void with a correcting record';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tax_calc_final_immutable ON tax_calculation_records;
CREATE TRIGGER trg_tax_calc_final_immutable
BEFORE UPDATE OR DELETE ON tax_calculation_records
FOR EACH ROW EXECUTE FUNCTION protect_final_tax_calculation();

CREATE OR REPLACE FUNCTION finalize_tax_calculation(
  p_record_id uuid,
  p_actor uuid
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_rec tax_calculation_records%ROWTYPE;
  v_journal_status text;
  v_can_post boolean;
  v_account uuid;
  v_line_no integer;
  v_key text;
  v_direction text;
BEGIN
  SELECT * INTO v_rec
  FROM tax_calculation_records
  WHERE id=p_record_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'tax calculation record not found'; END IF;
  IF v_rec.status <> 'DRAFT' THEN RAISE EXCEPTION 'only DRAFT tax records can be finalized'; END IF;
  IF v_rec.journal_entry_id IS NULL THEN RAISE EXCEPTION 'tax record must link to a journal before FINAL'; END IF;

  SELECT status INTO v_journal_status
  FROM journal_entries
  WHERE id=v_rec.journal_entry_id AND company_id=v_rec.company_id
  FOR UPDATE;
  IF v_journal_status IS NULL THEN RAISE EXCEPTION 'journal not found for tax record'; END IF;
  IF v_journal_status <> 'DRAFT' THEN RAISE EXCEPTION 'tax record must be FINAL before journal posting'; END IF;

  SELECT can_post INTO v_can_post
  FROM company_memberships
  WHERE user_id=p_actor AND company_id=v_rec.company_id
    AND (expires_at IS NULL OR expires_at > now());
  IF COALESCE(v_can_post,false)=false THEN
    RAISE EXCEPTION 'actor cannot finalize tax for this company';
  END IF;

  IF v_rec.tax_type='VAT' THEN
    v_key := CASE WHEN v_rec.reference_type='PURCHASE' THEN 'VAT_INPUT' ELSE 'VAT_OUTPUT' END;
    v_direction := CASE WHEN v_key='VAT_INPUT' THEN 'DEBIT' ELSE 'CREDIT' END;
  ELSE
    v_key := CASE WHEN v_rec.reference_type='RECEIVABLE' THEN 'WHT_RECEIVABLE' ELSE 'WHT_PAYABLE' END;
    v_direction := CASE WHEN v_key='WHT_RECEIVABLE' THEN 'DEBIT' ELSE 'CREDIT' END;
  END IF;

  SELECT id INTO v_account
  FROM chart_of_accounts
  WHERE company_id=v_rec.company_id AND system_key=v_key AND is_active=true;
  IF v_account IS NULL THEN RAISE EXCEPTION 'tax control account missing: %', v_key; END IF;

  SELECT COALESCE(max(line_no),0) + 1 INTO v_line_no
  FROM journal_lines
  WHERE journal_entry_id=v_rec.journal_entry_id;

  INSERT INTO journal_lines(
    journal_entry_id, company_id, line_no, account_id, description, debit, credit
  ) VALUES (
    v_rec.journal_entry_id, v_rec.company_id, v_line_no, v_account,
    'Tax control: ' || v_rec.tax_type || ' ' || v_rec.tax_period,
    CASE WHEN v_direction='DEBIT' THEN v_rec.tax_amount ELSE 0 END,
    CASE WHEN v_direction='CREDIT' THEN v_rec.tax_amount ELSE 0 END
  );

  INSERT INTO tax_ledger_entries(
    company_id, tax_calculation_record_id, journal_entry_id, tax_type,
    tax_period, account_system_key, amount, direction
  ) VALUES (
    v_rec.company_id, v_rec.id, v_rec.journal_entry_id, v_rec.tax_type,
    v_rec.tax_period, v_key, v_rec.tax_amount, v_direction
  );

  UPDATE tax_calculation_records
  SET status='FINAL', finalized_at=now(), finalized_by=p_actor
  WHERE id=p_record_id;
END;
$$;

COMMIT;
