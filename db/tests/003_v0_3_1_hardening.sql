-- v0.3.1 hardening regression/invariant tests.

DO $$
DECLARE
  v_user uuid;
  v_company_a uuid;
  v_company_b uuid;
  v_rule uuid;
  v_wht_rule uuid;
  v_journal uuid;
  v_other_journal uuid;
  v_record uuid;
  v_integration_journal uuid;
  v_cash_account uuid;
  v_revenue_account uuid;
  v_financial_account uuid;
  v_financial_line uuid;
  v_counterpart_line uuid;
  v_tax_line uuid;
  v_expense_account uuid;
  v_wht_journal uuid;
  v_wht_counterpart_line uuid;
  v_wht_record uuid;
  v_error text;
  v_tax_point date;
  v_tax numeric(18,2);
  v_qualifies boolean;
  v_debit numeric(18,2);
  v_credit numeric(18,2);
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
    ('5000','ค่าใช้จ่าย','EXPENSE','EXPENSE_GENERAL'),
    ('1300','ภาษีซื้อ','ASSET','VAT_INPUT'),
    ('1310','ภาษีหัก ณ ที่จ่ายถูกหัก','ASSET','WHT_RECEIVABLE'),
    ('2200','ภาษีขายค้างจ่าย','LIABILITY','VAT_OUTPUT'),
    ('2210','ภาษีหัก ณ ที่จ่ายค้างจ่าย','LIABILITY','WHT_PAYABLE')
  ) AS x(code, name_th, account_type, system_key)
  WHERE c.id IN (v_company_a, v_company_b)
  ON CONFLICT(company_id, code) DO NOTHING;

  SELECT id INTO v_rule FROM tax_rule_resolve('VAT','VAT_STANDARD','2026-08-20'::date);
  SELECT id INTO v_wht_rule FROM tax_rule_resolve('WHT','WHT_SERVICE','2026-08-20'::date);

  SELECT tax_resolve_vat_tax_point(
    'SALE_GOODS','2026-08-20','2026-08-18',NULL,'2026-08-19',NULL,NULL,NULL
  )
  INTO v_tax_point;
  IF v_tax_point <> '2026-08-18'::date THEN
    RAISE EXCEPTION 'VAT tax point SALE_GOODS failed: %', v_tax_point;
  END IF;

  SELECT tax_resolve_vat_tax_point(
    'SERVICE','2026-08-20',NULL,'2026-08-21','2026-08-19',NULL,NULL,'2026-08-17'
  )
  INTO v_tax_point;
  IF v_tax_point <> '2026-08-17'::date THEN
    RAISE EXCEPTION 'VAT tax point SERVICE failed: %', v_tax_point;
  END IF;

  BEGIN
    PERFORM tax_resolve_vat_tax_point(
      'SERVICE','2026-08-20',NULL,NULL,NULL,NULL,NULL,NULL
    );
    RAISE EXCEPTION 'VAT tax point accepted a missing legal event date';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
    IF v_error NOT ILIKE '%event date is required%' THEN
      RAISE EXCEPTION 'unexpected missing tax point error: %', v_error;
    END IF;
  END;

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

  SELECT id INTO v_cash_account
  FROM chart_of_accounts WHERE company_id=v_company_a AND system_key='CASH';
  SELECT id INTO v_revenue_account
  FROM chart_of_accounts WHERE company_id=v_company_a AND system_key='REVENUE_MAIN';
  SELECT id INTO v_expense_account
  FROM chart_of_accounts WHERE company_id=v_company_a AND system_key='EXPENSE_GENERAL';
  SELECT id INTO v_financial_account
  FROM financial_accounts
  WHERE company_id=v_company_a AND gl_account_id=v_cash_account AND name='QA cash'
  LIMIT 1;
  IF v_financial_account IS NULL THEN
    INSERT INTO financial_accounts(company_id, gl_account_id, kind, name)
    VALUES(v_company_a, v_cash_account, 'CASH', 'QA cash')
    RETURNING id INTO v_financial_account;
  END IF;

  INSERT INTO journal_entries(company_id, txn_date, memo, created_by, idempotency_key)
  VALUES(v_company_a, '2026-08-20', 'QA VAT inclusive integration', v_user, gen_random_uuid()::text)
  RETURNING id INTO v_integration_journal;
  INSERT INTO journal_lines(
    journal_entry_id, company_id, line_no, account_id, financial_account_id,
    description, debit, credit
  ) VALUES(
    v_integration_journal, v_company_a, 1, v_cash_account, v_financial_account,
    'Cash receipt gross', 1070, 0
  ) RETURNING id INTO v_financial_line;
  INSERT INTO journal_lines(
    journal_entry_id, company_id, line_no, account_id, description, debit, credit
  ) VALUES(
    v_integration_journal, v_company_a, 2, v_revenue_account,
    'Revenue gross before VAT split', 0, 1070
  ) RETURNING id INTO v_counterpart_line;

  INSERT INTO tax_calculation_records(
    company_id, journal_entry_id, tax_type, tax_rule_version_id,
    transaction_date, transaction_type, tax_point_date, tax_period, tax_point_type,
    amount_mode, base_amount, rate_bps, tax_amount, gross_amount,
    reference_type, calculation_inputs, calculation_hash, status, created_by, idempotency_key,
    counterpart_journal_line_id
  ) VALUES (
    v_company_a, v_integration_journal, 'VAT', v_rule,
    '2026-08-20', 'SALE_GOODS', '2026-08-20', '2026-08', 'SALE_GOODS',
    'INCLUSIVE', 1000, 700, 70, 1070,
    'SALE', '{"deliveryDate":"2026-08-20"}'::jsonb,
    'qa-vat-integration', 'DRAFT', v_user, gen_random_uuid()::text,
    v_counterpart_line
  ) RETURNING id INTO v_record;

  UPDATE tax_calculation_records SET tax_amount=69 WHERE id=v_record;
  BEGIN
    PERFORM finalize_tax_calculation(v_record, v_user);
    RAISE EXCEPTION 'incorrect deterministic VAT amount was finalized';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
    IF v_error NOT ILIKE '%deterministic PostgreSQL calculation%' THEN
      RAISE EXCEPTION 'unexpected deterministic VAT validation error: %', v_error;
    END IF;
  END;
  UPDATE tax_calculation_records SET tax_amount=70 WHERE id=v_record;
  PERFORM finalize_tax_calculation(v_record, v_user);

  SELECT COALESCE(sum(debit),0), COALESCE(sum(credit),0)
    INTO v_debit, v_credit
  FROM journal_lines WHERE journal_entry_id=v_integration_journal;
  IF v_debit<>1070 OR v_credit<>1070 THEN
    RAISE EXCEPTION 'VAT journal integration is unbalanced: %/%', v_debit, v_credit;
  END IF;
  IF (SELECT credit FROM journal_lines WHERE id=v_counterpart_line)<>1000 THEN
    RAISE EXCEPTION 'VAT inclusive integration did not reduce revenue to base';
  END IF;
  SELECT journal_line_id INTO v_tax_line
  FROM tax_ledger_entries WHERE tax_calculation_record_id=v_record;
  IF v_tax_line IS NULL OR (SELECT credit FROM journal_lines WHERE id=v_tax_line)<>70 THEN
    RAISE EXCEPTION 'canonical VAT ledger/control line missing';
  END IF;

  BEGIN
    UPDATE tax_calculation_records SET tax_period='2026-09' WHERE id=v_record;
    RAISE EXCEPTION 'FINAL tax record mutation was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
    IF v_error NOT ILIKE '%immutable%' THEN
      RAISE EXCEPTION 'unexpected FINAL immutability error: %', v_error;
    END IF;
  END;

  BEGIN
    UPDATE journal_lines SET credit=999 WHERE id=v_counterpart_line;
    RAISE EXCEPTION 'journal linked to FINAL tax was mutable';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
    IF v_error NOT ILIKE '%FINAL tax records are immutable%' THEN
      RAISE EXCEPTION 'unexpected tax-linked journal immutability error: %', v_error;
    END IF;
  END;

  BEGIN
    INSERT INTO tax_ledger_entries(
      company_id, tax_calculation_record_id, journal_entry_id, journal_line_id,
      tax_type, tax_period, account_system_key, amount, direction
    ) VALUES(
      v_company_b, v_record, v_other_journal, v_tax_line,
      'VAT', '2026-08', 'VAT_OUTPUT', 70, 'CREDIT'
    );
    RAISE EXCEPTION 'cross-company tax ledger link was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
    IF v_error NOT ILIKE '%cross-company%' THEN
      RAISE EXCEPTION 'unexpected cross-company tax ledger error: %', v_error;
    END IF;
  END;

  INSERT INTO journal_entries(company_id, txn_date, memo, created_by, idempotency_key)
  VALUES(v_company_a, '2026-08-20', 'QA WHT payable integration', v_user, gen_random_uuid()::text)
  RETURNING id INTO v_wht_journal;
  INSERT INTO journal_lines(
    journal_entry_id, company_id, line_no, account_id, description, debit, credit
  ) VALUES(
    v_wht_journal, v_company_a, 1, v_expense_account, 'Service expense gross', 500, 0
  ) RETURNING id INTO v_wht_counterpart_line;
  INSERT INTO journal_lines(
    journal_entry_id, company_id, line_no, account_id, financial_account_id,
    description, debit, credit
  ) VALUES(
    v_wht_journal, v_company_a, 2, v_cash_account, v_financial_account,
    'Cash payment before WHT', 0, 500
  );
  INSERT INTO tax_calculation_records(
    company_id, journal_entry_id, tax_type, tax_rule_version_id,
    transaction_date, transaction_type, payee_type, tax_point_date, tax_period,
    amount_mode, base_amount, rate_bps, tax_amount, gross_amount,
    reference_type, calculation_inputs, calculation_hash, status, created_by,
    idempotency_key, counterpart_journal_line_id
  ) VALUES(
    v_company_a, v_wht_journal, 'WHT', v_wht_rule,
    '2026-08-20', 'SERVICE', 'LEGAL_ENTITY', '2026-08-20', '2026-08',
    'BASE_ONLY', 500, 300, 15, 500,
    'PAYABLE', '{"contractTotalAmount":"1500.00"}'::jsonb,
    'qa-wht-integration', 'DRAFT', v_user, gen_random_uuid()::text, v_wht_counterpart_line
  ) RETURNING id INTO v_wht_record;
  PERFORM finalize_tax_calculation(v_wht_record, v_user);
  SELECT COALESCE(sum(debit),0), COALESCE(sum(credit),0)
    INTO v_debit, v_credit
  FROM journal_lines WHERE journal_entry_id=v_wht_journal;
  IF v_debit<>500 OR v_credit<>500 THEN
    RAISE EXCEPTION 'WHT journal integration is unbalanced: %/%', v_debit, v_credit;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM journal_lines jl
    JOIN chart_of_accounts a ON a.id=jl.account_id
    WHERE jl.journal_entry_id=v_wht_journal
      AND a.system_key='WHT_PAYABLE' AND jl.credit=15
  ) OR NOT EXISTS (
    SELECT 1 FROM journal_lines
    WHERE journal_entry_id=v_wht_journal
      AND financial_account_id=v_financial_account AND credit=485
  ) THEN
    RAISE EXCEPTION 'WHT payable integration did not split net cash/control liability';
  END IF;

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
  ON CONFLICT(company_id, tax_type, idempotency_key)
    WHERE idempotency_key IS NOT NULL AND status <> 'VOID'
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
