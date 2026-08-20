# Security Notes v0.3.1

## Local-only defaults

PostgreSQL is published as:

```text
127.0.0.1:5432
```

not `0.0.0.0`.

MCP uses stdio, so it is not listening on a network port.

## Secret handling

Startup creates a random database password and a one-time admin password. Accounts
that still use the legacy public demo hash are disabled by migration. MCP credentials
are random, hashed at rest, and remain unusable until the linked user changes the
temporary password.

Never expose:
- database passwords,
- AI API keys,
- bank credentials,
- signing keys,
- raw private certificates,
through MCP tools.

## AI permission rule

```text
Effective AI permission <= effective employee permission
```

An AI client must never become an administrator simply because it connected successfully.

## Production gates not completed yet

- Central ABAC/PDP
- field-level masking policy
- encrypted local document store
- local DLP
- step-up authentication
- adversarial MCP/prompt-injection suite
