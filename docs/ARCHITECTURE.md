# Architecture v0.2

```text
                        HUMAN AUTHORITY
                              │
                      Local Login/Session
                              │
                              ▼
                    Company Permission
                              │
            ┌─────────────────┼────────────────┐
            ▼                 ▼                ▼
      Human Web UI       MCP stdio        Documents
            │                 │                │
            │           Read + Draft       Local Disk
            │                 │                │
            └──────────────┬──┘                │
                           ▼                   │
                    Accounting Core ◄──────────┘
                           │
                    Approval Workflow
                           │
                    Human-only Posting
                           │
                           ▼
                    Canonical Ledger
                           │
                           ▼
                       PostgreSQL
                      127.0.0.1
                           │
                           ├── Audit Events
                           └── Idempotency
```

## Critical rules

1. Company scope is checked server-side.
2. MCP connection alone grants no accounting authority.
3. MCP cannot post or pay in v0.2.
4. Every human-created income/expense is a balanced DRAFT.
5. Posting requires an APPROVED approval request.
6. Non-owner maker cannot post their own journal.
7. Closed periods reject posting.
8. Period cannot close while DRAFT journals remain.
9. Posted/reversed journal core fields and lines are immutable.
10. Audit events cannot update/delete.


## Multi-financial-account invariant

New v0.2 journal lines may carry `financial_account_id`.

For such a line:

```text
financial_account.company_id = journal_line.company_id
financial_account.gl_account_id = journal_line.account_id
```

This lets several bank/cash/e-wallet/credit-card accounts map to control GL accounts while still producing a separate operational balance per financial account.

Historic v0.1 postings may have `financial_account_id = NULL` because the old schema did not record which bank sub-account was used. The migration does not guess this historical mapping.
