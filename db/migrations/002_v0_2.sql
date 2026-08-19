-- Accounting OS Local v0.2 migration
-- Safe to re-run on a v0.1 database.

ALTER TABLE app_users
  ADD COLUMN IF NOT EXISTS password_hash text,
  ADD COLUMN IF NOT EXISTS must_change_password boolean NOT NULL DEFAULT false;

UPDATE app_users
SET password_hash = 'pbkdf2_sha256$310000$OPzFto5+TsgnKtfvPjT5yw==$Cbbfq0dIcFEVbfIz/POFDhUnl92Rqp8PVMbYpnu8qW8='
WHERE email IN ('owner@local.accounting', 'accountant@local.accounting')
  AND password_hash IS NULL;

CREATE TABLE IF NOT EXISTS user_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_user_sessions_user ON user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_expiry ON user_sessions(expires_at);

CREATE TABLE IF NOT EXISTS contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  contact_type text NOT NULL CHECK (contact_type IN ('CUSTOMER','VENDOR','BOTH')),
  code text,
  display_name text NOT NULL,
  legal_name text,
  tax_id text,
  email text,
  phone text,
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid NOT NULL REFERENCES app_users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id, code)
);
CREATE INDEX IF NOT EXISTS idx_contacts_company ON contacts(company_id, display_name);

CREATE TABLE IF NOT EXISTS approval_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  resource_type text NOT NULL,
  resource_id uuid NOT NULL,
  action text NOT NULL CHECK (action IN ('POST_JOURNAL','CLOSE_PERIOD','REOPEN_PERIOD')),
  amount numeric(18,2),
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','APPROVED','REJECTED','CANCELLED')),
  requested_by uuid NOT NULL REFERENCES app_users(id),
  requested_at timestamptz NOT NULL DEFAULT now(),
  decided_by uuid REFERENCES app_users(id),
  decided_at timestamptz,
  decision_reason text,
  owner_override boolean NOT NULL DEFAULT false,
  UNIQUE(company_id, resource_type, resource_id, action)
);
CREATE INDEX IF NOT EXISTS idx_approval_company_status
  ON approval_requests(company_id, status, requested_at DESC);

CREATE TABLE IF NOT EXISTS local_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  original_name text NOT NULL,
  stored_name text NOT NULL,
  mime_type text NOT NULL,
  size_bytes bigint NOT NULL CHECK (size_bytes >= 0),
  sha256 text NOT NULL,
  local_relative_path text NOT NULL,
  uploaded_by uuid NOT NULL REFERENCES app_users(id),
  uploaded_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id, stored_name)
);
CREATE INDEX IF NOT EXISTS idx_documents_company_time
  ON local_documents(company_id, uploaded_at DESC);

ALTER TABLE fiscal_periods
  ADD COLUMN IF NOT EXISTS reopened_at timestamptz,
  ADD COLUMN IF NOT EXISTS reopened_by uuid REFERENCES app_users(id),
  ADD COLUMN IF NOT EXISTS close_reason text,
  ADD COLUMN IF NOT EXISTS reopen_reason text;

