# Security Notes v0.1

## Local-only defaults

PostgreSQL is published as:

```text
127.0.0.1:5432
```

not `0.0.0.0`.

MCP uses stdio, so it is not listening on a network port.

## Secret handling

The demo password in `.env.example` is only for a local development database. v0.2 must move provider/API secrets to a local encrypted vault (Windows DPAPI / Credential Manager or dedicated vault).

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

- Real login/session management
- Central ABAC/PDP
- field-level masking policy
- encrypted local document store
- local DLP
- step-up authentication
- approval workflow
- backup restore verification
- adversarial MCP/prompt-injection suite
