INSERT INTO app_users(email, display_name)
VALUES
  ('owner@local.accounting', 'Local Owner'),
  ('accountant@local.accounting', 'Demo Accountant');

INSERT INTO companies(code, legal_name, display_name, tax_id)
VALUES
  ('COMP-A', 'บริษัท ตัวอย่าง เอ จำกัด', 'บริษัท A', '0100000000001'),
  ('COMP-B', 'บริษัท ตัวอย่าง บี จำกัด', 'บริษัท B', '0100000000002');

INSERT INTO branches(company_id, code, name, is_head_office)
SELECT id, 'HQ', 'สำนักงานใหญ่', true FROM companies;

INSERT INTO company_memberships(user_id, company_id, role, can_read, can_create_draft, can_approve, can_post)
SELECT u.id, c.id, 'OWNER', true, true, true, true
FROM app_users u CROSS JOIN companies c
WHERE u.email = 'owner@local.accounting';

INSERT INTO company_memberships(user_id, company_id, role, can_read, can_create_draft, can_approve, can_post, approval_limit)
SELECT u.id, c.id, 'ACCOUNTANT', true, true, false, false, 50000
FROM app_users u
JOIN companies c ON c.code = 'COMP-A'
WHERE u.email = 'accountant@local.accounting';

INSERT INTO chart_of_accounts(company_id, code, name_th, account_type, system_key)
SELECT id, '1000', 'เงินสด', 'ASSET', 'CASH' FROM companies;
INSERT INTO chart_of_accounts(company_id, code, name_th, account_type, system_key)
SELECT id, '1100', 'เงินฝากธนาคาร', 'ASSET', 'BANK' FROM companies;
INSERT INTO chart_of_accounts(company_id, code, name_th, account_type, system_key)
SELECT id, '1200', 'ลูกหนี้การค้า', 'ASSET', 'AR' FROM companies;
INSERT INTO chart_of_accounts(company_id, code, name_th, account_type, system_key)
SELECT id, '2000', 'เจ้าหนี้การค้า', 'LIABILITY', 'AP' FROM companies;
INSERT INTO chart_of_accounts(company_id, code, name_th, account_type, system_key)
SELECT id, '3000', 'ทุน', 'EQUITY', 'EQUITY' FROM companies;
INSERT INTO chart_of_accounts(company_id, code, name_th, account_type, system_key)
SELECT id, '4000', 'รายได้จากการขาย/บริการ', 'REVENUE', 'REVENUE_MAIN' FROM companies;
INSERT INTO chart_of_accounts(company_id, code, name_th, account_type, system_key)
SELECT id, '5000', 'ค่าใช้จ่ายทั่วไป', 'EXPENSE', 'EXPENSE_GENERAL' FROM companies;
INSERT INTO chart_of_accounts(company_id, code, name_th, account_type, system_key)
SELECT id, '5100', 'ค่าสาธารณูปโภค', 'EXPENSE', 'EXPENSE_UTILITIES' FROM companies;
INSERT INTO chart_of_accounts(company_id, code, name_th, account_type, system_key)
SELECT id, '5200', 'ค่าโฆษณาและการตลาด', 'EXPENSE', 'EXPENSE_ADS' FROM companies;

INSERT INTO financial_accounts(company_id, branch_id, gl_account_id, kind, name, institution, masked_number)
SELECT c.id, b.id, a.id, 'BANK', 'บัญชีหลัก SCB', 'SCB', 'XXX-X-X1234-X'
FROM companies c
JOIN branches b ON b.company_id = c.id AND b.is_head_office
JOIN chart_of_accounts a ON a.company_id = c.id AND a.system_key = 'BANK'
WHERE c.code = 'COMP-A';

INSERT INTO financial_accounts(company_id, branch_id, gl_account_id, kind, name, institution, masked_number)
SELECT c.id, b.id, a.id, 'BANK', 'บัญชีค่าใช้จ่าย KBank', 'KBank', 'XXX-X-X5678-X'
FROM companies c
JOIN branches b ON b.company_id = c.id AND b.is_head_office
JOIN chart_of_accounts a ON a.company_id = c.id AND a.system_key = 'BANK'
WHERE c.code = 'COMP-A';

