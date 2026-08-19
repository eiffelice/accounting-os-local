-- Accounting OS Local v0.3 tax patch
-- Correct DELETE behavior for immutable FINAL tax calculation records.

CREATE OR REPLACE FUNCTION protect_final_tax_calculation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status='FINAL' THEN
    RAISE EXCEPTION 'FINAL tax calculation is immutable; create a correcting record';
  END IF;

  IF TG_OP='DELETE' THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tax_calc_final_immutable ON tax_calculation_records;
CREATE TRIGGER trg_tax_calc_final_immutable
BEFORE UPDATE OR DELETE ON tax_calculation_records
FOR EACH ROW EXECUTE FUNCTION protect_final_tax_calculation();
