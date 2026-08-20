-- Thai bank logo directory for financial-account branding.
-- Logo metadata is derived from omise/banks-logo at revision
-- 2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2 (MIT).
-- source_code is metadata from that repository, not an authoritative current
-- Bank of Thailand institution or payment-routing code.

BEGIN;

CREATE TABLE IF NOT EXISTS bank_directory (
  slug text PRIMARY KEY CHECK (slug ~ '^[a-z0-9]+$'),
  source_code text NOT NULL CHECK (source_code ~ '^[0-9]{3}$'),
  name text NOT NULL,
  brand_color text NOT NULL CHECK (brand_color ~ '^#[0-9a-fA-F]{6}$'),
  country_code char(2) NOT NULL DEFAULT 'TH' CHECK (country_code = 'TH'),
  source text NOT NULL DEFAULT 'omise/banks-logo',
  source_revision text NOT NULL,
  is_active boolean NOT NULL DEFAULT true
);

INSERT INTO bank_directory(slug, source_code, name, brand_color, source_revision)
VALUES
  ('bbl','002','Bangkok Bank','#1e4598','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('kbank','004','Kasikorn Bank','#138f2d','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('rbs','005','Royal Bank of Scotland','#032952','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('ktb','006','Krungthai Bank','#1ba5e1','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('jpm','008','J.P. Morgan','#321c10','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('mufg','010','Bank of Tokyo-Mitsubishi UFJ','#d61323','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('tmb','011','TMB Bank','#1279be','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('scb','014','Siam Commercial Bank','#4e2e7f','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('citi','017','Citibank','#1583c7','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('smbc','018','Sumitomo Mitsui Banking Corporation','#a0d235','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('sc','020','Standard Chartered (Thai)','#0f6ea1','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('cimb','022','CIMB Thai Bank','#7e2f36','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('uob','024','United Overseas Bank (Thai)','#0b3979','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('bay','025','Bank of Ayudhya (Krungsri)','#fec43b','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('mega','026','Mega International Commercial Bank','#815e3b','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('boa','027','Bank of America','#e11e3c','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('cacib','028','Credit Agricole','#0e765b','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('gsb','030','Government Savings Bank','#eb198d','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('hsbc','031','Hongkong and Shanghai Banking Corporation','#fd0d1b','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('db','032','Deutsche Bank','#0522a5','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('ghb','033','Government Housing Bank','#f57d23','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('baac','034','Bank for Agriculture and Agricultural Cooperatives','#4b9b1d','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('mb','039','Mizuho Bank','#150b78','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('bnp','045','BNP Paribas','#14925e','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('tbank','065','Thanachart Bank','#fc4f1f','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('ibank','066','Islamic Bank of Thailand','#184615','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('tisco','067','Tisco Bank','#12549f','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('kk','069','Kiatnakin Bank','#199cc5','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('icbc','070','Industrial and Commercial Bank of China (Thai)','#c50f1c','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('tcrb','071','Thai Credit Retail Bank','#0a4ab3','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('lhb','073','Land and Houses Bank','#6d6e71','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2'),
  ('ttb','076','TMBThanachart Bank','#ecf0f1','2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2')
ON CONFLICT (slug) DO UPDATE
SET source_code=excluded.source_code,
    name=excluded.name,
    brand_color=excluded.brand_color,
    source_revision=excluded.source_revision;

ALTER TABLE financial_accounts
  ADD COLUMN IF NOT EXISTS bank_slug text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname='financial_accounts_bank_slug_fkey'
      AND conrelid='financial_accounts'::regclass
  ) THEN
    ALTER TABLE financial_accounts
      ADD CONSTRAINT financial_accounts_bank_slug_fkey
      FOREIGN KEY (bank_slug) REFERENCES bank_directory(slug) ON UPDATE RESTRICT ON DELETE RESTRICT;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname='financial_accounts_bank_required_check'
      AND conrelid='financial_accounts'::regclass
  ) THEN
    ALTER TABLE financial_accounts
      ADD CONSTRAINT financial_accounts_bank_required_check
      CHECK (kind <> 'BANK' OR bank_slug IS NOT NULL) NOT VALID;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname='financial_accounts_cash_bank_check'
      AND conrelid='financial_accounts'::regclass
  ) THEN
    ALTER TABLE financial_accounts
      ADD CONSTRAINT financial_accounts_cash_bank_check
      CHECK (kind <> 'CASH' OR bank_slug IS NULL);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname='financial_accounts_masked_number_check'
      AND conrelid='financial_accounts'::regclass
  ) THEN
    ALTER TABLE financial_accounts
      ADD CONSTRAINT financial_accounts_masked_number_check
      CHECK (
        masked_number IS NULL OR (
          char_length(masked_number) BETWEEN 4 AND 80
          AND masked_number ~ '^[0-9Xx* .-]+$'
          AND masked_number ~ '[Xx*]'
        )
      ) NOT VALID;
  END IF;
END;
$$;

-- Exact-name backfill is intentionally conservative; unknown historical rows keep the fallback icon.
UPDATE financial_accounts fa
SET bank_slug=b.slug
FROM bank_directory b
WHERE fa.bank_slug IS NULL
  AND fa.institution IS NOT NULL
  AND lower(trim(fa.institution))=lower(b.name);

CREATE INDEX IF NOT EXISTS ix_financial_accounts_bank_slug
  ON financial_accounts(bank_slug)
  WHERE bank_slug IS NOT NULL;

COMMIT;