ALTER TABLE journal_lines
  ADD COLUMN IF NOT EXISTS financial_account_id uuid REFERENCES financial_accounts(id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_financial_account
  ON journal_lines(company_id, financial_account_id)
  WHERE financial_account_id IS NOT NULL;

INSERT INTO chart_of_accounts(company_id, code, name_th, account_type, system_key)
SELECT c.id, '2100', 'เจ้าหนี้บัตรเครดิต', 'LIABILITY', 'CREDIT_CARD_PAYABLE'
FROM companies c
WHERE NOT EXISTS (
  SELECT 1 FROM chart_of_accounts a
  WHERE a.company_id=c.id AND a.system_key='CREDIT_CARD_PAYABLE'
);

-- Posted/reversed journal headers are immutable except for controlled internal state transitions.
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
DROP TRIGGER IF EXISTS trg_journal_entry_immutable ON journal_entries;
DROP TRIGGER IF EXISTS trg_entries_no_mutate_posted ON journal_entries;
CREATE TRIGGER trg_journal_entry_immutable
BEFORE UPDATE OR DELETE ON journal_entries
FOR EACH ROW EXECUTE FUNCTION protect_posted_journal_entry();

-- Journal lines are writable only while the parent journal is DRAFT.
CREATE OR REPLACE FUNCTION guard_journal_line_write()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_entry_id uuid;
  v_status text;
  v_company uuid;
  v_fa_company uuid;
  v_fa_gl uuid;
BEGIN
  v_entry_id := CASE WHEN TG_OP='DELETE' THEN OLD.journal_entry_id ELSE NEW.journal_entry_id END;

  SELECT status, company_id INTO v_status, v_company
  FROM journal_entries
  WHERE id=v_entry_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'journal entry not found';
  END IF;
  IF v_status <> 'DRAFT' THEN
    RAISE EXCEPTION 'journal lines are writable only while journal is DRAFT';
  END IF;

  IF TG_OP <> 'DELETE' THEN
    IF NEW.company_id <> v_company THEN
      RAISE EXCEPTION 'journal line company mismatch';
    END IF;

    IF NEW.financial_account_id IS NOT NULL THEN
      SELECT company_id, gl_account_id INTO v_fa_company, v_fa_gl
      FROM financial_accounts
      WHERE id=NEW.financial_account_id AND is_active=true;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'financial account not found or inactive';
      END IF;
      IF v_fa_company <> NEW.company_id OR v_fa_gl <> NEW.account_id THEN
        RAISE EXCEPTION 'financial account must belong to same company and map to journal GL account';
      END IF;
    END IF;
  END IF;

  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END;
$$;
DROP TRIGGER IF EXISTS trg_lines_no_mutate_posted ON journal_lines;
DROP TRIGGER IF EXISTS trg_lines_guard_write ON journal_lines;
CREATE TRIGGER trg_lines_guard_write
BEFORE INSERT OR UPDATE OR DELETE ON journal_lines
FOR EACH ROW EXECUTE FUNCTION guard_journal_line_write();

CREATE OR REPLACE FUNCTION approve_post_request(
  p_request_id uuid,
  p_actor uuid,
  p_reason text
)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_req approval_requests%ROWTYPE;
  v_can_approve boolean;
  v_role text;
  v_limit numeric(18,2);
BEGIN
  SELECT * INTO v_req
  FROM approval_requests
  WHERE id=p_request_id
  FOR UPDATE;

  IF NOT FOUND OR v_req.status <> 'PENDING' THEN
    RAISE EXCEPTION 'approval request is not pending';
  END IF;

  SELECT can_approve, role, approval_limit
    INTO v_can_approve, v_role, v_limit
  FROM company_memberships
  WHERE user_id=p_actor
    AND company_id=v_req.company_id
    AND (expires_at IS NULL OR expires_at > now());

  IF COALESCE(v_can_approve,false)=false THEN
    RAISE EXCEPTION 'actor cannot approve for this company';
  END IF;
  IF v_limit IS NOT NULL AND v_req.amount IS NOT NULL AND v_req.amount > v_limit
     AND v_role <> 'OWNER' THEN
    RAISE EXCEPTION 'approval amount exceeds actor limit';
  END IF;

  UPDATE approval_requests
  SET status='APPROVED',
      decided_by=p_actor,
      decided_at=now(),
      decision_reason=p_reason,
      owner_override=(requested_by=p_actor AND v_role='OWNER')
  WHERE id=p_request_id;

  INSERT INTO audit_events(company_id, actor_user_id, event_type, resource_type, resource_id, payload)
  VALUES (
    v_req.company_id, p_actor, 'APPROVAL_APPROVED', 'approval_request', p_request_id::text,
    jsonb_build_object('action',v_req.action,'resource_id',v_req.resource_id,'reason',p_reason,
                       'owner_override',(v_req.requested_by=p_actor AND v_role='OWNER'))
  );
END;
$$;

CREATE OR REPLACE FUNCTION reject_post_request(
  p_request_id uuid,
  p_actor uuid,
  p_reason text
)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_req approval_requests%ROWTYPE;
  v_can_approve boolean;
BEGIN
  SELECT * INTO v_req
  FROM approval_requests
  WHERE id=p_request_id
  FOR UPDATE;

  IF NOT FOUND OR v_req.status <> 'PENDING' THEN
    RAISE EXCEPTION 'approval request is not pending';
  END IF;

  SELECT can_approve INTO v_can_approve
  FROM company_memberships
  WHERE user_id=p_actor
    AND company_id=v_req.company_id
    AND (expires_at IS NULL OR expires_at > now());

  IF COALESCE(v_can_approve,false)=false THEN
    RAISE EXCEPTION 'actor cannot reject for this company';
  END IF;

  UPDATE approval_requests
  SET status='REJECTED', decided_by=p_actor, decided_at=now(), decision_reason=p_reason
  WHERE id=p_request_id;

  INSERT INTO audit_events(company_id, actor_user_id, event_type, resource_type, resource_id, payload)
  VALUES (
    v_req.company_id, p_actor, 'APPROVAL_REJECTED', 'approval_request', p_request_id::text,
    jsonb_build_object('action',v_req.action,'resource_id',v_req.resource_id,'reason',p_reason)
  );
END;
$$;

-- All direct posting is hardened: approval + permission + open period + balance + company isolation.
CREATE OR REPLACE FUNCTION post_journal_entry(p_entry_id uuid, p_actor uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_company uuid;
  v_status text;
  v_date date;
  v_reversal_of uuid;
  v_debit numeric(18,2);
  v_credit numeric(18,2);
  v_count int;
  v_bad_accounts int;
  v_bad_financial_accounts int;
  v_period_count int;
  v_seq bigint;
  v_entry_no text;
  v_can_post boolean;
  v_approved_count int;
  v_approved_by uuid;
BEGIN
  SELECT company_id, status, txn_date, reversal_of
    INTO v_company, v_status, v_date, v_reversal_of
  FROM journal_entries
  WHERE id=p_entry_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'journal entry not found'; END IF;
  IF v_status <> 'DRAFT' THEN RAISE EXCEPTION 'only DRAFT entries can be posted'; END IF;

  SELECT can_post INTO v_can_post
  FROM company_memberships
  WHERE user_id=p_actor AND company_id=v_company
    AND (expires_at IS NULL OR expires_at > now());
  IF COALESCE(v_can_post,false)=false THEN
    RAISE EXCEPTION 'actor is not authorized to post for this company';
  END IF;

  SELECT count(*), max(decided_by)
    INTO v_approved_count, v_approved_by
  FROM approval_requests
  WHERE company_id=v_company
    AND resource_type='journal_entry'
    AND resource_id=p_entry_id
    AND action='POST_JOURNAL'
    AND status='APPROVED';
  IF v_approved_count <> 1 THEN
    RAISE EXCEPTION 'exactly one APPROVED POST_JOURNAL request is required';
  END IF;

  SELECT count(*) INTO v_period_count
  FROM fiscal_periods
  WHERE company_id=v_company AND status='OPEN'
    AND v_date BETWEEN start_date AND end_date;
  IF v_period_count <> 1 THEN
    RAISE EXCEPTION 'transaction date is not in exactly one OPEN fiscal period';
  END IF;

  SELECT count(*), COALESCE(sum(debit),0), COALESCE(sum(credit),0)
    INTO v_count, v_debit, v_credit
  FROM journal_lines
  WHERE journal_entry_id=p_entry_id;
  IF v_count < 2 THEN RAISE EXCEPTION 'journal requires at least two lines'; END IF;
  IF v_debit <= 0 OR v_debit <> v_credit THEN
    RAISE EXCEPTION 'journal is not balanced: debit %, credit %', v_debit, v_credit;
  END IF;

  SELECT count(*) INTO v_bad_accounts
  FROM journal_lines jl
  JOIN chart_of_accounts a ON a.id=jl.account_id
  WHERE jl.journal_entry_id=p_entry_id
    AND (jl.company_id<>v_company OR a.company_id<>v_company);
  IF v_bad_accounts > 0 THEN
    RAISE EXCEPTION 'cross-company journal line/account detected';
  END IF;

  SELECT count(*) INTO v_bad_financial_accounts
  FROM journal_lines jl
  JOIN financial_accounts fa ON fa.id=jl.financial_account_id
  WHERE jl.journal_entry_id=p_entry_id
    AND jl.financial_account_id IS NOT NULL
    AND (fa.company_id<>v_company OR fa.gl_account_id<>jl.account_id);
  IF v_bad_financial_accounts > 0 THEN
    RAISE EXCEPTION 'invalid financial account mapping detected';
  END IF;

  INSERT INTO company_sequences(company_id, sequence_name, next_value)
  VALUES(v_company,'JOURNAL',2)
  ON CONFLICT(company_id,sequence_name)
  DO UPDATE SET next_value=company_sequences.next_value+1
  RETURNING next_value-1 INTO v_seq;

  v_entry_no := 'JE-' || to_char(v_date,'YYYY') || '-' || lpad(v_seq::text,6,'0');

  UPDATE journal_entries
  SET status='POSTED', entry_no=v_entry_no, posted_at=now(),
      approved_by=v_approved_by, row_version=row_version+1
  WHERE id=p_entry_id;

  IF v_reversal_of IS NOT NULL THEN
    PERFORM set_config('accounting.internal_transition','on',true);
    UPDATE journal_entries
    SET status='REVERSED', row_version=row_version+1
    WHERE id=v_reversal_of AND status='POSTED';
    PERFORM set_config('accounting.internal_transition','off',true);

    INSERT INTO audit_events(company_id, actor_user_id, event_type, resource_type, resource_id, payload)
    VALUES(v_company,p_actor,'ORIGINAL_MARKED_REVERSED','journal_entry',v_reversal_of::text,
           jsonb_build_object('reversal_entry_id',p_entry_id));
  END IF;

  INSERT INTO audit_events(company_id, actor_user_id, event_type, resource_type, resource_id, payload)
  VALUES(v_company,p_actor,'JOURNAL_POSTED','journal_entry',p_entry_id::text,
         jsonb_build_object('entry_no',v_entry_no,'debit',v_debit,'credit',v_credit));

  RETURN v_entry_no;
END;
$$;

CREATE OR REPLACE FUNCTION post_approved_journal(p_entry_id uuid, p_actor uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_company uuid;
  v_creator uuid;
  v_role text;
  v_approved int;
  v_entry_no text;
BEGIN
  SELECT company_id, created_by INTO v_company, v_creator
  FROM journal_entries WHERE id=p_entry_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'journal entry not found'; END IF;

  SELECT role INTO v_role
  FROM company_memberships
  WHERE user_id=p_actor AND company_id=v_company
    AND (expires_at IS NULL OR expires_at > now());

  SELECT count(*) INTO v_approved
  FROM approval_requests
  WHERE company_id=v_company
    AND resource_type='journal_entry'
    AND resource_id=p_entry_id
    AND action='POST_JOURNAL'
    AND status='APPROVED';
  IF v_approved <> 1 THEN
    RAISE EXCEPTION 'approved POST_JOURNAL request is required';
  END IF;
  IF v_creator=p_actor AND v_role<>'OWNER' THEN
    RAISE EXCEPTION 'maker cannot post own journal unless OWNER override';
  END IF;

  v_entry_no := post_journal_entry(p_entry_id,p_actor);

  INSERT INTO audit_events(company_id, actor_user_id, event_type, resource_type, resource_id, payload)
  VALUES(v_company,p_actor,'APPROVED_JOURNAL_POSTED','journal_entry',p_entry_id::text,
         jsonb_build_object('entry_no',v_entry_no));
  RETURN v_entry_no;
END;
$$;

-- Reversal is a draft; it must go through the same approval/posting workflow.
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
  v_total numeric(18,2);
BEGIN
  SELECT * INTO v_original
  FROM journal_entries
  WHERE id=p_entry_id
  FOR UPDATE;
  IF NOT FOUND OR v_original.status<>'POSTED' THEN
    RAISE EXCEPTION 'only POSTED entries can be reversed';
  END IF;

  INSERT INTO journal_entries(
    company_id, branch_id, txn_date, status, source_type, source_id, memo,
    created_by, reversal_of
  ) VALUES(
    v_original.company_id, v_original.branch_id, p_reversal_date, 'DRAFT',
    'REVERSAL', p_entry_id::text, p_reason, p_actor, p_entry_id
  ) RETURNING id INTO v_new_id;

  FOR v_line IN
    SELECT * FROM journal_lines WHERE journal_entry_id=p_entry_id ORDER BY line_no
  LOOP
    INSERT INTO journal_lines(
      journal_entry_id, company_id, line_no, account_id, financial_account_id,
      description, debit, credit
    ) VALUES(
      v_new_id, v_original.company_id, v_line.line_no, v_line.account_id,
      v_line.financial_account_id, 'Reversal: '||v_line.description,
      v_line.credit, v_line.debit
    );
  END LOOP;

  SELECT sum(debit) INTO v_total
  FROM journal_lines WHERE journal_entry_id=v_new_id;

  INSERT INTO approval_requests(
    company_id, resource_type, resource_id, action, amount, requested_by
  ) VALUES(
    v_original.company_id,'journal_entry',v_new_id,'POST_JOURNAL',v_total,p_actor
  );

  INSERT INTO audit_events(company_id, actor_user_id, event_type, resource_type, resource_id, payload)
  VALUES(v_original.company_id,p_actor,'REVERSAL_DRAFT_CREATED','journal_entry',v_new_id::text,
         jsonb_build_object('reversal_of',p_entry_id,'reason',p_reason));

  RETURN v_new_id;
END;
$$;