INSERT INTO financial_accounts(company_id, branch_id, gl_account_id, kind, name, institution, masked_number)
SELECT c.id, b.id, a.id, 'CASH', 'เงินสดย่อย', null, null
FROM companies c
JOIN branches b ON b.company_id = c.id AND b.is_head_office
JOIN chart_of_accounts a ON a.company_id = c.id AND a.system_key = 'CASH'
WHERE c.code = 'COMP-A';

INSERT INTO financial_accounts(company_id, branch_id, gl_account_id, kind, name, institution, masked_number)
SELECT c.id, b.id, a.id, 'BANK', 'บัญชีหลัก BBL', 'BBL', 'XXX-X-X9012-X'
FROM companies c
JOIN branches b ON b.company_id = c.id AND b.is_head_office
JOIN chart_of_accounts a ON a.company_id = c.id AND a.system_key = 'BANK'
WHERE c.code = 'COMP-B';

INSERT INTO fiscal_periods(company_id, period_key, start_date, end_date, status)
SELECT id, 'FY2026', DATE '2026-01-01', DATE '2026-12-31', 'OPEN'
FROM companies;

DO $$
DECLARE
  owner_id uuid;
  company_a uuid;
  bank_gl uuid;
  rev_gl uuid;
  util_gl uuid;
  ads_gl uuid;
  main_bank_fa uuid;
  e1 uuid;
  e2 uuid;
  e3 uuid;
BEGIN
  SELECT id INTO owner_id FROM app_users WHERE email='owner@local.accounting';
  SELECT id INTO company_a FROM companies WHERE code='COMP-A';
  SELECT id INTO bank_gl FROM chart_of_accounts WHERE company_id=company_a AND system_key='BANK';
  SELECT id INTO rev_gl FROM chart_of_accounts WHERE company_id=company_a AND system_key='REVENUE_MAIN';
  SELECT id INTO util_gl FROM chart_of_accounts WHERE company_id=company_a AND system_key='EXPENSE_UTILITIES';
  SELECT id INTO ads_gl FROM chart_of_accounts WHERE company_id=company_a AND system_key='EXPENSE_ADS';
  SELECT id INTO main_bank_fa FROM financial_accounts WHERE company_id=company_a AND kind='BANK' ORDER BY created_at LIMIT 1;

  INSERT INTO journal_entries(company_id, txn_date, memo, created_by)
  VALUES(company_a, DATE '2026-08-01', 'รับรายได้จากลูกค้า', owner_id)
  RETURNING id INTO e1;
  INSERT INTO journal_lines(journal_entry_id, company_id, line_no, account_id, financial_account_id, description, debit, credit)
  VALUES
    (e1, company_a, 1, bank_gl, main_bank_fa, 'เงินเข้าธนาคาร', 150000, 0),
    (e1, company_a, 2, rev_gl, NULL, 'รายได้บริการ', 0, 150000);
  PERFORM post_journal_entry(e1, owner_id);

  INSERT INTO journal_entries(company_id, txn_date, memo, created_by)
  VALUES(company_a, DATE '2026-08-05', 'ค่าไฟสำนักงาน', owner_id)
  RETURNING id INTO e2;
  INSERT INTO journal_lines(journal_entry_id, company_id, line_no, account_id, financial_account_id, description, debit, credit)
  VALUES
    (e2, company_a, 1, util_gl, NULL, 'ค่าไฟ', 1700, 0),
    (e2, company_a, 2, bank_gl, main_bank_fa, 'จ่ายจากธนาคาร', 0, 1700);
  PERFORM post_journal_entry(e2, owner_id);

  INSERT INTO journal_entries(company_id, txn_date, memo, created_by)
  VALUES(company_a, DATE '2026-08-10', 'ค่าโฆษณา', owner_id)
  RETURNING id INTO e3;
  INSERT INTO journal_lines(journal_entry_id, company_id, line_no, account_id, financial_account_id, description, debit, credit)
  VALUES
    (e3, company_a, 1, ads_gl, NULL, 'ค่าโฆษณาออนไลน์', 12000, 0),
    (e3, company_a, 2, bank_gl, main_bank_fa, 'จ่ายจากธนาคาร', 0, 12000);
  PERFORM post_journal_entry(e3, owner_id);
END $$;
