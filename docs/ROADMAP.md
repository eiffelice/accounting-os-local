# Roadmap

## v0.1 — Foundation
- [x] Multi-company / multi-branch
- [x] Multiple financial accounts
- [x] Company memberships
- [x] Chart of Accounts
- [x] Fiscal periods
- [x] Double-entry ledger
- [x] Audit / idempotency
- [x] Local dashboard
- [x] Local stdio MCP

## v0.2 — Human accounting workflow
- [x] Local login/session
- [x] Employee permission UI
- [x] Income/expense entry
- [x] Approval inbox
- [x] Human posting
- [x] Approval limit
- [x] Maker/poster separation for non-owner
- [x] Contacts/customers/vendors
- [x] Period close/reopen
- [x] Local documents
- [x] Backup/restore scripts + backup catalog verification
- [x] MCP remains draft-only

## v0.3 — Thai tax core
- [ ] Tax Rule Registry
- [ ] legal source/effective date/version
- [ ] VAT input/output ledger
- [ ] WHT rule engine + certificate data
- [ ] Tax Calendar
- [ ] Tax evidence trace
- [ ] accountant golden regression tests

## v0.4 — Security & AI control plane
- [x] password change UI + 12-character minimum
- [ ] stronger password policy / breach list
- [ ] lockout / brute-force control
- [ ] encrypted local document vault
- [ ] Windows DPAPI/Credential Manager integration
- [ ] central ABAC/PDP
- [ ] field-level masking policy
- [ ] SoD conflict matrix
- [ ] MCP adversarial suite
- [ ] provider DLP/redaction

## v0.5 — Filing/integration preparation
- [ ] immutable filing snapshots
- [ ] e-Tax/e-Receipt adapter boundary
- [ ] DBD mapping/XBRL
- [ ] certificate/signing boundary
- [ ] integration outbox/inbox
