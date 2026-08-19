# Accounting OS Local v0.2

Local-first accounting system for **multiple companies and multiple financial accounts** with a human approval workflow and local MCP integration.

## New in v0.2

- Local login/session (HTTP-only cookie)
- Password change flow that revokes existing sessions
- Add unlimited local companies
- Add multiple bank/cash/e-wallet/credit-card accounts per company
- Per-financial-account ledger tagging and balances
- Employee/company permission UI
- Create local employee accounts with temporary passwords
- First-login password change flow
- Audit Log UI
- Income and expense entry forms
- Draft → Approval → Human Post workflow
- Maker/poster separation for non-owner users
- Approval limits
- Customers/vendors master data
- Fiscal period close/reopen controls
- Local document upload (PDF/JPG/PNG, max 10 MB)
- SHA-256 document evidence
- Local backup + restore using container-side binary dump + catalog verification
- MCP stays read + draft only
- MCP stdio server for local AI clients

## Local-only data path

```text
Browser
  ↓
Next.js localhost
  ↓
Accounting Core
  ↓
PostgreSQL 127.0.0.1
  ├── Ledger
  ├── Contacts
  ├── Permissions
  ├── Approval
  └── Audit

Local documents → ./data/documents
Local backups   → ./backups

AI host
  ↓
MCP stdio
  ↓
Permission check
  ↓
Read / create Draft only
```

## Start on Windows

Requirements:
- Docker Desktop
- Node.js 20.9+
- PowerShell

```powershell
git clone https://github.com/eiffelice/accounting-os-local.git
cd accounting-os-local
.\start-local.ps1
```

Open:

```text
http://localhost:3000
```

### Demo login

```text
owner@local.accounting
change-me-now
```

**Change the demo password before putting real accounting data into the system.**

## Existing v0.1 database

`start-local.ps1` applies the idempotent v0.2 migration automatically.

You can also run:

```powershell
.\migrate-local.ps1
```

## Backup

```powershell
.\backup-local.ps1
```

The script creates a local PostgreSQL custom-format dump and verifies the backup catalog.

## Restore

```powershell
.\restore-local.ps1 -BackupFile ".\backups\accounting-os-YYYYMMDD-HHMMSS.dump"
```

Restore is destructive and requires typing `RESTORE`.

## Human accounting flow

```text
Employee creates Expense/Income
        ↓
Balanced Journal DRAFT
        ↓
Approval Request
        ↓
Checker approves
        ↓
Authorized human clicks Post
        ↓
DB validates:
- permission
- approval
- open fiscal period
- debit = credit
- same company
        ↓
Canonical Posted Ledger
        ↓
Append-only Audit
```

## MCP tools

Exposed:
- `company_list`
- `financial_account_list`
- `report_trial_balance`
- `journal_recent`
- `expense_create_draft`

Not exposed:
- `journal_post`
- `payment_execute`
- `tax_submit`
- `secret_read`
- generic SQL/filesystem

## Local secrets and data

The repository intentionally excludes:
- `.env`
- `data/`
- `backups/`
- `node_modules/`
- build output

Only `.env.example` is committed.

## v0.3 target

Thai tax core:
- Tax Rule Registry
- VAT input/output
- WHT
- tax evidence/provenance
- tax calendar
- golden regression tests
