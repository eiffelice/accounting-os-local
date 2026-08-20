# Accounting OS Local v0.3

Local-first accounting system for **multiple companies and multiple financial accounts** with a human approval workflow, deterministic Thai tax core, and local MCP integration.

## New in v0.3 — Thai Tax Core

- Versioned Tax Rule Registry with effective dates
- Immutable tax-rule history: corrections create a new rule version
- Official Revenue Department provenance stored with verified rules
- Deterministic VAT calculation using PostgreSQL `NUMERIC`
- VAT exclusive / inclusive breakdown
- Current VAT rule versioning across effective periods
- WHT rules currently supported for service, rent, and advertising
- WHT contract-threshold logic based on **contract total**, not only the current installment
- Deterministic split-payment WHT through PostgreSQL `tax_wht_breakdown()`
- Company tax profiles
- Tax control accounts: input VAT, output VAT, WHT receivable, WHT payable
- Base tax calendar for PND3 / PND53 / PP30 with explicit official-calendar verification warning
- Tax calculation record table with immutable `FINAL` records
- Tax dashboard in the Web UI
- Golden SQL regression tests for VAT/WHT invariants
- MCP tax tools are **read / calculate only**
- AI tax filing remains disabled

## v0.2 foundation retained

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

## Single Source of Truth

```text
Browser / AI host
      ↓
Web / MCP
      ↓
Accounting + Tax Core
      ↓
PostgreSQL 127.0.0.1
  ├── Canonical Ledger
  ├── Tax Rule Registry
  ├── Tax Calculation Engine
  ├── Tax Evidence / Provenance
  ├── Contacts
  ├── Permissions
  ├── Approval
  └── Audit

Local documents → ./data/documents
Local backups   → ./backups
```

AI is never the accounting or tax calculation source of truth. The Web UI and MCP clients call the same deterministic database functions.

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

### Initial login

```text
.\start-local.ps1
```

The first startup creates a random database password in `.env` and prints a one-time
initial admin password. Use it once, then change it before entering real data.

## Upgrade an existing local database

```powershell
git pull
.\migrate-local.ps1
```

The v0.3.1 migration runner records `schema_migrations` checksums and skips
already-applied migrations. It applies:

```text
002_v0_2.sql
002_5_v0_3_pre.sql
003_v0_3_tax.sql
004_v0_3_tax_patch.sql
005_v0_3_wht_contract_threshold.sql
006_v0_3_wht_engine.sql
007_v0_3_1_security_accounting_hardening.sql
        ↓
qa_v0_3_tax.sql
```

`qa_v0_3_tax.sql` fails fast if a golden accounting/tax invariant regresses.

## Thai tax rules currently implemented

### VAT

The engine resolves VAT by transaction date from `tax_rule_versions` rather than hardcoding one global constant.

Supported calculation modes:
- `EXCLUSIVE`
- `INCLUSIVE`

Examples at a 7% resolved rule:
- 1,000 exclusive → base 1,000 / VAT 70 / gross 1,070
- 1,070 inclusive → base 1,000 / VAT 70 / gross 1,070

### WHT

Currently supported transaction classes:
- service — 3%
- rent — 5%
- advertising — 2%

The supported WHT path evaluates the **total contract amount** against the THB 1,000 contract threshold. Example: a THB 500 installment under a THB 1,500 contract still qualifies for withholding; the withholding amount is calculated on the relevant payment/base amount.

WHT classification, payer/payee status, exceptions, and the real transaction documents must still be verified before filing.

## Tax calendar

The engine stores a **base schedule** for:
- PND3
- PND53
- PP30

Actual legal filing dates may move because of holidays or Revenue Department extension announcements. The system intentionally labels generated dates as requiring official-calendar verification before filing.

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

Accounting:
- `company_list`
- `financial_account_list`
- `report_trial_balance`
- `journal_recent`
- `expense_create_draft`

Thai Tax Core:
- `tax_rule_list`
- `tax_calculate_vat`
- `tax_calculate_wht`
- `tax_calendar_month`

Not exposed:
- `journal_post`
- `payment_execute`
- `tax_submit`
- tax return filing
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

## Before real accounting/tax use

Run locally:

```powershell
.\migrate-local.ps1
npm run typecheck
npm run build
.\start-local.ps1
```

The repository contains code-level safeguards and SQL golden tests, but a clean runtime migration/build test on the target Windows machine is still required before treating the release as production-verified.

## Next target — v0.3.1 / v0.4

- Wire VAT/WHT calculations directly into accounting transaction drafts
- Input/output VAT subledgers and PP30 working report
- WHT certificate / PND working datasets
- Tax evidence attachment links and calculation hashes
- Tax profile editor and VAT registration settings
- Tax-period close / correction workflow
- Accountant acceptance test pack
- Expanded Thai tax-rule coverage with official-source review
