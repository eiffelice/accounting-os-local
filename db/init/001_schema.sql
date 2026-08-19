CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE app_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE,
  display_name text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  legal_name text NOT NULL,
  display_name text NOT NULL,
  tax_id text,
  base_currency char(3) NOT NULL DEFAULT 'THB',
  fiscal_year_start_month smallint NOT NULL DEFAULT 1 CHECK (fiscal_year_start_month BETWEEN 1 AND 12),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE branches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  code text NOT NULL,
  name text NOT NULL,
  is_head_office boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  UNIQUE(company_id, code)
);

CREATE TABLE company_memberships (
  user_id uuid NOT NULL REFERENCES app_users(id),
  company_id uuid NOT NULL REFERENCES companies(id),
  role text NOT NULL CHECK (role IN ('OWNER','CFO','ACCOUNTING_MANAGER','ACCOUNTANT','STAFF','AUDITOR')),
  can_read boolean NOT NULL DEFAULT true,
  can_create_draft boolean NOT NULL DEFAULT false,
  can_approve boolean NOT NULL DEFAULT false,
  can_post boolean NOT NULL DEFAULT false,
  approval_limit numeric(18,2),
  expires_at timestamptz,
  PRIMARY KEY(user_id, company_id)
);

CREATE TABLE chart_of_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  code text NOT NULL,
  name_th text NOT NULL,
  account_type text NOT NULL CHECK (account_type IN ('ASSET','LIABILITY','EQUITY','REVENUE','EXPENSE')),
  parent_id uuid REFERENCES chart_of_accounts(id),
  system_key text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id, code),
  UNIQUE(company_id, system_key)
);

CREATE TABLE financial_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  branch_id uuid REFERENCES branches(id),
  gl_account_id uuid NOT NULL REFERENCES chart_of_accounts(id),
  kind text NOT NULL CHECK (kind IN ('BANK','CASH','E_WALLET','CREDIT_CARD')),
  name text NOT NULL,
  institution text,
  masked_number text,
  currency char(3) NOT NULL DEFAULT 'THB',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE fiscal_periods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  period_key text NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  status text NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','CLOSED')),
  closed_at timestamptz,
  closed_by uuid REFERENCES app_users(id),
  UNIQUE(company_id, period_key),
  CHECK (end_date >= start_date)
);

CREATE TABLE journal_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  branch_id uuid REFERENCES branches(id),
  entry_no text,
  txn_date date NOT NULL,
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','POSTED','REVERSED')),
  source_type text NOT NULL DEFAULT 'MANUAL',
  source_id text,
  memo text NOT NULL,
  created_by uuid NOT NULL REFERENCES app_users(id),
  approved_by uuid REFERENCES app_users(id),
  posted_at timestamptz,
  reversal_of uuid REFERENCES journal_entries(id),
  idempotency_key text,
  row_version bigint NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id, idempotency_key)
);

