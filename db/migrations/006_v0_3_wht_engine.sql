-- Accounting OS Local v0.3 — deterministic WHT engine
-- Contract threshold is evaluated against total contract amount.

CREATE OR REPLACE FUNCTION tax_wht_breakdown(
  p_withholding_base numeric,
  p_contract_total numeric,
  p_rate_bps integer,
  p_contract_threshold numeric
) RETURNS TABLE(
  contract_qualifies boolean,
  tax_amount numeric(18,2)
)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_qualifies boolean;
  v_tax numeric(18,2);
BEGIN
  IF p_withholding_base < 0 THEN
    RAISE EXCEPTION 'withholding base must be >= 0';
  END IF;
  IF p_contract_total < 0 THEN
    RAISE EXCEPTION 'contract total must be >= 0';
  END IF;
  IF p_contract_total < p_withholding_base THEN
    RAISE EXCEPTION 'contract total must be >= withholding base';
  END IF;
  IF p_rate_bps < 0 OR p_rate_bps > 10000 THEN
    RAISE EXCEPTION 'invalid rate_bps';
  END IF;
  IF p_contract_threshold < 0 THEN
    RAISE EXCEPTION 'contract threshold must be >= 0';
  END IF;

  v_qualifies := p_contract_total >= p_contract_threshold;
  v_tax := CASE
    WHEN v_qualifies THEN tax_percent_amount(p_withholding_base, p_rate_bps)
    ELSE 0.00::numeric(18,2)
  END;

  RETURN QUERY SELECT v_qualifies, v_tax;
END;
$$;
