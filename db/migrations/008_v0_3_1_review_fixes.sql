-- Accounting OS Local v0.3.1 review fixes.
-- Makes tax finalization balance-preserving, tenant-safe, and lifecycle-controlled.

BEGIN;

ALTER TABLE tax_calculation_records
  ADD COLUMN IF NOT EXISTS counterpart_journal_line_id uuid REFERENCES journal_lines(id) ON DELETE RESTRICT;

ALTER TABLE tax_ledger_entries
  ADD COLUMN IF NOT EXISTS journal_line_id uuid REFERENCES journal_lines(id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX IF NOT EXISTS ux_tax_ledger_record
  ON tax_ledger_entries(tax_calculation_record_id);

-- Disable only accounts that still have the publicly known legacy demo hash.
UPDATE app_users
SET is_active=false,
    password_hash=NULL,
    must_change_password=true,
    locked_until='infinity'::timestamptz
WHERE lower(email) IN ('owner@local.accounting', 'accountant@local.accounting')
  AND password_hash='pbkdf2_sha256$310000$OPzFto5+TsgnKtfvPjT5yw==$Cbbfq0dIcFEVbfIz/POFDhUnl92Rqp8PVMbYpnu8qW8=';

UPDATE user_sessions s
SET revoked_at=now()
FROM app_users u
WHERE s.user_id=u.id
  AND u.is_active=false
  AND lower(u.email) IN ('owner@local.accounting', 'accountant@local.accounting')
  AND s.revoked_at IS NULL;

UPDATE mcp_identities m
SET is_active=false
FROM app_users u
WHERE m.user_id=u.id
  AND u.is_active=false
  AND lower(u.email) IN ('owner@local.accounting', 'accountant@local.accounting');

DROP FUNCTION IF EXISTS tax_resolve_vat_tax_point(text,date,date,date,date,date);
CREATE OR REPLACE FUNCTION tax_resolve_vat_tax_point(
  p_transaction_type text,
  p_transaction_date date,
  p_delivery_date date DEFAULT NULL,
  p_payment_date date DEFAULT NULL,
  p_invoice_date date DEFAULT NULL,
  p_import_date date DEFAULT NULL,
  p_ownership_transfer_date date DEFAULT NULL,
  p_service_use_date date DEFAULT NULL
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
      FROM unnest(ARRAY[
        p_delivery_date, p_ownership_transfer_date, p_payment_date, p_invoice_date
      ]) AS x(d)
      WHERE d IS NOT NULL;
    WHEN 'SERVICE' THEN
      SELECT min(d) INTO v_tax_point
      FROM unnest(ARRAY[p_payment_date, p_invoice_date, p_service_use_date]) AS x(d)
      WHERE d IS NOT NULL;
    WHEN 'IMPORT' THEN
      v_tax_point := p_import_date;
    WHEN 'ADVANCE', 'DEPOSIT' THEN
      SELECT min(d) INTO v_tax_point
      FROM unnest(ARRAY[p_payment_date, p_invoice_date]) AS x(d)
      WHERE d IS NOT NULL;
    ELSE
      RAISE EXCEPTION 'unsupported VAT transaction type: %', p_transaction_type;
  END CASE;

  IF v_tax_point IS NULL THEN
    RAISE EXCEPTION 'VAT tax point event date is required for %', p_transaction_type;
  END IF;
  RETURN v_tax_point;
END;
$$;

CREATE OR REPLACE FUNCTION validate_tax_record_company()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_journal_company uuid;
  v_line_company uuid;
  v_line_journal uuid;
  v_rule_type text;
BEGIN
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
  IF NEW.journal_entry_id IS NOT NULL
     AND NEW.source_journal_entry_id IS DISTINCT FROM NEW.journal_entry_id THEN
    RAISE EXCEPTION 'source journal must equal the canonical tax journal';
  END IF;

  IF NEW.counterpart_journal_line_id IS NOT NULL THEN
    SELECT company_id, journal_entry_id INTO v_line_company, v_line_journal
    FROM journal_lines
    WHERE id=NEW.counterpart_journal_line_id;
    IF v_line_company IS NULL
       OR v_line_company <> NEW.company_id
       OR v_line_journal IS DISTINCT FROM NEW.journal_entry_id THEN
      RAISE EXCEPTION 'cross-company or unrelated tax counterpart line rejected';
    END IF;
  END IF;

  IF NEW.tax_type='VAT' AND NEW.tax_point_date IS NULL THEN
    RAISE EXCEPTION 'VAT tax_point_date is required';
  END IF;
  NEW.tax_point_date := COALESCE(NEW.tax_point_date, NEW.transaction_date);
  NEW.tax_period := to_char(NEW.tax_point_date, 'YYYY-MM');
  NEW.tax_point_type := COALESCE(NEW.tax_point_type, NEW.transaction_type);

  IF NEW.status='FINAL'
     AND (TG_OP='INSERT' OR OLD.status IS DISTINCT FROM 'FINAL')
     AND COALESCE(current_setting('accounting.tax_transition', true), 'off') <> 'on' THEN
    RAISE EXCEPTION 'use finalize_tax_calculation to create a FINAL tax record';
  END IF;

  IF NEW.journal_entry_id IS NOT NULL AND NEW.status='DRAFT' AND EXISTS (
    SELECT 1
    FROM approval_requests ar
    WHERE ar.company_id=NEW.company_id
      AND ar.resource_type='journal_entry'
      AND ar.resource_id=NEW.journal_entry_id
      AND ar.action='POST_JOURNAL'
      AND ar.status='APPROVED'
  ) THEN
    RAISE EXCEPTION 'cannot attach a DRAFT tax record to an approved journal';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION protect_final_tax_calculation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status='FINAL' THEN
    RAISE EXCEPTION 'FINAL tax calculation is immutable; create a correcting record';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION guard_journal_line_write()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_entry_id uuid;
  v_status text;
  v_company uuid;
  v_fa_company uuid;
  v_fa_gl uuid;
BEGIN
  v_entry_id := CASE WHEN TG_OP='DELETE' THEN OLD.journal_entry_id ELSE NEW.journal_entry_id END;

  SELECT status, company_id INTO v_status, v_company
  FROM journal_entries
  WHERE id=v_entry_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'journal entry not found'; END IF;
  IF v_status <> 'DRAFT' THEN
    RAISE EXCEPTION 'journal lines are writable only while journal is DRAFT';
  END IF;
  IF EXISTS (
    SELECT 1 FROM tax_calculation_records t
    WHERE t.journal_entry_id=v_entry_id AND t.status='FINAL'
  ) AND COALESCE(current_setting('accounting.tax_transition', true), 'off') <> 'on' THEN
    RAISE EXCEPTION 'journal lines linked to FINAL tax records are immutable';
  END IF;

  IF TG_OP <> 'DELETE' THEN
    IF NEW.company_id <> v_company THEN
      RAISE EXCEPTION 'journal line company mismatch';
    END IF;
    IF NEW.financial_account_id IS NOT NULL THEN
      SELECT company_id, gl_account_id INTO v_fa_company, v_fa_gl
      FROM financial_accounts
      WHERE id=NEW.financial_account_id AND is_active=true;
      IF NOT FOUND THEN RAISE EXCEPTION 'financial account not found or inactive'; END IF;
      IF v_fa_company <> NEW.company_id OR v_fa_gl <> NEW.account_id THEN
        RAISE EXCEPTION 'financial account must belong to same company and map to journal GL account';
      END IF;
    END IF;
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END;
$$;

CREATE OR REPLACE FUNCTION enforce_tax_before_approval_or_post()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_entry_id uuid;
BEGIN
  IF TG_TABLE_NAME='approval_requests' THEN
    IF NEW.status='APPROVED' AND OLD.status IS DISTINCT FROM 'APPROVED'
       AND NEW.resource_type='journal_entry' AND NEW.action='POST_JOURNAL' THEN
      v_entry_id := NEW.resource_id;
    ELSE
      RETURN NEW;
    END IF;
  ELSE
    IF NEW.status='POSTED' AND OLD.status='DRAFT' THEN
      v_entry_id := NEW.id;
    ELSE
      RETURN NEW;
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM tax_calculation_records t
    WHERE t.journal_entry_id=v_entry_id AND t.status='DRAFT'
  ) THEN
    RAISE EXCEPTION 'all linked tax records must be FINAL before approval or posting';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tax_before_approval ON approval_requests;
CREATE TRIGGER trg_tax_before_approval
BEFORE UPDATE ON approval_requests
FOR EACH ROW EXECUTE FUNCTION enforce_tax_before_approval_or_post();

DROP TRIGGER IF EXISTS trg_tax_before_post ON journal_entries;
CREATE TRIGGER trg_tax_before_post
BEFORE UPDATE ON journal_entries
FOR EACH ROW EXECUTE FUNCTION enforce_tax_before_approval_or_post();

CREATE OR REPLACE FUNCTION protect_tax_ledger_entry()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_rec tax_calculation_records%ROWTYPE;
  v_journal_company uuid;
  v_line_company uuid;
  v_line_journal uuid;
  v_line_key text;
  v_line_debit numeric(18,2);
  v_line_credit numeric(18,2);
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'tax_ledger_entries are append-only';
  END IF;

  SELECT * INTO v_rec
  FROM tax_calculation_records
  WHERE id=NEW.tax_calculation_record_id;
  IF NOT FOUND OR v_rec.status <> 'FINAL' THEN
    RAISE EXCEPTION 'tax ledger requires a FINAL tax record';
  END IF;
  SELECT company_id INTO v_journal_company
  FROM journal_entries WHERE id=NEW.journal_entry_id;
  SELECT jl.company_id, jl.journal_entry_id, a.system_key, jl.debit, jl.credit
    INTO v_line_company, v_line_journal, v_line_key, v_line_debit, v_line_credit
  FROM journal_lines jl
  JOIN chart_of_accounts a ON a.id=jl.account_id
  WHERE jl.id=NEW.journal_line_id;

  IF NEW.company_id <> v_rec.company_id
     OR NEW.journal_entry_id IS DISTINCT FROM v_rec.journal_entry_id
     OR v_journal_company IS DISTINCT FROM NEW.company_id
     OR v_line_company IS DISTINCT FROM NEW.company_id
     OR v_line_journal IS DISTINCT FROM NEW.journal_entry_id THEN
    RAISE EXCEPTION 'cross-company or unrelated tax ledger link rejected';
  END IF;
  IF NEW.tax_type <> v_rec.tax_type
     OR NEW.tax_period <> v_rec.tax_period
     OR NEW.amount <> v_rec.tax_amount
     OR v_line_key IS DISTINCT FROM NEW.account_system_key THEN
    RAISE EXCEPTION 'tax ledger does not match its canonical tax record/control line';
  END IF;
  IF (NEW.direction='DEBIT' AND (v_line_debit<>NEW.amount OR v_line_credit<>0))
     OR (NEW.direction='CREDIT' AND (v_line_credit<>NEW.amount OR v_line_debit<>0)) THEN
    RAISE EXCEPTION 'tax ledger direction/amount does not match journal line';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tax_ledger_immutable ON tax_ledger_entries;
CREATE TRIGGER trg_tax_ledger_immutable
BEFORE INSERT OR UPDATE OR DELETE ON tax_ledger_entries
FOR EACH ROW EXECUTE FUNCTION protect_tax_ledger_entry();

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
  v_counterpart journal_lines%ROWTYPE;
  v_counterpart_system_key text;
  v_financial journal_lines%ROWTYPE;
  v_financial_count integer;
  v_tax_line uuid;
  v_debit numeric(18,2);
  v_credit numeric(18,2);
  v_rule tax_rule_versions%ROWTYPE;
  v_expected_base numeric(18,2);
  v_expected_tax numeric(18,2);
  v_expected_gross numeric(18,2);
  v_contract_total numeric(18,2);
  v_resolved_tax_point date;
BEGIN
  SELECT * INTO v_rec
  FROM tax_calculation_records
  WHERE id=p_record_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'tax calculation record not found'; END IF;
  IF v_rec.status <> 'DRAFT' THEN RAISE EXCEPTION 'only DRAFT tax records can be finalized'; END IF;
  IF v_rec.journal_entry_id IS NULL OR v_rec.counterpart_journal_line_id IS NULL THEN
    RAISE EXCEPTION 'tax record must link to a journal and counterpart line before FINAL';
  END IF;
  IF v_rec.tax_amount <= 0 THEN RAISE EXCEPTION 'zero tax records must not be finalized'; END IF;

  SELECT * INTO v_rule
  FROM tax_rule_versions
  WHERE id=v_rec.tax_rule_version_id;
  IF NOT FOUND
     OR v_rule.verification_status<>'VERIFIED'
     OR v_rule.tax_type<>v_rec.tax_type
     OR v_rule.rate_bps<>v_rec.rate_bps
     OR v_rec.tax_point_date<v_rule.effective_from
     OR (v_rule.effective_to IS NOT NULL AND v_rec.tax_point_date>v_rule.effective_to) THEN
    RAISE EXCEPTION 'tax record does not match its verified effective rule';
  END IF;

  IF v_rec.tax_type='VAT' THEN
    v_resolved_tax_point := tax_resolve_vat_tax_point(
      v_rec.transaction_type,
      v_rec.transaction_date,
      NULLIF(v_rec.calculation_inputs->>'deliveryDate','')::date,
      NULLIF(v_rec.calculation_inputs->>'paymentDate','')::date,
      NULLIF(v_rec.calculation_inputs->>'invoiceDate','')::date,
      NULLIF(v_rec.calculation_inputs->>'importDate','')::date,
      NULLIF(v_rec.calculation_inputs->>'ownershipTransferDate','')::date,
      NULLIF(v_rec.calculation_inputs->>'serviceUseDate','')::date
    );
    IF v_resolved_tax_point<>v_rec.tax_point_date THEN
      RAISE EXCEPTION 'VAT tax point does not match deterministic resolver';
    END IF;
    SELECT base_amount, tax_amount, gross_amount
      INTO v_expected_base, v_expected_tax, v_expected_gross
    FROM tax_vat_breakdown(
      CASE WHEN v_rec.amount_mode='EXCLUSIVE' THEN v_rec.base_amount ELSE v_rec.gross_amount END,
      v_rec.rate_bps,
      v_rec.amount_mode
    );
  ELSE
    IF v_rule.transaction_type IS DISTINCT FROM v_rec.transaction_type
       OR (v_rule.payee_type IS NOT NULL
           AND v_rule.payee_type<>'BOTH'
           AND v_rule.payee_type IS DISTINCT FROM v_rec.payee_type) THEN
      RAISE EXCEPTION 'WHT transaction/payee classification does not match rule';
    END IF;
    v_contract_total := NULLIF(
      COALESCE(
        v_rec.calculation_inputs->>'contractTotalAmount',
        v_rec.calculation_inputs->>'contract_total_amount'
      ),
      ''
    )::numeric(18,2);
    IF v_contract_total IS NULL THEN
      RAISE EXCEPTION 'WHT contract total is required in calculation_inputs';
    END IF;
    SELECT v_rec.base_amount, tax_amount, v_rec.base_amount
      INTO v_expected_base, v_expected_tax, v_expected_gross
    FROM tax_wht_breakdown(
      v_rec.base_amount, v_contract_total, v_rec.rate_bps, v_rule.threshold_amount
    );
  END IF;

  IF v_expected_base IS DISTINCT FROM v_rec.base_amount
     OR v_expected_tax IS DISTINCT FROM v_rec.tax_amount
     OR v_expected_gross IS DISTINCT FROM v_rec.gross_amount THEN
    RAISE EXCEPTION 'tax amounts do not match deterministic PostgreSQL calculation';
  END IF;

  SELECT status INTO v_journal_status
  FROM journal_entries
  WHERE id=v_rec.journal_entry_id AND company_id=v_rec.company_id
  FOR UPDATE;
  IF v_journal_status IS NULL THEN RAISE EXCEPTION 'journal not found for tax record'; END IF;
  IF v_journal_status <> 'DRAFT' THEN RAISE EXCEPTION 'tax record must be FINAL before journal posting'; END IF;
  IF EXISTS (
    SELECT 1 FROM approval_requests ar
    WHERE ar.company_id=v_rec.company_id
      AND ar.resource_type='journal_entry'
      AND ar.resource_id=v_rec.journal_entry_id
      AND ar.action='POST_JOURNAL'
      AND ar.status='APPROVED'
  ) THEN
    RAISE EXCEPTION 'finalize tax before journal approval';
  END IF;

  SELECT can_post INTO v_can_post
  FROM company_memberships
  WHERE user_id=p_actor AND company_id=v_rec.company_id
    AND (expires_at IS NULL OR expires_at > now());
  IF COALESCE(v_can_post,false)=false THEN
    RAISE EXCEPTION 'actor cannot finalize tax for this company';
  END IF;

  SELECT jl.* INTO v_counterpart
  FROM journal_lines jl
  WHERE jl.id=v_rec.counterpart_journal_line_id
    AND jl.company_id=v_rec.company_id
    AND jl.journal_entry_id=v_rec.journal_entry_id
  FOR UPDATE;
  IF NOT FOUND OR v_counterpart.financial_account_id IS NOT NULL THEN
    RAISE EXCEPTION 'tax counterpart must be a non-financial line in the same journal';
  END IF;
  SELECT system_key INTO v_counterpart_system_key
  FROM chart_of_accounts WHERE id=v_counterpart.account_id;
  IF v_counterpart_system_key IN ('VAT_INPUT','VAT_OUTPUT','WHT_RECEIVABLE','WHT_PAYABLE') THEN
    RAISE EXCEPTION 'tax counterpart cannot be a tax control account';
  END IF;

  SELECT count(*) INTO v_financial_count
  FROM journal_lines
  WHERE journal_entry_id=v_rec.journal_entry_id
    AND financial_account_id IS NOT NULL;
  IF v_financial_count <> 1 THEN
    RAISE EXCEPTION 'tax journal must have exactly one financial account line';
  END IF;
  SELECT jl.* INTO v_financial
  FROM journal_lines jl
  WHERE jl.journal_entry_id=v_rec.journal_entry_id
    AND jl.financial_account_id IS NOT NULL
  FOR UPDATE;

  PERFORM set_config('accounting.tax_transition','on',true);

  IF v_rec.tax_type='VAT' THEN
    IF v_rec.reference_type IS NULL OR v_rec.reference_type NOT IN ('PURCHASE','SALE')
       OR v_rec.amount_mode IS NULL OR v_rec.amount_mode NOT IN ('EXCLUSIVE','INCLUSIVE') THEN
      RAISE EXCEPTION 'VAT requires PURCHASE/SALE and EXCLUSIVE/INCLUSIVE';
    END IF;
    v_key := CASE WHEN v_rec.reference_type='PURCHASE' THEN 'VAT_INPUT' ELSE 'VAT_OUTPUT' END;
    v_direction := CASE WHEN v_rec.reference_type='PURCHASE' THEN 'DEBIT' ELSE 'CREDIT' END;

    IF v_rec.reference_type='PURCHASE' THEN
      IF v_counterpart.debit<=0 OR v_financial.credit<=0 THEN
        RAISE EXCEPTION 'VAT PURCHASE requires debit counterpart and credit financial line';
      END IF;
      IF v_rec.amount_mode='INCLUSIVE' THEN
        IF v_counterpart.debit<>v_rec.gross_amount THEN RAISE EXCEPTION 'VAT inclusive counterpart must equal gross amount'; END IF;
        IF v_counterpart.debit<=v_rec.tax_amount THEN RAISE EXCEPTION 'VAT exceeds inclusive counterpart'; END IF;
        UPDATE journal_lines SET debit=debit-v_rec.tax_amount WHERE id=v_counterpart.id;
      ELSE
        IF v_counterpart.debit<>v_rec.base_amount THEN RAISE EXCEPTION 'VAT exclusive counterpart must equal base amount'; END IF;
        UPDATE journal_lines SET credit=credit+v_rec.tax_amount WHERE id=v_financial.id;
      END IF;
    ELSE
      IF v_counterpart.credit<=0 OR v_financial.debit<=0 THEN
        RAISE EXCEPTION 'VAT SALE requires credit counterpart and debit financial line';
      END IF;
      IF v_rec.amount_mode='INCLUSIVE' THEN
        IF v_counterpart.credit<>v_rec.gross_amount THEN RAISE EXCEPTION 'VAT inclusive counterpart must equal gross amount'; END IF;
        IF v_counterpart.credit<=v_rec.tax_amount THEN RAISE EXCEPTION 'VAT exceeds inclusive counterpart'; END IF;
        UPDATE journal_lines SET credit=credit-v_rec.tax_amount WHERE id=v_counterpart.id;
      ELSE
        IF v_counterpart.credit<>v_rec.base_amount THEN RAISE EXCEPTION 'VAT exclusive counterpart must equal base amount'; END IF;
        UPDATE journal_lines SET debit=debit+v_rec.tax_amount WHERE id=v_financial.id;
      END IF;
    END IF;
  ELSE
    IF v_rec.reference_type IS NULL OR v_rec.reference_type NOT IN ('PAYABLE','RECEIVABLE')
       OR v_rec.amount_mode IS DISTINCT FROM 'BASE_ONLY' THEN
      RAISE EXCEPTION 'WHT requires PAYABLE/RECEIVABLE and BASE_ONLY';
    END IF;
    v_key := CASE WHEN v_rec.reference_type='RECEIVABLE' THEN 'WHT_RECEIVABLE' ELSE 'WHT_PAYABLE' END;
    v_direction := CASE WHEN v_rec.reference_type='RECEIVABLE' THEN 'DEBIT' ELSE 'CREDIT' END;
    IF v_rec.reference_type='PAYABLE' THEN
      IF v_counterpart.debit<=0 OR v_financial.credit<=v_rec.tax_amount THEN
        RAISE EXCEPTION 'WHT PAYABLE requires gross debit and sufficient financial credit';
      END IF;
      IF v_counterpart.debit<>v_rec.base_amount THEN RAISE EXCEPTION 'WHT counterpart must equal base amount'; END IF;
      UPDATE journal_lines SET credit=credit-v_rec.tax_amount WHERE id=v_financial.id;
    ELSE
      IF v_counterpart.credit<=0 OR v_financial.debit<=v_rec.tax_amount THEN
        RAISE EXCEPTION 'WHT RECEIVABLE requires gross credit and sufficient financial debit';
      END IF;
      IF v_counterpart.credit<>v_rec.base_amount THEN RAISE EXCEPTION 'WHT counterpart must equal base amount'; END IF;
      UPDATE journal_lines SET debit=debit-v_rec.tax_amount WHERE id=v_financial.id;
    END IF;
  END IF;

  SELECT id INTO v_account
  FROM chart_of_accounts
  WHERE company_id=v_rec.company_id AND system_key=v_key AND is_active=true;
  IF v_account IS NULL THEN RAISE EXCEPTION 'tax control account missing: %', v_key; END IF;

  SELECT COALESCE(max(line_no),0)+1 INTO v_line_no
  FROM journal_lines WHERE journal_entry_id=v_rec.journal_entry_id;
  INSERT INTO journal_lines(
    journal_entry_id, company_id, line_no, account_id, description, debit, credit
  ) VALUES (
    v_rec.journal_entry_id, v_rec.company_id, v_line_no, v_account,
    'Tax control: ' || v_rec.tax_type || ' ' || v_rec.tax_period,
    CASE WHEN v_direction='DEBIT' THEN v_rec.tax_amount ELSE 0 END,
    CASE WHEN v_direction='CREDIT' THEN v_rec.tax_amount ELSE 0 END
  ) RETURNING id INTO v_tax_line;

  SELECT COALESCE(sum(debit),0), COALESCE(sum(credit),0)
    INTO v_debit, v_credit
  FROM journal_lines WHERE journal_entry_id=v_rec.journal_entry_id;
  IF v_debit<=0 OR v_debit<>v_credit THEN
    RAISE EXCEPTION 'tax integration left journal unbalanced: debit %, credit %', v_debit, v_credit;
  END IF;

  UPDATE approval_requests
  SET amount=v_debit
  WHERE company_id=v_rec.company_id
    AND resource_type='journal_entry'
    AND resource_id=v_rec.journal_entry_id
    AND action='POST_JOURNAL'
    AND status='PENDING';

  UPDATE tax_calculation_records
  SET status='FINAL', finalized_at=now(), finalized_by=p_actor
  WHERE id=p_record_id;

  INSERT INTO tax_ledger_entries(
    company_id, tax_calculation_record_id, journal_entry_id, journal_line_id,
    tax_type, tax_period, account_system_key, amount, direction
  ) VALUES (
    v_rec.company_id, v_rec.id, v_rec.journal_entry_id, v_tax_line,
    v_rec.tax_type, v_rec.tax_period, v_key, v_rec.tax_amount, v_direction
  );

  INSERT INTO audit_events(company_id, actor_user_id, event_type, resource_type, resource_id, payload)
  VALUES(
    v_rec.company_id, p_actor, 'TAX_CALCULATION_FINALIZED', 'tax_calculation_record', v_rec.id::text,
    jsonb_build_object('journal_entry_id',v_rec.journal_entry_id,'tax_type',v_rec.tax_type,
                       'tax_period',v_rec.tax_period,'tax_amount',v_rec.tax_amount,
                       'account_system_key',v_key)
  );
  PERFORM set_config('accounting.tax_transition','off',true);
END;
$$;

COMMIT;