CREATE TABLE journal_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journal_entry_id uuid NOT NULL REFERENCES journal_entries(id) ON DELETE RESTRICT,
  company_id uuid NOT NULL REFERENCES companies(id),
  line_no integer NOT NULL CHECK (line_no > 0),
  account_id uuid NOT NULL REFERENCES chart_of_accounts(id),
  financial_account_id uuid REFERENCES financial_accounts(id),
  description text NOT NULL,
  debit numeric(18,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
  credit numeric(18,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(journal_entry_id, line_no),
  CHECK ((debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0))
);

CREATE TABLE company_sequences (
  company_id uuid NOT NULL REFERENCES companies(id),
  sequence_name text NOT NULL,
  next_value bigint NOT NULL DEFAULT 1 CHECK (next_value > 0),
  PRIMARY KEY(company_id, sequence_name)
);

CREATE TABLE idempotency_registry (
  company_id uuid NOT NULL REFERENCES companies(id),
  operation text NOT NULL,
  idempotency_key text NOT NULL,
  payload_hash text NOT NULL,
  resource_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(company_id, operation, idempotency_key)
);

CREATE TABLE audit_events (
  id bigserial PRIMARY KEY,
  company_id uuid REFERENCES companies(id),
  actor_user_id uuid REFERENCES app_users(id),
  event_type text NOT NULL,
  resource_type text NOT NULL,
  resource_id text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_journal_entries_company_date ON journal_entries(company_id, txn_date DESC);
CREATE INDEX idx_journal_lines_company_account ON journal_lines(company_id, account_id);
CREATE INDEX idx_audit_company_time ON audit_events(company_id, occurred_at DESC);

CREATE OR REPLACE FUNCTION prevent_audit_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'audit_events are append-only';
END;
$$;

CREATE TRIGGER trg_audit_no_update
BEFORE UPDATE OR DELETE ON audit_events
FOR EACH ROW EXECUTE FUNCTION prevent_audit_mutation();

CREATE OR REPLACE FUNCTION prevent_posted_line_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  st text;
BEGIN
  SELECT status INTO st
  FROM journal_entries
  WHERE id = COALESCE(OLD.journal_entry_id, NEW.journal_entry_id);

  IF st IN ('POSTED','REVERSED') THEN
    RAISE EXCEPTION 'posted/reversed journal lines are immutable';
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_lines_no_mutate_posted
BEFORE INSERT OR UPDATE OR DELETE ON journal_lines
FOR EACH ROW EXECUTE FUNCTION prevent_posted_line_mutation();

CREATE OR REPLACE FUNCTION validate_journal_line_company()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_entry_company uuid;
  v_account_company uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  SELECT company_id INTO v_entry_company
  FROM journal_entries
  WHERE id = NEW.journal_entry_id;

  SELECT company_id INTO v_account_company
  FROM chart_of_accounts
  WHERE id = NEW.account_id;

  IF v_entry_company IS NULL OR v_account_company IS NULL THEN
    RAISE EXCEPTION 'journal entry/account not found';
  END IF;

  IF NEW.company_id <> v_entry_company OR NEW.company_id <> v_account_company THEN
    RAISE EXCEPTION 'cross-company journal line rejected';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_lines_company_integrity
BEFORE INSERT OR UPDATE ON journal_lines
FOR EACH ROW EXECUTE FUNCTION validate_journal_line_company();

CREATE OR REPLACE FUNCTION protect_posted_journal_entry()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'DRAFT' THEN
      RAISE EXCEPTION 'posted/reversed journal entries cannot be deleted';
    END IF;
    RETURN OLD;
  END IF;

  IF OLD.status IN ('POSTED','REVERSED')
     AND COALESCE(current_setting('accounting.internal_transition', true), 'off') <> 'on' THEN
    RAISE EXCEPTION 'posted/reversed journal entries are immutable';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_journal_entry_immutable
BEFORE UPDATE OR DELETE ON journal_entries
FOR EACH ROW EXECUTE FUNCTION protect_posted_journal_entry();

CREATE OR REPLACE FUNCTION post_journal_entry(p_entry_id uuid, p_actor uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_company uuid;
  v_status text;
  v_date date;
  v_debit numeric(18,2);
  v_credit numeric(18,2);
  v_count int;
  v_bad_accounts int;
  v_period_count int;
  v_seq bigint;
  v_entry_no text;
  v_can_post boolean;
BEGIN
  SELECT company_id, status, txn_date
    INTO v_company, v_status, v_date
  FROM journal_entries
  WHERE id = p_entry_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'journal entry not found';
  END IF;

  IF v_status <> 'DRAFT' THEN
    RAISE EXCEPTION 'only DRAFT entries can be posted';
  END IF;

  SELECT can_post INTO v_can_post
  FROM company_memberships
  WHERE user_id = p_actor
    AND company_id = v_company
    AND (expires_at IS NULL OR expires_at > now());

  IF COALESCE(v_can_post, false) = false THEN
    RAISE EXCEPTION 'actor is not authorized to post for this company';
  END IF;

  SELECT count(*) INTO v_period_count
  FROM fiscal_periods
  WHERE company_id = v_company
    AND status = 'OPEN'
    AND v_date BETWEEN start_date AND end_date;

  IF v_period_count <> 1 THEN
    RAISE EXCEPTION 'transaction date is not in exactly one OPEN fiscal period';
  END IF;

  SELECT count(*), COALESCE(sum(debit),0), COALESCE(sum(credit),0)
    INTO v_count, v_debit, v_credit
  FROM journal_lines
  WHERE journal_entry_id = p_entry_id;

  IF v_count < 2 THEN
    RAISE EXCEPTION 'journal requires at least two lines';
  END IF;

  IF v_debit <= 0 OR v_debit <> v_credit THEN
    RAISE EXCEPTION 'journal is not balanced: debit %, credit %', v_debit, v_credit;
  END IF;

  SELECT count(*) INTO v_bad_accounts
  FROM journal_lines jl
  JOIN chart_of_accounts a ON a.id = jl.account_id
  WHERE jl.journal_entry_id = p_entry_id
    AND (jl.company_id <> v_company OR a.company_id <> v_company);

  IF v_bad_accounts > 0 THEN
    RAISE EXCEPTION 'cross-company journal line/account detected';
  END IF;

  INSERT INTO company_sequences(company_id, sequence_name, next_value)
  VALUES (v_company, 'JOURNAL', 2)
  ON CONFLICT (company_id, sequence_name)
  DO UPDATE SET next_value = company_sequences.next_value + 1
  RETURNING next_value - 1 INTO v_seq;

  v_entry_no := 'JE-' || to_char(v_date, 'YYYY') || '-' || lpad(v_seq::text, 6, '0');

  UPDATE journal_entries
  SET status = 'POSTED',
      entry_no = v_entry_no,
      posted_at = now(),
      approved_by = COALESCE(approved_by, p_actor),
      row_version = row_version + 1
  WHERE id = p_entry_id;

  INSERT INTO audit_events(company_id, actor_user_id, event_type, resource_type, resource_id, payload)
  VALUES (
    v_company, p_actor, 'JOURNAL_POSTED', 'journal_entry', p_entry_id::text,
    jsonb_build_object('entry_no', v_entry_no, 'debit', v_debit, 'credit', v_credit)
  );

  RETURN v_entry_no;
END;
$$;

CREATE OR REPLACE FUNCTION reverse_journal_entry(
  p_entry_id uuid,
  p_actor uuid,
  p_reversal_date date,
  p_reason text
)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_original journal_entries%ROWTYPE;
  v_new_id uuid;
  v_line record;
BEGIN
  SELECT * INTO v_original
  FROM journal_entries
  WHERE id = p_entry_id
  FOR UPDATE;

  IF NOT FOUND OR v_original.status <> 'POSTED' THEN
    RAISE EXCEPTION 'only POSTED entries can be reversed';
  END IF;

  INSERT INTO journal_entries(
    company_id, branch_id, txn_date, status, source_type, source_id, memo,
    created_by, reversal_of
  )
  VALUES (
    v_original.company_id, v_original.branch_id, p_reversal_date, 'DRAFT',
    'REVERSAL', p_entry_id::text, p_reason, p_actor, p_entry_id
  )
  RETURNING id INTO v_new_id;

  FOR v_line IN
    SELECT * FROM journal_lines WHERE journal_entry_id = p_entry_id ORDER BY line_no
  LOOP
    INSERT INTO journal_lines(
      journal_entry_id, company_id, line_no, account_id, description, debit, credit
    )
    VALUES (
      v_new_id, v_original.company_id, v_line.line_no, v_line.account_id,
      'Reversal: ' || v_line.description, v_line.credit, v_line.debit
    );
  END LOOP;

  PERFORM post_journal_entry(v_new_id, p_actor);

  PERFORM set_config('accounting.internal_transition', 'on', true);

  UPDATE journal_entries
  SET status = 'REVERSED',
      row_version = row_version + 1
  WHERE id = p_entry_id;

  PERFORM set_config('accounting.internal_transition', 'off', true);

  INSERT INTO audit_events(company_id, actor_user_id, event_type, resource_type, resource_id, payload)
  VALUES (
    v_original.company_id, p_actor, 'JOURNAL_REVERSED', 'journal_entry', p_entry_id::text,
    jsonb_build_object('reversal_entry_id', v_new_id, 'reason', p_reason)
  );

  RETURN v_new_id;
END;
$$;
