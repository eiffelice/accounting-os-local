-- Accounting OS Local v0.3 — WHT threshold correction
-- TP.4/2528 clause 12/7: the contract amount must be at least THB 1,000,
-- even when an individual installment is less than THB 1,000.
-- Preserve the earlier seed as REVIEW_REQUIRED and introduce a verified v2.

BEGIN;

DROP TRIGGER IF EXISTS trg_tax_rule_immutable ON tax_rule_versions;

UPDATE tax_rule_versions
SET verification_status='REVIEW_REQUIRED',
    effective_to='2016-08-05',
    metadata = metadata || '{"superseded_reason":"Incorrect contract-threshold seed; do not use for filing."}'::jsonb
WHERE tax_type='WHT'
  AND rule_code IN ('WHT_SERVICE','WHT_RENT','WHT_ADVERTISING')
  AND version=1;

INSERT INTO tax_rule_versions(
  tax_type, rule_code, version, name_th, description_th, rate_bps,
  effective_from, effective_to, transaction_type, payer_type, payee_type,
  threshold_amount, form_code_individual, form_code_legal_entity,
  legal_reference, source_url, source_checked_at, verification_status, metadata
) VALUES
(
  'WHT','WHT_SERVICE',2,'หัก ณ ที่จ่าย — ค่าบริการ 3%',
  'ค่าบริการที่เข้าเกณฑ์ โดยตรวจยอดตามสัญญาตั้งแต่ 1,000 บาทขึ้นไป แม้แบ่งจ่ายแต่ละครั้งต่ำกว่า 1,000 บาท',
  300,'2016-08-06',NULL,'SERVICE','LEGAL_ENTITY','BOTH',1000,'PND3','PND53',
  'คำสั่งกรมสรรพากร ที่ ท.ป.4/2528 ข้อ 12/7 และข้อที่กำหนดอัตราค่าบริการ',
  'https://www.rd.go.th/3479.html','2026-08-20','VERIFIED',
  '{"threshold_basis":"contract_total","classification_required":true}'::jsonb
),
(
  'WHT','WHT_RENT',2,'หัก ณ ที่จ่าย — ค่าเช่า 5%',
  'ค่าเช่าที่เข้าเกณฑ์ โดยตรวจยอดตามสัญญาตั้งแต่ 1,000 บาทขึ้นไป แม้แบ่งจ่ายแต่ละครั้งต่ำกว่า 1,000 บาท',
  500,'2016-08-06',NULL,'RENT','LEGAL_ENTITY','BOTH',1000,'PND3','PND53',
  'คำสั่งกรมสรรพากร ที่ ท.ป.4/2528 ข้อ 6 และข้อ 12/7',
  'https://www.rd.go.th/3479.html','2026-08-20','VERIFIED',
  '{"threshold_basis":"contract_total","classification_required":true}'::jsonb
),
(
  'WHT','WHT_ADVERTISING',2,'หัก ณ ที่จ่าย — ค่าโฆษณา 2%',
  'ค่าโฆษณาที่เข้าเกณฑ์ โดยตรวจยอดตามสัญญาตั้งแต่ 1,000 บาทขึ้นไป แม้แบ่งจ่ายแต่ละครั้งต่ำกว่า 1,000 บาท',
  200,'2016-08-06',NULL,'ADVERTISING','LEGAL_ENTITY','BOTH',1000,'PND3','PND53',
  'คำสั่งกรมสรรพากร ที่ ท.ป.4/2528 ข้อ 10 และข้อ 12/7',
  'https://www.rd.go.th/3479.html','2026-08-20','VERIFIED',
  '{"threshold_basis":"contract_total","classification_required":true}'::jsonb
)
ON CONFLICT (country_code, tax_type, rule_code, version) DO NOTHING;

DROP TRIGGER IF EXISTS trg_tax_rule_immutable ON tax_rule_versions;
CREATE TRIGGER trg_tax_rule_immutable
BEFORE UPDATE OR DELETE ON tax_rule_versions
FOR EACH ROW EXECUTE FUNCTION prevent_tax_rule_mutation();

COMMIT;
