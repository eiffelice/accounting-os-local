-- Bank directory and financial-account logo linkage invariants.

DO $$
DECLARE
  v_user uuid;
  v_company uuid;
  v_bank_gl uuid;
  v_cash_gl uuid;
  v_error text;
BEGIN
  IF (SELECT count(*) FROM bank_directory) <> 32 THEN
    RAISE EXCEPTION 'bank directory does not match the 32-logo source manifest';
  END IF;

  INSERT INTO app_users(email, display_name)
  VALUES ('qa-bank-directory@local.invalid', 'QA Bank Directory')
  RETURNING id INTO v_user;
  INSERT INTO companies(code, legal_name, display_name)
  VALUES ('QABANKDIR', 'QA Bank Directory', 'QA Bank Directory')
  RETURNING id INTO v_company;
  INSERT INTO chart_of_accounts(company_id, code, name_th, account_type, system_key)
  VALUES
    (v_company, '1000', 'Cash', 'ASSET', 'CASH'),
    (v_company, '1100', 'Bank', 'ASSET', 'BANK');
  SELECT id INTO v_bank_gl
  FROM chart_of_accounts WHERE company_id=v_company AND system_key='BANK';
  SELECT id INTO v_cash_gl
  FROM chart_of_accounts WHERE company_id=v_company AND system_key='CASH';

  INSERT INTO financial_accounts(company_id, gl_account_id, kind, name, bank_slug)
  VALUES(v_company, v_bank_gl, 'BANK', 'QA Bangkok Bank', 'bbl');

  BEGIN
    INSERT INTO financial_accounts(company_id, gl_account_id, kind, name)
    VALUES(v_company, v_bank_gl, 'BANK', 'Missing bank code');
    RAISE EXCEPTION 'BANK account without a bank code was accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO financial_accounts(company_id, gl_account_id, kind, name, bank_slug)
    VALUES(v_company, v_bank_gl, 'BANK', 'Unknown bank', 'unknown');
    RAISE EXCEPTION 'unknown bank logo identifier was accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO financial_accounts(company_id, gl_account_id, kind, name, bank_slug)
    VALUES(v_company, v_cash_gl, 'CASH', 'Cash with bank logo', 'bbl');
    RAISE EXCEPTION 'CASH account with a bank code was accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO financial_accounts(company_id, gl_account_id, kind, name, bank_slug, masked_number)
    VALUES(v_company, v_bank_gl, 'BANK', 'Unmasked account number', 'bbl', '1234567890');
    RAISE EXCEPTION 'unmasked account number was accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  SELECT name INTO v_error FROM bank_directory WHERE source_code='002' AND slug='bbl';
  IF v_error IS DISTINCT FROM 'Bangkok Bank' THEN
    RAISE EXCEPTION 'bank code/logo mapping is incorrect';
  END IF;
END;
$$;
