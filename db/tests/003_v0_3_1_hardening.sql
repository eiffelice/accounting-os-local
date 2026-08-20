-- v0.3.1 hardening regression/invariant tests.

DO $$
DECLARE
  v_user uuid;
  v_company_a uuid;
  v_company_b uuid;
  v_rule uuid;
  v_journal uuid;
  v_other_journal uuid;
  v_record uuid;
  v_error text;
  v_tax_point date;
  v_tax numeric(18,2);
  v_qualifies boolean;
BEGIN
  INSERT INTO app_users(email, display_name)
  VALUES ('qa-v031@local.accounting', 'QA v0.3.1')
  ON CONFLICT(email) DO UPDATE SET display_name=excluded.display_name
  RETURNING id INTO v_user;

  INSERT INTO companies(code, legal_name, display_name)
  VALUES ('QA031A', 'QA 031 A', 'QA031A')
  ON CONFLICT(code) DO UPDATE SET display_name=excluded.display_name
  RETURNING id INTO v_company_a;

  INSERT INTO companies(code, legal_name, display_name)
  VALUES ('QA031B', 'QA 031 B', 'QA031B')
  ON CONFLICT(code) DO UPDATE SET display_name=excluded.display_name
  RETURNING id INTO v_company_b;

  INSERT INTO company_memberships(user_id, company_id, role, can_read, can_create_draft, can_approve, can_post)
  VALUES (v_user, v_company_a, 'OWNER', true, true, true, true)
  ON CONFLICT(user_id, company_id) DO UPDATE
  SET can_read=true, can_create_draft=true, can_approve=true, can_post=true;

  INSERT INTO chart_of_accounts(company_id, code, name_th, account_type, system_key)
  SELECT c.id, x.code, x.name_th, x.account_type, x.system_key
  FROM companies c
  CROSS JOIN (VALUES
    ('1000','เงินสด','ASSET','CASH'),
    ('4000','รายได้','REVENUE','REVENUE_MAIN'),
    ('1300','ภาษีซื้อ','ASSET','VAT_INPUT'),
    ('1310','ภาษีหัก ณ ที่จ่ายถูกหัก','ASSET','WHT_RECEIVABLE'),
    ('2200','ภาษีขายค้างจ่าย','LIABILITY','VAT_OUTPUT'),
    ('2210','ภาษีหัก ณ ที่จ่ายค้างจ่าย','LIABILITY','WHT_PAYABLE')
  ) AS x(code, name_th, account_type, system_key)
  WHERE c.id IN (v_company_a, v_company_b)
  ON CONFLICT(company_id, code) DO NOTHING;

  SELECT id INTO v_rule FROM tax_rule_resolve('VAT','VAT_STANDARD','2026-08-20'::date);

  SELECT tax_resolve_vat_tax_point('SALE_GOODS','2026-08-20','2026-08-18',NULL,'2026-08-19',NULL)
  INTO v_tax_point;
  IF v_tax_point <> '2026-08-18'::date THEN
    RAISE EXCEPTION 'VAT tax point SALE_GOODS failed: %', v_tax_point;
  END IF;

  SELECT tax_resolve_vat_tax_point('SERVICE','2026-08-20',NULL,'2026-08-21','2026-08-19',NULL)
  INTO v_tax_point;
  IF v_tax_point <> '2026-08-19'::date THEN
    RAISE EXCEPTION 'VAT tax point SERVICE failed: %', v_tax_point;
  END IF;

  SELECT contract_qualifies, tax_amount
  INTO v_qualifies, v_tax
  FROM tax_wht_breakdown(500.00,1500.00,300,1000.00);
  IF v_qualifies IS DISTINCT FROM true OR v_tax <> 15.00 THEN
    RAISE EXCEPTION 'WHT split-payment invariant failed';
  END IF;

  INSERT INTO journal_entries(company_id, txn_date, memo, created_by, idempotency_key)
  VALUES(v_company_a, '2026-08-20', 'QA tax journal', v_user, 'qa031-tax-a')
  ON CONFLICT(company_id, idempotency_key) DO UPDATE SET memo=excluded.memo
  RETURNING id INTO v_journal;

  INSERT INTO journal_entries(company_id, txn_date, memo, created_by, idempotency_key)
  VALUES(v_company_b, '2026-08-20', 'QA other journal', v_user, 'qa031-tax-b')
  ON CONFLICT(company_id, idempotency_key) DO UPDATE SET memo=excluded.memo
  RETURNING id INTO v_other_journal;

  BEGIN
    INSERT INTO tax_calculation_records(
      company_id, journal_entry_id, tax_type, tax_rule_version_id,
      transaction_date, tax_point_date, tax_period, amount_mode,
      base_amount, rate_bps, tax_amount, gross_amount,
      calculation_hash, status, created_by
    ) VALUES (
      v_company_a, v_other_journal, 'VAT', v_rule,
      '2026-08-20', '2026-08-20', '2026-08',
      'EXCLUSIVE', 1000, 700, 70, 1070,
      'qa-cross-company', 'DRAFT', v_user
    );
    RAISE EXCEPTION 'cross-company tax record was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
    IF v_error NOT ILIKE '%cross-company%' THEN
      RAISE EXCEPTION 'unexpected cross-company error: %', v_error;
    END IF;
  END;

  INSERT INTO tax_calculation_records(
    company_id, journal_entry_id, tax_type, tax_rule_version_id,
    transaction_date, tax_point_date, tax_period, amount_mode,
    base_amount, rate_bps, tax_amount, gross_amount,
    calculation_hash, status, created_by, idempotency_key
  ) VALUES (
    v_company_a, v_journal, 'VAT', v_rule,
    '2026-08-20', '2026-08-20', '2026-08',
    'EXCLUSIVE', 1000, 700, 70, 1070,
    'qa-idempotent', 'DRAFT', v_user, 'qa-vat-1'
  )
  ON CONFLICT(company_id, tax_type, idempotency_key) WHERE status <> 'VOID'
  DO UPDATE SET calculation_hash=excluded.calculation_hash
  RETURNING id INTO v_record;

  BEGIN
    INSERT INTO tax_calculation_records(
      company_id, journal_entry_id, tax_type, tax_rule_version_id,
      transaction_date, tax_point_date, tax_period, amount_mode,
      base_amount, rate_bps, tax_amount, gross_amount,
      calculation_hash, status, created_by, idempotency_key
    ) VALUES (
      v_company_a, v_journal, 'VAT', v_rule,
      '2026-08-20', '2026-08-20', '2026-08',
      'EXCLUSIVE', 2000, 700, 140, 2140,
      'qa-idempotent-conflict', 'DRAFT', v_user, 'qa-vat-1'
    );
    RAISE EXCEPTION 'duplicate tax idempotency key was accepted';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO mcp_identities(user_id, name, token_hash, scopes)
    VALUES(v_user, 'bad scope', repeat('a',64), ARRAY['read','tax_submit']);
    RAISE EXCEPTION 'forbidden MCP scope was accepted';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
END;
$$;

SELECT 'PASS: v0.3.1 hardening invariants' AS result;
