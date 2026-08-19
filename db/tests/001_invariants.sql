-- Manual QA queries. Run inside psql after local DB starts.

-- Must return zero rows: unbalanced posted journals.
SELECT je.id, je.entry_no, sum(jl.debit) debit, sum(jl.credit) credit
FROM journal_entries je
JOIN journal_lines jl ON jl.journal_entry_id = je.id
WHERE je.status IN ('POSTED','REVERSED')
GROUP BY je.id, je.entry_no
HAVING sum(jl.debit) <> sum(jl.credit);

-- Must return zero rows: cross-company account usage.
SELECT jl.id
FROM journal_lines jl
JOIN chart_of_accounts a ON a.id = jl.account_id
JOIN journal_entries je ON je.id = jl.journal_entry_id
WHERE jl.company_id <> je.company_id OR a.company_id <> je.company_id;

-- Review company/account isolation.
SELECT c.code, fa.kind, fa.name, fa.masked_number
FROM financial_accounts fa
JOIN companies c ON c.id = fa.company_id
ORDER BY c.code, fa.name;
