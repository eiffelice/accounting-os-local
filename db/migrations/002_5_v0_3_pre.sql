-- Accounting OS Local v0.3 pre-migration
-- Allows 003_v0_3_tax.sql to be re-run after immutable-rule triggers already exist.

DO $$
BEGIN
  IF to_regclass('public.tax_rule_versions') IS NOT NULL THEN
    EXECUTE 'DROP TRIGGER IF EXISTS trg_tax_rule_immutable ON tax_rule_versions';
  END IF;
END;
$$;
