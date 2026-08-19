-- Accounting OS Local v0.3 — Thai Tax Core QA / Golden Regression
-- Run after migrations through 006_v0_3_wht_engine.sql.
-- Fails fast with RAISE EXCEPTION when a core invariant regresses.

DO $$
DECLARE
  v_rate integer;
  v_version integer;
  v_threshold numeric(18,2);
  v_base numeric(18,2);
  v_tax numeric(18,2);
  v_gross numeric(18,2);
  v_wht_tax numeric(18,2);
  v_qualifies boolean;
  v_overlap_count integer;
BEGIN
  -- VAT rule on 2026-08-20 must resolve to 7%.
  SELECT rate_bps INTO v_rate
  FROM tax_rule_resolve('VAT','VAT_STANDARD','2026-08-20'::date);
  IF v_rate IS DISTINCT FROM 700 THEN
    RAISE EXCEPTION 'GOLDEN_FAIL: VAT 2026-08-20 expected 700 bps, got %', v_rate;
  END IF;

  -- VAT extension starting 2026-10-01 must also resolve to 7%.
  SELECT rate_bps INTO v_rate
  FROM tax_rule_resolve('VAT','VAT_STANDARD','2026-10-01'::date);
  IF v_rate IS DISTINCT FROM 700 THEN
    RAISE EXCEPTION 'GOLDEN_FAIL: VAT 2026-10-01 expected 700 bps, got %', v_rate;
  END IF;

  -- VAT exclusive: 1,000 + 7% = 1,070.
  SELECT base_amount, tax_amount, gross_amount
  INTO v_base, v_tax, v_gross
  FROM tax_vat_breakdown(1000.00,700,'EXCLUSIVE');
  IF v_base <> 1000.00 OR v_tax <> 70.00 OR v_gross <> 1070.00 THEN
    RAISE EXCEPTION 'GOLDEN_FAIL: VAT exclusive got base %, tax %, gross %', v_base, v_tax, v_gross;
  END IF;

  -- VAT inclusive: 1,070 inclusive must split to 1,000 + 70.
  SELECT base_amount, tax_amount, gross_amount
  INTO v_base, v_tax, v_gross
  FROM tax_vat_breakdown(1070.00,700,'INCLUSIVE');
  IF v_base <> 1000.00 OR v_tax <> 70.00 OR v_gross <> 1070.00 THEN
    RAISE EXCEPTION 'GOLDEN_FAIL: VAT inclusive got base %, tax %, gross %', v_base, v_tax, v_gross;
  END IF;

  -- Current WHT rules must be corrected v2 rules with THB 1,000 contract threshold.
  SELECT version, threshold_amount
  INTO v_version, v_threshold
  FROM tax_rule_resolve('WHT','WHT_SERVICE','2026-08-20'::date);
  IF v_version IS DISTINCT FROM 2 OR v_threshold <> 1000.00 THEN
    RAISE EXCEPTION 'GOLDEN_FAIL: service WHT expected v2 / threshold 1000, got v% / %', v_version, v_threshold;
  END IF;

  SELECT version, threshold_amount
  INTO v_version, v_threshold
  FROM tax_rule_resolve('WHT','WHT_RENT','2026-08-20'::date);
  IF v_version IS DISTINCT FROM 2 OR v_threshold <> 1000.00 THEN
    RAISE EXCEPTION 'GOLDEN_FAIL: rent WHT expected v2 / threshold 1000, got v% / %', v_version, v_threshold;
  END IF;

  SELECT version, threshold_amount
  INTO v_version, v_threshold
  FROM tax_rule_resolve('WHT','WHT_ADVERTISING','2026-08-20'::date);
  IF v_version IS DISTINCT FROM 2 OR v_threshold <> 1000.00 THEN
    RAISE EXCEPTION 'GOLDEN_FAIL: advertising WHT expected v2 / threshold 1000, got v% / %', v_version, v_threshold;
  END IF;

  -- WHT common-rate golden cases.
  IF tax_percent_amount(1000.00,300) <> 30.00 THEN
    RAISE EXCEPTION 'GOLDEN_FAIL: service WHT 3%%';
  END IF;
  IF tax_percent_amount(1000.00,500) <> 50.00 THEN
    RAISE EXCEPTION 'GOLDEN_FAIL: rent WHT 5%%';
  END IF;
  IF tax_percent_amount(1000.00,200) <> 20.00 THEN
    RAISE EXCEPTION 'GOLDEN_FAIL: advertising WHT 2%%';
  END IF;

  -- Split payment: current payment 500, contract total 1,500 => contract qualifies; 3% of 500 = 15.
  SELECT contract_qualifies, tax_amount
  INTO v_qualifies, v_wht_tax
  FROM tax_wht_breakdown(500.00,1500.00,300,1000.00);
  IF v_qualifies IS DISTINCT FROM true OR v_wht_tax <> 15.00 THEN
    RAISE EXCEPTION 'GOLDEN_FAIL: split-payment WHT expected qualifies=true/tax=15, got %/%', v_qualifies, v_wht_tax;
  END IF;

  -- Contract below threshold: payment 500, contract total 900 => no withholding in this supported rule path.
  SELECT contract_qualifies, tax_amount
  INTO v_qualifies, v_wht_tax
  FROM tax_wht_breakdown(500.00,900.00,300,1000.00);
  IF v_qualifies IS DISTINCT FROM false OR v_wht_tax <> 0.00 THEN
    RAISE EXCEPTION 'GOLDEN_FAIL: below-threshold WHT expected qualifies=false/tax=0, got %/%', v_qualifies, v_wht_tax;
  END IF;

  -- Superseded v1 WHT seed must never be selected as VERIFIED.
  IF EXISTS (
    SELECT 1 FROM tax_rule_versions
    WHERE tax_type='WHT'
      AND rule_code IN ('WHT_SERVICE','WHT_RENT','WHT_ADVERTISING')
      AND version=1
      AND verification_status='VERIFIED'
  ) THEN
    RAISE EXCEPTION 'INVARIANT_FAIL: superseded WHT v1 still VERIFIED';
  END IF;

  -- Verified rules must keep official Revenue Department provenance.
  IF EXISTS (
    SELECT 1
    FROM tax_rule_versions
    WHERE verification_status='VERIFIED'
      AND source_url NOT ILIKE '%rd.go.th%'
  ) THEN
    RAISE EXCEPTION 'INVARIANT_FAIL: VERIFIED rule without Revenue Department source';
  END IF;

  -- Same rule code must not have overlapping VERIFIED effective windows.
  SELECT count(*) INTO v_overlap_count
  FROM tax_rule_versions a
  JOIN tax_rule_versions b
    ON a.id < b.id
   AND a.country_code=b.country_code
   AND a.tax_type=b.tax_type
   AND a.rule_code=b.rule_code
   AND a.verification_status='VERIFIED'
   AND b.verification_status='VERIFIED'
   AND daterange(a.effective_from, COALESCE(a.effective_to + 1, 'infinity'::date), '[)')
       && daterange(b.effective_from, COALESCE(b.effective_to + 1, 'infinity'::date), '[)');
  IF v_overlap_count <> 0 THEN
    RAISE EXCEPTION 'INVARIANT_FAIL: overlapping VERIFIED tax rule windows = %', v_overlap_count;
  END IF;

  -- Expected tax control accounts must exist for every company.
  IF EXISTS (
    SELECT 1
    FROM companies c
    CROSS JOIN (VALUES ('VAT_INPUT'),('VAT_OUTPUT'),('WHT_RECEIVABLE'),('WHT_PAYABLE')) AS k(system_key)
    WHERE NOT EXISTS (
      SELECT 1 FROM chart_of_accounts a
      WHERE a.company_id=c.id AND a.system_key=k.system_key AND a.is_active=true
    )
  ) THEN
    RAISE EXCEPTION 'INVARIANT_FAIL: missing tax control account';
  END IF;
END;
$$;

SELECT 'PASS: Accounting OS Local v0.3 Thai Tax Core QA' AS result;
