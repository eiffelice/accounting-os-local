-- v0.2 QA

-- 1. No unbalanced posted journals.
SELECT je.id, je.entry_no, sum(jl.debit) debit, sum(jl.credit) credit
FROM journal_entries je
JOIN journal_lines jl ON jl.journal_entry_id=je.id
WHERE je.status IN ('POSTED','REVERSED')
GROUP BY je.id, je.entry_no
HAVING sum(jl.debit) <> sum(jl.credit);

-- Expected: zero rows.

-- 2. No approval points at another company journal.
SELECT ar.id
FROM approval_requests ar
JOIN journal_entries je ON je.id=ar.resource_id AND ar.resource_type='journal_entry'
WHERE ar.company_id <> je.company_id;

-- Expected: zero rows.

-- 3. Session should never store raw token; only fixed sha256 hex.
SELECT id FROM user_sessions
WHERE length(token_hash) <> 64 OR token_hash !~ '^[0-9a-f]+$';

-- Expected: zero rows.

-- 4. Local document path should be relative.
SELECT id, local_relative_path FROM local_documents
WHERE local_relative_path LIKE '/%' OR local_relative_path ~ '^[A-Za-z]:';

-- Expected: zero rows.

-- 5. Review critical unresolved SoD.
SELECT u.email, c.code, m.role, m.can_create_draft, m.can_approve, m.can_post
FROM company_memberships m
JOIN app_users u ON u.id=m.user_id
JOIN companies c ON c.id=m.company_id
WHERE m.can_create_draft AND m.can_approve AND m.can_post AND m.role <> 'OWNER';

-- Expected for production: zero rows. Demo may be configured differently by owner.

-- 6. Financial account tag must map to same company and control GL.
SELECT jl.id
FROM journal_lines jl
JOIN financial_accounts fa ON fa.id=jl.financial_account_id
WHERE jl.financial_account_id IS NOT NULL
  AND (fa.company_id <> jl.company_id OR fa.gl_account_id <> jl.account_id);

-- Expected: zero rows.

-- 7. No v0.2 workflow journal should be posted without approved request.
SELECT je.id, je.entry_no
FROM journal_entries je
WHERE je.source_type IN ('HUMAN_UI_DRAFT','AI_MCP_DRAFT','REVERSAL')
  AND je.status IN ('POSTED','REVERSED')
  AND NOT EXISTS (
    SELECT 1 FROM approval_requests ar
    WHERE ar.company_id=je.company_id
      AND ar.resource_type='journal_entry'
      AND ar.resource_id=je.id
      AND ar.action='POST_JOURNAL'
      AND ar.status='APPROVED'
  );

-- Expected: zero rows.
